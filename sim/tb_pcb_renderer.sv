`timescale 1ns/1ps
`include "check.svh"
module tb_pcb_renderer;
 reg clk=0,rst=1,frame_start=0,valid=1,de=0;always #5 clk=~clk;
 reg [1206:0] status=0;reg [10:0] x=0,y=0;
 reg [145:0] more_status=0,frozen_more;wire [2591:0] pcb;reg [1023:0] hw=0;reg av=0;reg [5:0] act_code=63;
 wire [159:0] control;wire [2:0] clear;wire mute,active;
 pcb_debug_ui ui(.clk(clk),.rst(rst),.ms_ce(1'b1),.menu_mode(1'b1),.mute_ack(1'b1),
  .action_valid(av),.action(act_code),.hardware_valid(1'b1),.hardware(hw),.encoder_diag(384'd0),
  .encoder_events(12'd0),.audio_status(320'd0),.mute_request(mute),.page_active(active),
  .control(control),.encoder_clear(clear),.display(pcb),.display_visible(1'b1));
 task act(input [5:0] a);begin @(negedge clk);act_code=a;av=1;@(negedge clk);av=0;repeat(32)@(negedge clk);end endtask
 wire [23:0] rgb;wire de_out,hs_out,vs_out;
 reg record=0;reg [23:0] pixels[0:383999];
 integer checks=0,n=0,fd,scene;reg [4095:0] outdir;reg [4095:0] filename;
 reg [1206:0] frozen;
 rgb_ui_renderer dut(clk,rst,frame_start,valid,status,x,y,de,1'b1,1'b1,rgb,de_out,hs_out,vs_out,more_status,pcb,,64'd0);
 always @(posedge clk)begin #1;
  if(record && de_out)begin
   `CHECK(n<384000 && (^rgb)!==1'bx,"defined pixel within full frame")
   pixels[n]=rgb;n=n+1;
  end
 end
 task snapshot;begin
  @(negedge clk);frame_start=1;de=0;@(negedge clk);frame_start=0;repeat(4)@(negedge clk);
 end endtask
 task render(input integer which);begin
  n=0;record=1;frozen=dut.state;frozen_more=dut.more_state;
  for(integer yy=0;yy<480;yy=yy+1)for(integer xx=0;xx<800;xx=xx+1)begin
   @(negedge clk);x=xx;y=yy;de=1;
   if(yy==240 && xx==100)status=~status;
   `CHECK(dut.state==frozen && dut.more_state==frozen_more,"UI state remains atomic for entire raster")
  end
  @(negedge clk);de=0;repeat(4)@(negedge clk);record=0;
  `CHECK(n==384000,"exactly 800x480 rendered pixels after pipeline flush")
  `CHECK(pixels[0]==24'h101214,"outer black background")
  if(!pcb[2560] && frozen[20] && frozen_more[81])
   `CHECK(pixels[430*800+340]==24'h101214,"library page cannot inherit main-page ultrasonic entry")
  if(pcb[2560])begin
   `CHECK(pixels[80*800+24]==(scene==0 ? 24'hd6b979 : 24'h4b4534),"active tab border")
  end else if(frozen[20] && frozen[1166])begin
   `CHECK(pixels[100*800+500]==24'hd6b979,"enabled ultrasonic toggle border")
   `CHECK(pixels[180*800+500]==24'h4b4534,"sensitivity decrease border")
  end else if(frozen[20] && !frozen_more[81])begin
   `CHECK(pixels[132*800+28]==({frozen[53],frozen[13:12]}==0 ? 24'hd6b979 : 24'h4b4534),"selected timbre border")
   `CHECK(pixels[124*800+464]==(frozen[22:21]==1 ? 24'hd6b979 : 24'h4b4534),"selected effect border")
  end else if(!frozen[20])begin
   `CHECK(pixels[234*800+32]==24'hd6b979,"actual waveform first point at positive zero crossing")
   `CHECK(pixels[350*800+34]==(frozen[64] ? 24'hd6b979 : 24'h101214),"held C4 monitor highlight")
   `CHECK(pixels[390*800+705]==(frozen[1203] ? 24'hd6b979 : 24'h101214),"highest B6 appears in third octave row")
  end
  $sformat(filename,"%0s/ui_%0d.ppm",outdir,which);fd=$fopen(filename,"wb");
  $fwrite(fd,"P6\n800 480\n255\n");
  for(integer i=0;i<384000;i=i+1)$fwrite(fd,"%c%c%c",pixels[i][23:16],pixels[i][15:8],pixels[i][7:0]);
  $fclose(fd);
 end endtask
 task spot(input integer xx,yy,input [23:0] expected,input bit visible);begin
  @(negedge clk);x=xx;y=yy;de=1;repeat(4)@(negedge clk);
  `CHECK(rgb===expected && de_out==visible,"test pattern and clipping follow same pixel pipeline")
 end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
  hw[771:640]={{16{8'd4}},4'd2};hw[903:772]={{16{8'd4}},4'd2};
  hw[908:906]=7;hw[911:909]=7;hw[608:592]='1;hw[609]=1;hw[142]=1;hw[140]=1;hw[139]=1;
  hw[95:64]=32'h00010001;hw[191:176]=16'h120;
  #12 rst=0;status[20]=1;status[15]=1;act(42);
  for(scene=0;scene<5;scene++)begin
   act(44+scene);status[20]=1;snapshot;render(scene);status=frozen;
  end
  $display("PASS tb_pcb_renderer checks=%0d frames=5",checks);$finish;
 end
 initial begin #50000000;$fatal(1,"PCB raster timeout");end
endmodule
