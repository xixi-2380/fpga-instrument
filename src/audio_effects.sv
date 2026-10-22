`timescale 1ns/1ps
// One selectable effect after the shared mixer. Every engine advances once
// per accepted sample, including bypass. No internal derived clocks.
module audio_effects #(
    parameter integer DELAY_SAMPLES=7200,D0=1499,D1=1601,D2=1867,D3=2053,
    ECHO_WET=64,ROOM_WET=64,TREMOLO_MIN=128,
    parameter [31:0] LFO_STEP=32'd447392)(
    input wire clk,rst,enable,input wire [1:0] mode,
    input wire in_valid,input wire signed [15:0] in_sample,
    output wire in_ready,output reg out_valid,output reg signed [15:0] out_sample,
    // Atomic parameter snapshot, all in clk domain. Pulse valid only with
    // defined fields; disconnected legacy valid is ignored in simulation.
    input wire cfg_valid,input wire [8:0] cfg_echo_wet,cfg_room_wet,cfg_tremolo_depth,
    input wire [3:0] cfg_tremolo_rate_hz,output wire cfg_ready,output reg cfg_applied);
    wire echo_ready,echo_valid,room_ready,room_valid;
    wire signed [15:0] echo_dry,echo_history,room_sample;
    reg [2:0] stage;
    reg [1:0] active_mode,used_mode,requested_mode;
    reg [8:0] fade_level,used_fade;
    reg signed [15:0] dry,tremolo_sample;
    reg signed [31:0] candidate;
    reg [31:0] lfo_phase,phase_step;
    reg [8:0] echo_target,room_target,depth_target;
    reg [8:0] echo_level,room_level,depth_level,used_echo,used_room;
    assign cfg_ready=!rst;
    function automatic [8:0] clamp_amount(input [8:0] value);
        begin clamp_amount=value>9'd256?9'd256:value;end
    endfunction
    // round(hz * 2^32 / 48000); no division or variable frequency clock.
    function automatic [31:0] rate_step(input [3:0] hz);
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
            default:rate_step=32'd894785;
        endcase end
    endfunction
    function automatic [8:0] slew(input [8:0] current,input [8:0] target);
        begin slew=current<target?current+9'd1:current>target?current-9'd1:current;end
    endfunction
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            echo_target<=ECHO_WET;room_target<=ROOM_WET;
            depth_target<=256-TREMOLO_MIN;phase_step<=LFO_STEP;cfg_applied<=0;
        end else begin
            cfg_applied<=0;
            if(cfg_valid)begin
                echo_target<=clamp_amount(cfg_echo_wet);
                room_target<=clamp_amount(cfg_room_wet);
                depth_target<=clamp_amount(cfg_tremolo_depth);
                phase_step<=rate_step(cfg_tremolo_rate_hz);cfg_applied<=1;
            end
        end
    end
    wire [7:0] triangle=lfo_phase[31]?~lfo_phase[30:23]:lfo_phase[30:23];
    wire [16:0] depth_product={9'd0,triangle}*{8'd0,depth_level};
    wire [8:0] tremolo_gain=(9'd256-depth_level)+depth_product[16:8];
    wire signed [31:0] input_ext={{16{in_sample[15]}},in_sample};
    wire signed [31:0] gain_ext=$signed({23'd0,tremolo_gain});
    wire signed [31:0] tremolo_product=input_ext*gain_ext;
    wire signed [31:0] dry_ext={{16{dry[15]}},dry};
    wire signed [31:0] echo_ext={{16{echo_history[15]}},echo_history};
    wire signed [31:0] room_ext={{16{room_sample[15]}},room_sample};
    wire signed [31:0] echo_weight=$signed({23'd0,used_echo});
    wire signed [31:0] room_weight=$signed({23'd0,used_room});
    wire signed [31:0] fade_ext=$signed({23'd0,used_fade});
    wire signed [31:0] blend=(dry_ext<<<8)+(candidate-dry_ext)*fade_ext;
    wire signed [31:0] result=blend>>>8;
    assign in_ready=!rst && stage==0 && echo_ready && room_ready;
    wire accept=in_valid && in_ready;
    // Unconnected legacy mode inputs retain the original echo selection.
    always @* case(mode)
        2'd1:requested_mode=1;
        2'd2:requested_mode=2;
        default:requested_mode=0;
    endcase
    audio_delay #(.DELAY_SAMPLES(DELAY_SAMPLES)) echo(
        .clk(clk),.rst(rst),.enable(1'b0),.in_valid(accept),.in_sample(in_sample),
        .in_ready(echo_ready),.out_valid(echo_valid),.out_sample(echo_dry),
        .out_history(echo_history));
    audio_reverb #(.D0(D0),.D1(D1),.D2(D2),.D3(D3)) room(
        .clk(clk),.rst(rst),.in_valid(accept),.in_sample(in_sample),
        .in_ready(room_ready),.out_valid(room_valid),.out_sample(room_sample));
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            stage<=0;active_mode<=0;used_mode<=0;fade_level<=0;used_fade<=0;
            dry<=0;candidate<=0;tremolo_sample<=0;lfo_phase<=0;out_valid<=0;out_sample<=0;
            echo_level<=ECHO_WET;room_level<=ROOM_WET;depth_level<=256-TREMOLO_MIN;
            used_echo<=ECHO_WET;used_room<=ROOM_WET;
        end else begin
            out_valid<=0;
            if(accept)begin
                stage<=1;dry<=in_sample;used_mode<=active_mode;used_fade<=fade_level;
                tremolo_sample<=tremolo_product>>>8;lfo_phase<=lfo_phase+phase_step;
                used_echo<=echo_level;used_room<=room_level;
                echo_level<=slew(echo_level,echo_target);
                room_level<=slew(room_level,room_target);
                depth_level<=slew(depth_level,depth_target);
                // Reach exact dry before changing algorithms, then fade in.
                if(requested_mode!=active_mode)begin
                    if(fade_level!=0)fade_level<=fade_level-1'b1;
                    else active_mode<=requested_mode;
                end else if(enable)begin
                    if(fade_level<256)fade_level<=fade_level+1'b1;
                end else if(fade_level!=0)fade_level<=fade_level-1'b1;
            end else if(stage==1)stage<=2;
            else if(stage==2)begin
                case(used_mode)
                    1:candidate<=((dry_ext*(32'sd256-room_weight))+room_ext*room_weight)>>>8;
                    2:candidate<=tremolo_sample;
                    default:candidate<=((dry_ext*(32'sd256-echo_weight))+echo_ext*echo_weight)>>>8;
                endcase
                stage<=3;
            end else if(stage==3)begin
                if(result>32767)out_sample<=16'sh7fff;
                else if(result < -32768)out_sample<=16'sh8000;
                else out_sample<=result[15:0];
                out_valid<=1;stage<=0;
            end
        end
    end
    // synthesis translate_off
    initial if(ECHO_WET<0 || ECHO_WET>256 || ROOM_WET<0 || ROOM_WET>256 ||
        TREMOLO_MIN<0 || TREMOLO_MIN>256)$fatal(1,"Invalid effect amount");
    always @(posedge clk)if(!rst && stage==2 && (!echo_valid || !room_valid))
        $fatal(1,"Effect engine latency mismatch");
    // synthesis translate_on
endmodule
