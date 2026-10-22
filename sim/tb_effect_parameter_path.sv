`timescale 1ns/1ps
`include "check.svh"
module tb_effect_parameter_path;
 reg clk=0,rst=1,note_valid=0,note_on=0,en=1,cfg_valid=0;
 reg [6:0] note_id=60;reg [31:0] fcw=32'h0258bf26;
 reg [1:0] mode=0;
 reg [8:0] echo_wet=64,room_wet=64,depth=128;
 reg [3:0] rate_hz=5;
 wire nr,ir,bck,ws,din,pa,u,frame_ce,gate,cfg_ready,cfg_applied;
 wire [31:0] active,held;wire [16:0] level;
 integer checks=0,frames=0,cycles=0,frame_cycle=0,deliveries=0,max_delivery=0;
 integer trace,bitn=0,ch=0,word=0,current_code=0,pending_code=0;
 reg [4095:0] tracefile;
 always #5 clk=~clk;
 synth_core #(.MUTE(4),.FADE(4),.ATTACK(8),.DECAY(8),.SUSTAIN(32768),.RELEASE(16),
  .DELAY_SAMPLES(8),.ROOM_D0(3),.ROOM_D1(5),.ROOM_D2(7),.ROOM_D3(11)) sound(
  .clk(clk),.rst(rst),.note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(fcw),
  .note_timbre(2'd1),.effects_enable(en),.effect_mode(mode),.note_ready(nr),.input_ready(ir),
  .bck(bck),.ws(ws),.din(din),.pa_enable(pa),.underrun(u),.frame_ce(frame_ce),.gate(gate),
  .voice_active(active),.voice_held(held),.envelope_level(level),.effect_cfg_valid(cfg_valid),
  .effect_echo_wet(echo_wet),.effect_room_wet(room_wet),.effect_tremolo_depth(depth),
  .effect_tremolo_rate_hz(rate_hz),.effect_cfg_ready(cfg_ready),.effect_cfg_applied(cfg_applied));
 always @(posedge clk)if(!rst)begin
  cycles=cycles+1;`CHECK(!u,"runtime updates never underrun")
  // Same-edge sample uses old parameter registers, then a config commits.
  if(sound.mix_valid)$fdisplay(trace,"S %0d %0d %0d",$signed(sound.mix_sample),en,mode);
  if(cfg_valid && cfg_ready)$fdisplay(trace,"C %0d %0d %0d %0d",echo_wet,room_wet,depth,rate_hz);
  if(sound.effect_valid)begin
   $fdisplay(trace,"O %0d",$signed(sound.effect_sample));
   `CHECK(cycles-frame_cycle<=544,"updated effect reaches buffer in 32-voice budget")
   if(cycles-frame_cycle>max_delivery)max_delivery=cycles-frame_cycle;
   pending_code=$signed(sound.effect_sample);deliveries=deliveries+1;
  end
  if(frame_ce)begin
   if(frames>0)`CHECK(deliveries==1,"one output per audio frame")
   deliveries=0;frame_cycle=cycles;current_code=pending_code;frames=frames+1;
  end
 end
 always @(posedge bck)if(!rst)begin
  `CHECK(ws==(ch==1),"serial stereo framing")
  word=((word<<1)|din)&65535;
  if(bitn==15)begin
   `CHECK(word==(current_code&65535),"runtime result reaches both actual DAC serial channels")
   ch=1-ch;bitn=0;word=0;
  end else bitn=bitn+1;
 end
 task more_frames(input integer n);integer target;begin target=frames+n;wait(frames>=target);#1;end endtask
 task command(input integer e,input integer r,input integer d,input integer hz);begin
  @(negedge clk);cfg_valid=1;echo_wet=e;room_wet=r;depth=d;rate_hz=hz;
  `CHECK(cfg_ready,"synth exposes config readiness")
  @(posedge clk);#1;`CHECK(cfg_applied,"synth forwards config acknowledgement")
  @(negedge clk);cfg_valid=0;
 end endtask
 initial begin
  if(!$value$plusargs("PARAM_TRACE=%s",tracefile))$fatal(1,"Provide PARAM_TRACE output path");
  trace=$fopen(tracefile,"w");if(!trace)$fatal(1,"Cannot open trace");
  #13 rst=0;wait(ir);more_frames(4);
  @(negedge clk);note_valid=1;note_on=1;
  wait(nr);@(posedge clk);@(negedge clk);note_valid=0;
  more_frames(300);
  for(integer m=0;m<3;m=m+1)begin
   @(negedge clk);mode=m;
   for(integer n=0;n<6;n=n+1)begin
    // Exercise parameter write at the same sample acceptance edge, then
    // another write while the effect pipeline owns that sample.
    wait(sound.mix_valid);command(n*51,256-n*43,n*51,1+n);
    command(256-n*43,n*51,256-n*43,10-n);
    more_frames(90);
   end
  end
  `CHECK(gate && $countones(held)==1,"parameter updates preserve held note and voice ownership")
  en=0;command(511,511,511,15);more_frames(300);
  @(negedge clk);note_valid=1;note_on=0;
  wait(nr);@(posedge clk);@(negedge clk);note_valid=0;
  more_frames(24);`CHECK(!gate && active==0,"independent note release survives parameter writes")
  $fclose(trace);$display("PASS tb_effect_parameter_path checks=%0d frames=%0d max_delivery=%0d",checks,frames,max_delivery);$finish;
 end
 initial begin #60000000;$fatal(1,"runtime path timeout");end
endmodule
