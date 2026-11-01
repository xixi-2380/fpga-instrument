`timescale 1ns/1ps
`include "config/synth_config.svh"
// One selected context and one registered sample per original renderer slot.
module dds_sine #(parameter integer VOICES=1,INDEX_W=VOICES>1?$clog2(VOICES):1,PREPARE_CONTEXT=0)(
 input wire clk,rst,sample_ce,input wire [31:0] fcw,
 output wire signed [15:0] sample,output reg valid,output wire [VOICES*32-1:0] phase,
 input wire restart,input wire [INDEX_W-1:0] voice_index,input wire [4:0] timbre);
 reg [31:0] phases[0:VOICES-1],noise[0:VOICES-1];reg [16:0] age[0:VOICES-1];
 reg signed [15:0] waves[0:65535],high_waves[0:16383];
 // In the renderer the voice index is ready two clocks before sample_ce.
 // Pre-read its immutable context during the idle clock, leaving the sample
 // edge for step calculation/addition. Public phase/sample timing is unchanged.
 reg [31:0] prepared_phase,prepared_noise;reg [16:0] prepared_age;
 reg [INDEX_W-1:0] prepared_index;reg prepared_valid;
 generate if(PREPARE_CONTEXT!=0)begin: context_preparation
  always @(posedge clk or posedge rst)begin
   if(rst)begin prepared_phase<=0;prepared_noise<=0;prepared_age<=0;prepared_index<=0;prepared_valid<=0;end
   else if(!sample_ce)begin
    prepared_phase<=phases[voice_index];prepared_noise<=noise[voice_index];
    prepared_age<=age[voice_index];prepared_index<=voice_index;prepared_valid<=1;
   end else prepared_valid<=0;
  end
 end endgenerate
 wire [31:0] selected_phase=PREPARE_CONTEXT!=0?prepared_phase:phases[voice_index];
 wire [31:0] selected_noise=PREPARE_CONTEXT!=0?prepared_noise:noise[voice_index];
 wire [16:0] selected_age=PREPARE_CONTEXT!=0?prepared_age:age[voice_index];
 wire [31:0] sample_phase=restart?32'd0:selected_phase;
 wire [4:0] tone=(^timbre===1'bx)?5'd0:((timbre<=25)?timbre:5'd0);
 wire [16:0] elapsed=restart?17'd0:selected_age;
 wire [31:0] random_bits=restart?(32'h6d2b79f5^{27'd0,voice_index}):selected_noise;
 reg signed [15:0] wave_q,random_sample;reg [4:0] sampled_tone;reg [16:0] sampled_age;
 wire signed [15:0] sine_sample=wave_q;
 wire high_register=fcw>32'd210213429 && tone!=0 && tone<16;
 reg [31:0] step;reg signed [16:0] percussion;
 always @*begin
  step=fcw;
  case(tone)
   16:step=elapsed<4800 ? 32'd4473924-(elapsed*32'd559) : 32'd1789569;
   17,23:step=32'd16106127;
   21:step=32'd7158279;22:step=32'd10737418;25:step=32'd536870912;
   default:;
  endcase
  percussion=0;
  case(sampled_tone)
   16,21,22,23:percussion=sine_sample;
   17:percussion=(sine_sample>>>2)+(random_sample>>>1);
   18:percussion=(sampled_age<1800 && sampled_age[8:7]==0)?random_sample:random_sample>>>2;
   19,20:percussion=random_sample>>>1;
   24:percussion=(random_sample>>>1)+(sine_sample>>>3);
   25:percussion=(random_sample>>>2)+(sine_sample>>>1);
   default:;
  endcase
 end
 assign sample=sampled_tone>=16?percussion[15:0]:wave_q;
 initial begin
  $readmemh("src/rom/sine4096.hex",waves,0,4095);
  $readmemh("src/rom/sine_high1024.hex",high_waves,0,1023);
  $readmemh("src/rom/flute4096.hex",waves,4096,8191);
  $readmemh("src/rom/flute_high1024.hex",high_waves,1024,2047);
  $readmemh("src/rom/reed4096.hex",waves,8192,12287);
  $readmemh("src/rom/reed_high1024.hex",high_waves,2048,3071);
  $readmemh("src/rom/cello4096.hex",waves,12288,16383);
  $readmemh("src/rom/cello_high1024.hex",high_waves,3072,4095);
  $readmemh("src/rom/piano4096.hex",waves,16384,20479);
  $readmemh("src/rom/piano_high1024.hex",high_waves,4096,5119);
  $readmemh("src/rom/guitar4096.hex",waves,20480,24575);
  $readmemh("src/rom/guitar_high1024.hex",high_waves,5120,6143);
  $readmemh("src/rom/vibraphone4096.hex",waves,24576,28671);
  $readmemh("src/rom/vibraphone_high1024.hex",high_waves,6144,7167);
  $readmemh("src/rom/organ4096.hex",waves,28672,32767);
  $readmemh("src/rom/organ_high1024.hex",high_waves,7168,8191);
  $readmemh("src/rom/bass4096.hex",waves,32768,36863);
  $readmemh("src/rom/bass_high1024.hex",high_waves,8192,9215);
  $readmemh("src/rom/violin4096.hex",waves,36864,40959);
  $readmemh("src/rom/violin_high1024.hex",high_waves,9216,10239);
  $readmemh("src/rom/strings4096.hex",waves,40960,45055);
  $readmemh("src/rom/strings_high1024.hex",high_waves,10240,11263);
  $readmemh("src/rom/trumpet4096.hex",waves,45056,49151);
  $readmemh("src/rom/trumpet_high1024.hex",high_waves,11264,12287);
  $readmemh("src/rom/sax4096.hex",waves,49152,53247);
  $readmemh("src/rom/sax_high1024.hex",high_waves,12288,13311);
  $readmemh("src/rom/lead4096.hex",waves,53248,57343);
  $readmemh("src/rom/lead_high1024.hex",high_waves,13312,14335);
  $readmemh("src/rom/pad4096.hex",waves,57344,61439);
  $readmemh("src/rom/pad_high1024.hex",high_waves,14336,15359);
  $readmemh("src/rom/accordion4096.hex",waves,61440,65535);
  $readmemh("src/rom/accordion_high1024.hex",high_waves,15360,16383);
 end
 for(genvar v=0;v<VOICES;v=v+1)assign phase[v*32+:32]=phases[v];
 always @(posedge clk or posedge rst)begin
  if(rst)begin valid<=0;wave_q<=0;sampled_tone<=0;random_sample<=0;sampled_age<=0;for(integer v=0;v<VOICES;v=v+1)begin phases[v]<=0;noise[v]<=32'h6d2b79f5^v;age[v]<=0;end end
  else begin valid<=sample_ce;
   if(sample_ce)begin
    phases[voice_index]<=sample_phase+step;
    noise[voice_index]<={random_bits[30:0],random_bits[31]^random_bits[21]^random_bits[1]^random_bits[0]};
    if(elapsed<17'd96000)age[voice_index]<=elapsed+1'b1;
    sampled_tone<=tone;random_sample<=random_bits[31:16];sampled_age<=elapsed;
    if(high_register)wave_q<=high_waves[{tone[3:0],sample_phase[31:22]}];
    else wave_q<=waves[{tone>=16?4'd0:tone[3:0],sample_phase[31:20]}];
   end
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(!rst && PREPARE_CONTEXT!=0 && sample_ce)begin
  if(!prepared_valid || prepared_index!==voice_index ||
     {prepared_phase,prepared_noise,prepared_age}!=={phases[voice_index],noise[voice_index],age[voice_index]})
   $fatal(1,"DDS context was not stable during the preceding idle clock");
 end
 // synthesis translate_on
endmodule
