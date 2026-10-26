`timescale 1ns/1ps
`include "check.svh"
module tb_lissajous_plot;
 reg clk=0,rst=1,tick=0,start=0,ren=0;always #5 clk=~clk;
 reg [1023:0] wave=0;reg [5:0] x=0,y=0;wire pixel,ready;
 reg [7:0] inputs[0:383];reg reference[0:12287];reg [4095:0] outdir,path;integer checks=0,elapsed;
 lissajous_plot dut(clk,rst,tick,start,wave,ren,x,y,pixel,ready);
 task scan(input integer expected);begin
 ren=1;
 for(integer k=0;k<4096;k=k+1)begin @(negedge clk);x=k%64;y=k/64;@(posedge clk);#1;
 `CHECK(pixel==reference[expected*4096+k],"full bitmap agrees with independent Pillow raster") end
 @(negedge clk);ren=0;
 end endtask
 initial begin
 if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
 $sformat(path,"%0s/xy_input.hex",outdir);$readmemh(path,inputs);
 $sformat(path,"%0s/xy_reference.hex",outdir);$readmemh(path,reference);
 #12 rst=0;
 for(integer f=0;f<3;f=f+1)begin
 for(integer k=0;k<128;k=k+1)wave[k*8+:8]=inputs[f*128+k];
 @(negedge clk);start=1;@(negedge clk);start=0;
 if(f>0)scan(f-1);
 elapsed=0;while(dut.state!=5&&elapsed<13000)begin @(negedge clk);elapsed=elapsed+1;end
 `CHECK(dut.state==5,"bounded inactive-bank build")
 if(f==0)`CHECK(!ready,"uninitialized bitmap never published") else scan(f-1);
 @(negedge clk);tick=1;@(negedge clk);tick=0;`CHECK(ready,"publish only at frame boundary") scan(f);
 end
 @(negedge clk);start=1;@(negedge clk);start=0;repeat(20)@(negedge clk);rst=1;#1;
 `CHECK(!ready,"reset invalidates partial bitmap")
 @(negedge clk);rst=0;wave=0;start=1;@(negedge clk);start=0;
 wait(dut.state==5);@(negedge clk);tick=1;@(negedge clk);tick=0;scan(0);
 $display("PASS tb_lissajous_plot checks=%0d",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"XY timeout");end
endmodule
