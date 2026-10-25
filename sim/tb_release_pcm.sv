`timescale 1ns/1ps
`include "check.svh"
// Real matrix -> event handshake -> envelope/mixer/effects -> I2S.
// 1 rendering voice and HALF_CYCLES=1 accelerate long envelope releases;
// the separate board regression retains production 32 voices and I2S cadence.
module tb_release_pcm;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [15:0] pressed=0;reg [2:0] selected=0;
 wire [3:0] columns;reg [3:0] ideal;wire [3:0] rows;
 wire [15:0] keys;wire ghost,nv,no,nr,ready,kg,gate,frame_ce,bck,ws,din,underrun;
 wire [6:0] id;wire [31:0] fcw;wire [3:0] last;wire [2:0] event_timbre;
 wire [0:0] active,held;wire [16:0] level;wire pcm_valid;wire signed [15:0] pcm;
 integer checks=0,on_count=0,off_count=0,frames=0,nonzero=0,prior_on,prior_off;
 reg must_be_silent=0;
 for(genvar r=0;r<4;r=r+1)begin
  always @*ideal[r]=!((pressed[r*4+:4]&columns)!=0);
  assign #(70,0) rows[r]=ideal[r];
 end
 keyboard_core #(.SLOT_CYCLES(24),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2))
  adapter(clk,rst,ready,nr,rows,columns,keys,ghost,nv,no,id,fcw,kg,last,selected,event_timbre,1'b0);
 synth_core #(.VOICES(1),.MUTE(4),.FADE(4),.ATTACK(4),.DECAY(4),.RELEASE(16),
  .DELAY_SAMPLES(8),.ROOM_D0(3),.ROOM_D1(5),.ROOM_D2(7),.ROOM_D3(9)) dut(
  .clk(clk),.rst(rst),.note_valid(nv),.note_on(no),.note_id(id),.note_fcw(fcw),
  .note_ready(nr),.input_ready(ready),.bck(bck),.ws(ws),.din(din),.underrun(underrun),
  .frame_ce(frame_ce),.gate(gate),.voice_active(active),.voice_held(held),.envelope_level(level),
  .note_timbre(event_timbre),.effects_enable(1'b0),.effect_mode(2'd0),.effect_cfg_valid(1'b0),
  .effect_echo_wet(9'd64),.effect_room_wet(9'd64),.effect_tremolo_depth(9'd128),.effect_tremolo_rate_hz(4'd5),
  .visual_sample_valid(pcm_valid),.visual_sample(pcm),.visual_notes());
 defparam dut.timing.HALF_CYCLES=1;
 always @(posedge clk)if(!rst)begin
  `CHECK(!underrun,"release path meets accelerated frame budget")
  if(frame_ce)frames=frames+1;
  if(nv && nr)begin if(no)on_count=on_count+1;else off_count=off_count+1;end
  if(pcm_valid)begin if(pcm!=0)nonzero=nonzero+1;
   if(must_be_silent)`CHECK(pcm==0,"post-effects PCM stays exactly zero after release tail")
  end
 end
 always @(posedge bck)if(!rst && must_be_silent)`CHECK(din==0,"both serialized I2S channels remain zero after release")
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task more_frames(input integer n);integer target;begin target=frames+n;wait(frames>=target);cycles(1);end endtask
 task release_and_check;begin
  pressed=0;cycles(700);
  `CHECK(keys==0 && !kg && !gate && held==0,"physical release drains keys, event state and all held voices")
  more_frames(2100);
  `CHECK(active==0 && level==0 && dut.frame_l==0 && dut.frame_r==0,"all envelope profiles finish and both output frames become zero")
  must_be_silent=1;more_frames(20);must_be_silent=0;
  `CHECK(on_count==off_count,"every accepted matrix onset has its matching Note Off")
 end endtask
 initial begin
  #21 rst=0;wait(ready);cycles(700);
  // Every physical key, including the slow return after changing columns.
  for(integer k=0;k<16;k=k+1)begin
   prior_on=on_count;prior_off=off_count;pressed=16'b1<<k;cycles(900);
   `CHECK(keys==(16'b1<<k) && gate && !ghost,"single physical key has one exact identity")
   `CHECK(on_count==prior_on+1 && off_count==prior_off,"held key cannot create adjacent-column notes")
   pressed=0;cycles(700);more_frames(24);
   `CHECK(keys==0 && !kg && !gate && active==0 && level==0,"every sine key releases within debounce plus envelope time")
   must_be_silent=1;more_frames(8);must_be_silent=0;
  end
  for(integer t=0;t<7;t=t+1)begin
   selected=t;pressed=16'h0200;cycles(900);more_frames(t==3 ? 2300 : 128);
   `CHECK(gate && keys==16'h0200,"each timbre uses the same real physical key")
   release_and_check;
  end
  `CHECK(nonzero>100,"test exercised actual nonzero audio before silence")
  $display("PASS tb_release_pcm checks=%0d on=%0d off=%0d nonzero_frames=%0d",checks,on_count,off_count,nonzero);$finish;
 end
 initial begin #100000000;$fatal(1,"release PCM timeout");end
endmodule
