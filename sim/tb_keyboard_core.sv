`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
module tb_keyboard_core;
 reg clk=0,rst=1;always #8.138020833 clk=~clk;
 reg [15:0] pressed=0;
 wire [3:0] rows,columns,key;wire [15:0] keys;
 wire bck,ws,din,pa,u,ghost,gate;wire [16:0] level;
 integer checks=0,frames=0,bitn=0,ch=0,word=0,current_code=0,pending_code=0;
 integer addr,romcode,nonzero=0,cycles=0,last_frame_cycle=-1,f;
 string sim_out_dir;
 reg [31:0] ref_phase=0;
 reg signed [63:0] product;
 real x;
 keyboard_core #(.SLOT_CYCLES(8),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(3),
  .MUTE(4),.FADE(4),.ATTACK(8),.DECAY(8),.SUSTAIN(32768),.RELEASE(16))
  dut(clk,rst,rows,columns,bck,ws,din,pa,u,keys,ghost,gate,key,level);
 passive_matrix_model model(pressed,columns,rows);
 always @(posedge rst)begin
  frames=0;bitn=0;ch=0;word=0;current_code=0;pending_code=0;ref_phase=0;last_frame_cycle=-1;
 end
 always @(posedge clk)if(!rst)begin
  cycles=cycles+1;
  `CHECK(!u,"no underrun in keyboard-controlled audio")
  `CHECK(!dut.gain_valid || dut.ready,"gain pipeline meets frame-buffer deadline")
  if(dut.frame_ce)begin
   if(last_frame_cycle>=0)begin `CHECK(cycles-last_frame_cycle==1280,"fixed 1280-cycle frame") end
   last_frame_cycle=cycles;
   current_code=pending_code;
   // Control frequency/envelope are sampled at the documented frame
   // interface; the oscillator/ROM and serial decoder references are independent.
   addr=ref_phase[31:20];ref_phase=ref_phase+dut.fcw;
   #0.001;
   x=$sin(6.283185307179586*addr/4096.0)*32767.0;
   romcode=x>=0?$rtoi(x+0.5):$rtoi(x-0.5);
   product=level;product=product*dut.startup_level;product=product>>>16;
   product=product*romcode;pending_code=product>>>21;
  end
 end
 always @(posedge bck)if(!rst)begin
  `CHECK(ws==(ch==1),"keyboard PT8211 framing")
  word=((word<<1)|din)&65535;
  if(bitn==15)begin
   `CHECK(word==(current_code&65535),"keyboard end-to-end oscillator/gain/serial code")
   `CHECK($signed(word[15:0])>=-1024 && $signed(word[15:0])<=1023,"bounded keyboard audio")
   if(word!=0)nonzero=nonzero+1;
   if(ch==1)begin
    $fdisplay(f,"%0d,%0d,%0d,%0d,%0d,%0d",frames,keys,key,level,ghost,$signed(word[15:0]));
    frames=frames+1;
   end
   ch=1-ch;word=0;bitn=0;
  end else bitn=bitn+1;
 end
 task more_frames(input integer n);integer target;begin target=frames+n;wait(frames>=target);#2;end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",sim_out_dir))sim_out_dir="reports/sim/current";
  f=$fopen({sim_out_dir,"/D2_samples.csv"},"w");
  if(f==0)$fatal(1,"Cannot open simulation sample output");
  $fdisplay(f,"frame,keys,key,envelope,ghost,sample");
  #23 rst=0;more_frames(20);`CHECK(nonzero==0 && !gate,"idle keyboard is silent")
  for(integer k=0;k<16;k=k+1)begin
   pressed=16'h1<<k;more_frames(24);
   `CHECK(gate && key==k,"all sixteen physical key positions reach voice")
   pressed=0;more_frames(24);`CHECK(!gate && level==0,"release finishes in audio path")
  end
  `CHECK(nonzero>100,"keys produce audio")
  pressed=16'h0001;more_frames(12);pressed=16'h0201;more_frames(12);
  `CHECK(key==9 && dut.fcw==32'h0258bf26,"new A4 key overrides C4")
  pressed=16'h0001;more_frames(12);`CHECK(key==0,"held-key fallback")
  pressed=16'h0013;more_frames(24);`CHECK(ghost && !gate && level==0,"ghost releases voice")
  pressed=16'h0002;more_frames(24);`CHECK(!ghost && gate && key==1,"recover after ambiguity")
  #3 rst=1;#1;`CHECK(!pa && din==0 && columns==0,"reset while playing")
  #31 rst=0;more_frames(30);`CHECK(gate && key==1 && level!=0,"held-key and envelope resume after reset")
  $fclose(f);$display("PASS tb_keyboard_core checks=%0d",checks);$finish;
 end
 initial begin #30000000;$fatal(1,"keyboard core timeout");end
endmodule
