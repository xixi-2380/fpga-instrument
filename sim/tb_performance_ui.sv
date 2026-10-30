`timescale 1ns/1ps
module tb_performance_ui;
 reg clk=0,rst=1,fs=0,de=0;reg [1207:0] state=0;reg [63:0] perf=0;reg [10:0] x=0,y=0;
 wire [23:0] rgb;wire den,hs,vs;integer checks=0,n=0,f;reg recording=0;
 reg [23:0] pixels[0:383999];string outdir;
 always #5 clk=~clk;
 rgb_ui_renderer dut(clk,rst,fs,1'b1,state,x,y,de,1'b1,1'b1,rgb,den,hs,vs,146'd0,2592'd0,,perf);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 always @(posedge clk)begin #1;if(recording&&den)begin check(n<384000&&(^rgb)!==1'bx,"defined raster pixel");pixels[n]=rgb;n++;end end
 task render(input integer scene);begin
  @(negedge clk);fs=1;@(negedge clk);fs=0;repeat(5)@(negedge clk);n=0;recording=1;
  for(integer yy=0;yy<480;yy++)for(integer xx=0;xx<800;xx++)begin
   @(negedge clk);x=xx;y=yy;de=1;
   if(yy==240&&xx==100)perf=~perf;
  end
  @(negedge clk);de=0;repeat(5)@(negedge clk);recording=0;check(n==384000,"full800x480 frame");
  if(scene==1)begin
   check(pixels[270*800+112]==24'hc8b88b,"first string present");
   check(pixels[270*800+640]==24'hc8b88b,"last string present");
   check(pixels[345*800+80]==24'hbc985b,"wood frame");
  end
  f=$fopen($sformatf("%s/performance_%0d.ppm",outdir,scene),"wb");$fwrite(f,"P6\n800 480\n255\n");
  for(integer k=0;k<384000;k++)$fwrite(f,"%c%c%c",pixels[k][23:16],pixels[k][15:8],pixels[k][7:0]);$fclose(f);
 end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
  repeat(3)@(negedge clk);rst=0;state[15]=1;state[51:49]=7;
  render(0);perf=0;perf[0]=1;perf[31]=1;perf[30:21]=256;perf[4:2]=3;perf[6:5]=1;perf[8:7]=1;
  render(1);perf=dut.performance_state;perf[1]=1;perf[20:9]=12'h249;perf[30:21]=512;render(2);
  check(dut.performance_state[1]&&dut.performance_state[30:21]==512,"frame atomic expression controls");
  $display("PASS tb_performance_ui checks=%0d frames=3",checks);$finish;
 end
 initial begin #30000000;$fatal(1,"UI timeout");end
endmodule
