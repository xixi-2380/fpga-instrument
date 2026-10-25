`timescale 1ns/1ps
`include "check.svh"
// Exhaust all logical pixels of all original 16 frames in both animations.
// The immutable baseline ROM files are supplied via plusargs; no duplicate
// full-size production ROM is required in the project.
module tb_animation_storage;
 reg clk=0;always #5 clk=~clk;
 reg [1:0] theme=1;reg [3:0] frame=0;reg [10:0] x=0,y=0;
 wire [23:0] pixel;
 reg [3:0] cat_reference[0:327679],capybara_reference[0:327679];
 reg [4095:0] cat_file,capybara_file;
 reg [3:0] index;reg [23:0] expected;
 integer checks=0,address;
 ui_theme_art dut(clk,theme,frame,x,y,pixel,1'b1);
 initial begin
  if(!$value$plusargs("CAT_REFERENCE=%s",cat_file) || !$value$plusargs("CAPYBARA_REFERENCE=%s",capybara_file))
   $fatal(1,"Supply original b07c0d5 animation ROMs with CAT_REFERENCE/CAPYBARA_REFERENCE");
  $readmemh(cat_file,cat_reference);$readmemh(capybara_file,capybara_reference);
  for(integer t=1;t<=2;t=t+1)begin
   theme=t;
   for(integer f=0;f<16;f=f+1)begin
    frame=f;
    for(integer sy=0;sy<160;sy=sy+1)for(integer sx=0;sx<128;sx=sx+1)begin
     @(negedge clk);x=500+sx*2;y=96+sy*2;address=f*20480+sy*128+sx;
     index=t==1 ? cat_reference[address] : capybara_reference[address];
     expected=index==0 ? (t==1 ? 24'hf7f1e8 : 24'hfff1d9) :
      t==1 ? dut.cat_palette[index] : dut.capybara_palette[index];
     @(posedge clk);#1;
     `CHECK(pixel===expected,"lossless cropped/deduplicated storage reproduces every original frame pixel")
     `CHECK(dut.cat_addr>=0 && dut.cat_addr<dut.CAT_WORDS && dut.capybara_addr>=0 && dut.capybara_addr<dut.CAPYBARA_WORDS,"both physical ROM addresses remain bounded")
    end
   end
  end
  $display("PASS tb_animation_storage checks=%0d logical_pixels=655360",checks);$finish;
 end
endmodule
