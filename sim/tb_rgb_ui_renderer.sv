`timescale 1ns/1ps
`include "check.svh"
module tb_rgb_ui_renderer;
 reg clk=0,rst=1,frame_start=0,valid=1,de=0;always #5 clk=~clk;
 reg [1111:0] status=0;reg [10:0] x=0,y=0;
 wire [23:0] rgb;wire de_out,hs_out,vs_out;
 reg record=0;reg [23:0] pixels[0:383999];
 integer checks=0,n=0,fd,scene;reg [4095:0] outdir;reg [4095:0] filename;
 reg [1111:0] frozen;
 rgb_ui_renderer dut(clk,rst,frame_start,valid,status,x,y,de,1'b1,1'b1,rgb,de_out,hs_out,vs_out);
 always @(posedge clk)begin #1;
  if(record && de_out)begin
   `CHECK(n<384000 && (^rgb)!==1'bx,"defined pixel within full frame")
   pixels[n]=rgb;n=n+1;
  end
 end
 task snapshot;begin
  @(negedge clk);frame_start=1;de=0;@(negedge clk);frame_start=0;repeat(3)@(negedge clk);
 end endtask
 task render(input integer which);begin
  n=0;record=1;frozen=dut.state;
  for(integer yy=0;yy<480;yy=yy+1)for(integer xx=0;xx<800;xx=xx+1)begin
   @(negedge clk);x=xx;y=yy;de=1;
   if(yy==240 && xx==100)status=~status;
   `CHECK(dut.state==frozen,"UI state remains atomic for entire raster")
  end
  @(negedge clk);de=0;repeat(3)@(negedge clk);record=0;
  `CHECK(n==384000,"exactly 800x480 rendered pixels after pipeline flush")
  `CHECK(pixels[0]==dut.artwork.british_palette[dut.artwork.british[0]],"outer celestial background")
  if(frozen[20])begin
   `CHECK(pixels[132*800+28]==({frozen[53],frozen[13:12]}==0 ? 24'hd6b979 : 24'h4b4534),"selected timbre border")
   `CHECK(pixels[124*800+464]==(frozen[22:21]==1 ? 24'hd6b979 : 24'h4b4534),"selected effect border")
  end else begin
   `CHECK(pixels[234*800+32]==24'hd6b979,"actual waveform first point at positive zero crossing")
   `CHECK(pixels[350*800+34]==(frozen[64] ? 24'hd6b979 : 24'h101214),"held C4 monitor highlight")
  end
  $sformat(filename,"%0s/ui_%0d.ppm",outdir,which);fd=$fopen(filename,"wb");
  $fwrite(fd,"P6\n800 480\n255\n");
  for(integer i=0;i<384000;i=i+1)$fwrite(fd,"%c%c%c",pixels[i][23:16],pixels[i][15:8],pixels[i][7:0]);
  $fclose(fd);
 end endtask
 task spot(input integer xx,yy,input [23:0] expected,input bit visible);begin
  @(negedge clk);x=xx;y=yy;de=1;repeat(2)@(negedge clk);
  `CHECK(rgb===expected && de_out==visible,"test pattern and clipping follow same pixel pipeline")
 end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
  #12 rst=0;
  status[15]=1;status[5:0]=3;status[64+:16]=16'h0091;status[87:80]=40;
  for(integer j=0;j<128;j=j+1)status[88+j*8+:8]=$rtoi(60*$sin(6.28318530718*j/32));status[11:6]=1;
  status[30:24]=25;status[37:31]=25;status[44:38]=50;status[48:45]=5;
  snapshot;render(0);
  status=frozen;status[20]=1;status[22:21]=1;status[23]=1;status[13:12]=1;status[37:31]=70;
  snapshot;render(1);
  status=frozen;status[22:21]=2;status[53]=1;status[13:12]=2;status[44:38]=80;status[48:45]=7;status[49]=1;status[50]=1;status[51]=1;
  snapshot;render(2);
  status=frozen;status[52]=1;status[18]=1;status[5:0]=32;
  snapshot;render(3);
  status=frozen;status[22:21]=0;status[30:24]=100;snapshot;
  spot(679,264,24'hd6b979,1);spot(680,264,24'h191c20,1);
  status[30:24]=0;snapshot;spot(380,264,dut.artwork.british_palette[dut.artwork.british[132*400+190]],1);
  status=frozen;status[19]=1;snapshot;
  spot(50,200,24'hffffff,1);spot(150,200,24'hffff00,1);spot(250,200,24'h00ffff,1);
  spot(350,200,24'h00ff00,1);spot(450,200,24'hff00ff,1);spot(550,200,24'hff0000,1);
  spot(650,200,24'h0000ff,1);spot(750,200,24'h000000,1);spot(799,200,24'hf2e6c9,1);
  spot(800,200,24'h000000,0);
  valid=0;status=0;snapshot;`CHECK(dut.state[19],"invalid snapshot cannot replace current frame state")
  rst=1;repeat(3)@(negedge clk);`CHECK(!de_out && rgb==0,"reset blanks both pipeline stages")
  $display("PASS tb_rgb_ui_renderer checks=%0d frames=4",checks);$finish;
 end
 initial begin #50000000;$fatal(1,"UI raster timeout");end
endmodule
