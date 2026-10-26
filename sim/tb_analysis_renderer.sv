`timescale 1ns/1ps
`include "check.svh"
module tb_analysis_renderer;
 parameter integer FIRST_SCENE=0,LAST_SCENE=5;
 reg clk=0,rst=1,frame=0,de=0,valid=1;always #5 clk=~clk;
 reg [1111:0] status=0;reg [512:0] analysis=0;reg [10:0] x=0,y=0;
 wire [23:0] rgb;wire dout,hs,vs;reg [23:0] pixels[0:383999];
 reg [7:0] bands[0:63],wave[0:127];reg [4095:0] outdir,path;
 reg record=0;integer count=0,checks=0,scene,fd,left,bottom,step,level,tx,ty;reg [23:0] gold;
 reg [1111:0] frozen;reg [511:0] frozen_spectrum;
 rgb_ui_renderer dut(clk,rst,frame,valid,status,x,y,de,1'b1,1'b1,rgb,dout,hs,vs,analysis,1'b1);
 always @(posedge clk)begin #1;if(record&&dout)begin
 `CHECK(count<384000&&(^rgb)!==1'bx,"defined analysis pixels") pixels[count]=rgb;count=count+1;
 end end
 task tick;begin @(negedge clk);frame=1;@(negedge clk);frame=0;repeat(12)@(negedge clk);end endtask
 initial begin
 if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
 $sformat(path,"%0s/display_spectrum.hex",outdir);$readmemh(path,bands);
 $sformat(path,"%0s/display_wave.hex",outdir);$readmemh(path,wave);
 #12 rst=0;
 for(scene=FIRST_SCENE;scene<=LAST_SCENE;scene=scene+1)begin
 status=0;analysis=0;status[15]=1;status[5:0]=2;status[13:12]=3;status[79:64]=16'h0091;status[87:80]=32;
 status[30:24]=25;status[37:31]=25;status[44:38]=50;status[48:45]=5;status[49]=1;status[50]=1;status[51]=1;
 status[58:57]=scene%2==0?1:2;status[55:54]=scene<2?0:scene==2?1:scene==3?2:3;status[56]=scene!=0&&scene!=4;
 for(integer k=0;k<128;k=k+1)status[88+k*8+:8]=wave[k];
 for(integer k=0;k<64;k=k+1)analysis[k*8+:8]=bands[k];analysis[512]=1;
 tick;if(scene%2)begin wait(dut.phase_plot.state==5);tick;`CHECK(dut.xy_ready,"complete XY ready") end
 count=0;record=1;frozen=dut.state;frozen_spectrum=dut.spectrum_state;
 for(integer yy=0;yy<480;yy=yy+1)for(integer xx=0;xx<800;xx=xx+1)begin
 @(negedge clk);x=xx;y=yy;de=1;if(xx==400&&yy==200)begin analysis=0;status=~status;end
 `CHECK(dut.state==frozen&&dut.spectrum_state==frozen_spectrum,"frame frozen UI and spectrum")
 end
 @(negedge clk);de=0;repeat(12)@(negedge clk);record=0;
 `CHECK(count==384000,"full800x480 pipeline preserved")
 `CHECK(dut.ui_hit(264,420,0,0)==21&&dut.ui_hit(383,463,0,0)==21,"full view touch target")
 gold=scene<2?24'hd6b979:scene==2?24'h856b57:scene==3?24'ha3652c:24'h884652;
 if(scene%2==0)begin
 left=scene<4?32:488;step=scene<4?8:4;bottom=scene<4?300:244;level=scene<4?bands[16]:bands[16]>>1;
 `CHECK(level>0&&pixels[(bottom-1)*800+left+16*step+1]==gold,"measured375Hz band visible")
 `CHECK(pixels[(bottom-level)*800+left+16*step+1]==gold,"FFT controls bar height")
 `CHECK(pixels[(bottom-1)*800+left+16*step+step-1]!=gold,"bar gaps visible")
 end else begin
 left=scene<4?376:680;ty=scene<4?170:172;step=scene<4?2:1;
 for(integer k=4;k<128;k=k+1)begin
 tx=32+($signed(wave[k])>>>2);bottom=31-($signed(wave[k-4])>>>2);
 `CHECK(pixels[(ty+bottom*step)*800+left+tx*step]==gold,"real XY point reaches viewport")
 end
 `CHECK(pixels[ty*800+left]!=gold,"XY corner empty")
 end
 $sformat(path,"%0s/analysis_%0d.ppm",outdir,scene);fd=$fopen(path,"wb");$fwrite(fd,"P6\n800 480\n255\n");
 for(integer k=0;k<384000;k=k+1)$fwrite(fd,"%c%c%c",pixels[k][23:16],pixels[k][15:8],pixels[k][7:0]);$fclose(fd);
 end
 $display("PASS tb_analysis_renderer checks=%0d frames=%0d",checks,LAST_SCENE-FIRST_SCENE+1);$finish;
 end
 initial begin #50000000;$fatal(1,"analysis renderer timeout");end
endmodule
