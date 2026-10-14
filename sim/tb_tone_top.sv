`timescale 1ns/1ps
`include "check.svh"
module tb_tone_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 wire bck,ws,din,pa;integer checks=0,bits=0,words=0,n=0,ch=0,word=0,right_word=0,nonzero=0;
 // Short startup counts accelerate board-level vendor-model integration.
 // The production 480/240 frame policy is independently checked in its own TB.
 tone_top #(.LOCK_N(32),.MUTE(4),.FADE(4)) dut(clk,rst,bck,ws,din,pa);
 always @(posedge bck) if(!dut.audio_reset)begin
  `CHECK(ws==(ch==1),"board top channel framing")
  word=((word<<1)|din)&65535;
  if(bits==15)begin
   if(ch==0)right_word=word;
   else begin `CHECK(word==right_word,"board top stereo atomics") if(word!=0)nonzero=nonzero+1;end
   bits=0;word=0;ch=1-ch;words=words+1;
  end else bits=bits+1;
 end
 initial begin
  #100 rst=0;wait(pa);wait(words>=200);
  `CHECK(nonzero>50,"board top produces sine")
  #3 rst=1;#1;`CHECK(!pa && din==0,"external reset mutes top")
  bits=0;words=0;word=0;ch=0;nonzero=0;
  #100 rst=0;wait(pa);wait(words>=40);
  `CHECK(nonzero>0,"board top resumes sine")
  $display("PASS tb_tone_top checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"top timeout");end
endmodule
