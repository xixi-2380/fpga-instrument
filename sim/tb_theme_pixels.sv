`timescale 1ns/1ps
`include "check.svh"
module tb_theme_pixels;
 parameter integer FIRST_SCENE=0,LAST_SCENE=7;
 reg clk=0,rst=1,frame_start=0,valid=1,de=0;always #5 clk=~clk;
 reg [1111:0] status=0;reg [10:0] x=0,y=0;
 wire [23:0] rgb;wire dout,hout,vout;
 reg record=0;reg [23:0] pixels[0:383999];
 integer checks=0,n=0,fd,scene,k;reg [4095:0] outdir,filename;
 reg [1111:0] frozen;reg [3:0] frozen_animation;reg [6:0] frozen_foot;
 reg [23:0] first_cat;reg [25:0] old_phase;
 rgb_ui_renderer dut(clk,rst,frame_start,valid,status,x,y,de,1'b1,1'b1,rgb,dout,hout,vout);
 always @(posedge clk)begin #1;
  if(record && dout)begin
   `CHECK(n<384000 && (^rgb)!==1'bx,"defined theme pixel within full raster")
   pixels[n]=rgb;n=n+1;
  end
 end
 task snapshot;begin
  @(negedge clk);frame_start=1;de=0;@(negedge clk);frame_start=0;repeat(3)@(negedge clk);
 end endtask
 task render(input integer which);begin
  n=0;record=1;frozen=dut.state;frozen_animation=dut.animation_frame;frozen_foot=dut.foot_phase;
  for(integer yy=0;yy<480;yy=yy+1)for(integer xx=0;xx<800;xx=xx+1)begin
   @(negedge clk);x=xx;y=yy;de=1;
   if(yy==240 && xx==100)status=~status;
   `CHECK(dut.state==frozen && dut.animation_frame==frozen_animation && dut.foot_phase==frozen_foot,"UI and animation never change mid-frame")
  end
  @(negedge clk);de=0;repeat(3)@(negedge clk);record=0;
  `CHECK(n==384000,"theme changes preserve complete 800x480 pipeline")
  // A theme switch button must be visibly rendered and have the shared hitbox.
  `CHECK(dut.ui_hit(536,420,0,frozen[20])==19,"theme control exists on both pages")
  `CHECK(pixels[420*800+536]!=pixels[419*800+536],"theme button border is visible")
  $sformat(filename,"%0s/theme_%0d.ppm",outdir,which);fd=$fopen(filename,"wb");
  $fwrite(fd,"P6\n800 480\n255\n");
  for(integer i=0;i<384000;i=i+1)$fwrite(fd,"%c%c%c",pixels[i][23:16],pixels[i][15:8],pixels[i][7:0]);
  $fclose(fd);
 end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
  #12 rst=0;
  status[15]=1;status[5:0]=3;status[64+:16]=16'h0091;status[87:80]=40;
  for(integer j=0;j<128;j=j+1)status[88+j*8+:8]=$rtoi(60*$sin(6.28318530718*j/32));status[11:6]=1;
  status[30:24]=25;status[37:31]=70;status[44:38]=50;status[48:45]=5;
  status[22:21]=1;status[23]=1;status[53]=0;status[13:12]=1;
  status[49]=1;status[50]=1;status[51]=1;
  for(scene=FIRST_SCENE;scene<=LAST_SCENE;scene=scene+1)begin
   status[55:54]=scene/2;status[20]=scene%2;snapshot;
   `CHECK(dut.state[55:54]==scene/2,"all four theme IDs reach renderer")
   render(scene);status=frozen;
  end
  // Animation counter runs from LCD frame ticks only and loops all 16 frames.
  status[55:54]=1;snapshot;
  `CHECK(dut.animation_frame==0 && dut.foot_phase==0,"theme entry restarts visual animation only")
  for(k=0;k<89;k=k+1)snapshot;
  `CHECK(dut.animation_frame==0,"16 animation frames loop after 1.6 seconds")
  valid=0;status=0;snapshot;`CHECK(dut.state[55:54]==1,"invalid CDC snapshot cannot change theme")
  rst=1;repeat(3)@(negedge clk);`CHECK(!dout && rgb==0,"reset blanks both stages")
  $display("PASS tb_theme_pixels checks=%0d frames=%0d",checks,LAST_SCENE-FIRST_SCENE+1);$finish;
 end
 initial begin #60000000;$fatal(1,"theme raster timeout");end
endmodule
