`timescale 1ns/1ps
// Independently enabled serial effects: echo -> normalized room -> tremolo.
// Each mix is a bounded weighted average; existing output limiter remains last.
module audio_effects #(
 parameter integer CHORUS_ENABLE=0,
 parameter [31:0] CHORUS_PHASE=0,
 parameter integer ECHO_ENABLE=1,DELAY_SAMPLES=7200,MAX_DELAY_SAMPLES=24000,D0=1499,D1=1601,D2=1867,D3=2053,
 ECHO_WET=64,ROOM_WET=64,TREMOLO_MIN=128,
 parameter [31:0] LFO_STEP=32'd447392)(
 input wire clk,rst,enable,input wire [1:0] mode,
 input wire in_valid,input wire signed [15:0] in_sample,
 output wire in_ready,output reg out_valid,output reg signed [15:0] out_sample,
 input wire cfg_valid,input wire [8:0] cfg_echo_wet,cfg_room_wet,cfg_tremolo_depth,
 input wire [4:0] cfg_tremolo_rate_hz,output wire cfg_ready,output reg cfg_applied,
 input wire [2:0] effect_mask,input wire [14:0] cfg_echo_samples,
 input wire chorus_enabled,input wire [8:0] chorus_wet,input wire [1:0] chorus_depth,chorus_rate);
 reg [2:0] stage;
 wire chorus_ready,chorus_valid;wire signed [15:0] chorus_sample,chorus_input;
 generate if(CHORUS_ENABLE)begin: chorus_on
  audio_chorus #(.PHASE_OFFSET(CHORUS_PHASE)) chorus(.clk(clk),.rst(rst),
   .in_valid(stage==5),.in_sample(chorus_input),.enabled(chorus_enabled),
   .wet(chorus_wet),.depth(chorus_depth),.rate(chorus_rate),
   .in_ready(chorus_ready),.out_valid(chorus_valid),.out_sample(chorus_sample));
 end else begin: chorus_off
  assign chorus_ready=1;assign chorus_valid=0;assign chorus_sample=0;
 end endgenerate
 reg [8:0] echo_target,room_target,depth_target,echo_level,room_level,depth_level;
 reg [8:0] used_echo,used_room,used_tremolo_gain;
 reg [14:0] echo_samples;
 reg [31:0] lfo_phase,phase_step;
 reg signed [15:0] echo_stage,room_stage;
 reg signed [26:0] tremolo_product;
 assign chorus_input=tremolo_product>>>8;
 wire echo_ready,echo_valid,room_ready,room_valid;
 wire signed [15:0] echo_dry,echo_history,room_sample;
 assign cfg_ready=!rst;
 function automatic [8:0] clamp_amount(input [8:0] value);
  begin clamp_amount=value>256 ? 9'd256 : value;end
 endfunction
 function automatic [8:0] slew(input [8:0] current,input [8:0] target);
  begin slew=current<target?current+9'd1:current>target?current-9'd1:current;end
 endfunction
    function automatic [31:0] rate_step(input [4:0] hz);
        begin case(hz)
            0,1:rate_step=32'd89478;
            2:rate_step=32'd178957;
            3:rate_step=32'd268435;
            4:rate_step=32'd357914;
            5:rate_step=32'd447392;
            6:rate_step=32'd536871;
            7:rate_step=32'd626349;
            8:rate_step=32'd715828;
            9:rate_step=32'd805306;
            10:rate_step=32'd894785;
            11:rate_step=32'd984263;
            12:rate_step=32'd1073742;
            13:rate_step=32'd1163220;
            14:rate_step=32'd1252699;
            15:rate_step=32'd1342177;
            16:rate_step=32'd1431656;
            17:rate_step=32'd1521134;
            18:rate_step=32'd1610613;
            19:rate_step=32'd1700091;
            20:rate_step=32'd1789570;
            default:rate_step=32'd1789570;
        endcase end
    endfunction

 // Standalone old callers can omit the mask; production always supplies all
 // three enable bits. A selected legacy effect is still one independently mixed stage.
 wire [2:0] legacy_mask=(enable===1'b1) ?
  ((mode===2'd1)?3'b010:(mode===2'd2)?3'b100:3'b001) : 3'b000;
 wire [2:0] requested_mask=(^effect_mask===1'bx)?legacy_mask:effect_mask;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   echo_target<=ECHO_WET;room_target<=ROOM_WET;depth_target<=256-TREMOLO_MIN;
   phase_step<=LFO_STEP;cfg_applied<=0;echo_samples<=DELAY_SAMPLES;
  end else begin
   cfg_applied<=0;
   if(cfg_valid)begin
    echo_target<=clamp_amount(cfg_echo_wet);room_target<=clamp_amount(cfg_room_wet);
    depth_target<=clamp_amount(cfg_tremolo_depth);phase_step<=rate_step(cfg_tremolo_rate_hz);cfg_applied<=1;
    if(^cfg_echo_samples!==1'bx)
     echo_samples<=cfg_echo_samples<1 ? 15'd1 : cfg_echo_samples>MAX_DELAY_SAMPLES ? 15'(MAX_DELAY_SAMPLES) : cfg_echo_samples;
   end
  end
 end
 wire [7:0] triangle=lfo_phase[31]?~lfo_phase[30:23]:lfo_phase[30:23];
 wire [16:0] depth_product={9'd0,triangle}*{8'd0,depth_level};
 wire [8:0] tremolo_gain=(9'd256-depth_level)+depth_product[16:8];
 wire signed [17:0] echo_difference=$signed({echo_history[15],echo_history})-$signed({echo_dry[15],echo_dry});
 wire signed [17:0] room_difference=$signed({room_sample[15],room_sample})-$signed({echo_stage[15],echo_stage});
 wire signed [27:0] echo_blend=$signed(echo_dry)*28'sd256+echo_difference*$signed({1'b0,used_echo});
 wire signed [27:0] room_blend=$signed(echo_stage)*28'sd256+room_difference*$signed({1'b0,used_room});
 assign in_ready=!rst && stage==0 && echo_ready && room_ready;
 wire accept=in_valid && in_ready;
 wire room_launch=stage==2 && room_ready;
 generate if(ECHO_ENABLE)begin: echo_on
 audio_delay #(.DELAY_SAMPLES(DELAY_SAMPLES),.MAX_SAMPLES(MAX_DELAY_SAMPLES)) echo(
  .clk(clk),.rst(rst),.enable(1'b0),.in_valid(accept),.in_sample(in_sample),
  .in_ready(echo_ready),.out_valid(echo_valid),.out_sample(echo_dry),
  .out_history(echo_history),.delay_samples(echo_samples));
 end else begin: direct_attack
  reg valid;reg signed [15:0] dry;
  always @(posedge clk or posedge rst)
   if(rst)begin valid<=0;dry<=0;end
   else begin valid<=accept;if(accept)dry<=in_sample;end
  assign echo_ready=!rst;assign echo_valid=valid;assign echo_dry=dry;assign echo_history=0;
 end endgenerate
 audio_reverb #(.D0(D0),.D1(D1),.D2(D2),.D3(D3)) room(
  .clk(clk),.rst(rst),.in_valid(room_launch),.in_sample(echo_stage),
  .in_ready(room_ready),.out_valid(room_valid),.out_sample(room_sample));
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   stage<=0;out_valid<=0;out_sample<=0;echo_stage<=0;room_stage<=0;tremolo_product<=0;
   echo_level<=0;room_level<=0;depth_level<=0;used_echo<=0;used_room<=0;used_tremolo_gain<=256;lfo_phase<=0;
  end else begin
   out_valid<=0;
   if(accept)begin
    used_echo<=echo_level;used_room<=room_level;used_tremolo_gain<=tremolo_gain;
    echo_level<=slew(echo_level,(ECHO_ENABLE && requested_mask[0]) ? echo_target : 9'd0);
    room_level<=slew(room_level,requested_mask[1] ? room_target : 9'd0);
    depth_level<=slew(depth_level,requested_mask[2] ? depth_target : 9'd0);
    lfo_phase<=lfo_phase+phase_step;stage<=1;
   end else case(stage)
    1:if(echo_valid)begin echo_stage<=echo_blend>>>8;stage<=2;end
    2:if(room_ready)stage<=3;
    3:if(room_valid)begin room_stage<=room_blend>>>8;stage<=4;end
    4:begin tremolo_product<=$signed(room_stage)*$signed({1'b0,used_tremolo_gain});stage<=5;end
    5:begin
     if(CHORUS_ENABLE)begin if(chorus_ready)stage<=6;end
     else begin out_sample<=tremolo_product>>>8;out_valid<=1;stage<=0;end
    end
    6:if(chorus_valid)begin out_sample<=chorus_sample;out_valid<=1;stage<=0;end
    default:begin end
   endcase
  end
 end
 // synthesis translate_off
 initial if(ECHO_WET<0 || ECHO_WET>256 || ROOM_WET<0 || ROOM_WET>256 || TREMOLO_MIN<0 || TREMOLO_MIN>256)
  $fatal(1,"invalid effect amount");
 // synthesis translate_on
endmodule
