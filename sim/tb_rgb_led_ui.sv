`timescale 1ns/1ps
module tb_rgb_led_ui;
 `include "../src/config/ui_layout.svh"
 reg clk=0,rst=1,fs=0,down=0;always #5 clk=~clk;
 reg [15:0] xx=0,yy=0;wire av,page;wire [6:0] action;wire [15:0] cfg;
 reg [1207:0] status=0;reg [519:0] led=0;reg [10:0] x=0,y=0;reg de=0,record=0;
 wire [23:0] rgb;wire deo,hso,vso;reg [23:0] pixels[0:383999];integer n=0,checks=0,events=0,fd;
 reg [4095:0] outdir,filename;reg [519:0] frozen;
 ui_touch_actions touch(clk,rst,1'b1,1'b1,1'b1,1'b0,down,4'd1,xx,yy,16'd800,16'd480,2'd0,1'b1,av,action,1'b0,1'b0,1'b0,page);
 rgb_led_settings settings(clk,rst,1'b1,av,action,cfg,page);
 rgb_ui_renderer dut(clk,rst,fs,1'b1,status,x,y,de,1'b1,1'b1,rgb,deo,hso,vso,146'd0,2592'd0,,led);
 always @(posedge clk)begin #1;if(record && deo)begin pixels[n]=rgb;n++;end end
 always @(posedge clk)if(av)events++;
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task tap(input integer px,py,input [6:0] expected);integer before_n;begin
  @(negedge clk);down=0;repeat(3)@(negedge clk);xx=px;yy=py;down=1;before_n=events;
  repeat(5)@(negedge clk);check(action==expected && events==before_n+1,"visible touch rectangle and action");
  repeat(10)@(negedge clk);check(events==before_n+1,"holding RGB controls cannot repeat");
  down=0;repeat(3)@(negedge clk);
 end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
  #12;rst=0;repeat(3)@(negedge clk);
  tap(480,440,UI_RGB_OPEN);check(page,"settings bottom RGB entry");
  tap(680,110,UI_RGB_TOGGLE);
  for(integer i=0;i<4;i++)tap(24+i*192+20,170,UI_RGB_STATIC+i);
  for(integer i=0;i<8;i++)tap(24+i*96+20,260,UI_RGB_COLOR+i);
  tap(50,330,UI_RGB_DOWN);tap(400,330,UI_RGB_UP);tap(600,330,UI_RGB_REVERSE);
  check(cfg[14] && cfg[13:12]==3 && cfg[11:9]==7 && cfg[8:2]==10 && cfg[1],"settings field routing");
  status[20]=1;status[15]=1;led[519:504]=cfg;
  for(integer i=0;i<21;i++)led[i*24+:24]={8'(i*12),8'(252-i*12),8'd30};
  @(negedge clk);fs=1;@(negedge clk);fs=0;repeat(5)@(negedge clk);frozen=dut.led_state;record=1;
  for(integer py=0;py<480;py++)for(integer px=0;px<800;px++)begin
   @(negedge clk);x=px;y=py;de=1;
   if(py==200 && px==100)led='1;
   check(dut.led_state===frozen,"RGB snapshot frozen for full raster");
  end
  @(negedge clk);de=0;repeat(6)@(negedge clk);record=0;
  check(n==384000,"full800x480 output");
  check(pixels[152*800+600]==24'hd6b979,"selected KEY LINK border");
  check(pixels[240*800+696]==24'hd6b979,"selected white palette border");
  for(integer i=0;i<21;i++)check(pixels[390*800+30+i*36]==frozen[i*24+:24],"target preview21 physical pixels");
  $sformat(filename,"%0s/rgb_settings.ppm",outdir);fd=$fopen(filename,"wb");$fwrite(fd,"P6\n800 480\n255\n");
  for(integer i=0;i<384000;i++)$fwrite(fd,"%c%c%c",pixels[i][23:16],pixels[i][15:8],pixels[i][7:0]);$fclose(fd);
  tap(700,40,UI_RGB_BACK);check(!page,"touch back preserves underlying settings");
  $display("PASS tb_rgb_led_ui checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"RGB UI timeout");end
endmodule
