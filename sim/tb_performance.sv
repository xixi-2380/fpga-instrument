`timescale 1ns/1ps
module tb_performance;
 reg clk=0;always #5 clk=~clk;reg rst=1;
 reg qv=0,rr=0;wire qr,rv;reg [80:0] q=0;wire [164:0] response;reg unavailable=0;reg [35:0] keys=0;reg pending=0;
 reg ev=0,on=0;reg [5:0] key=0;reg [6:0] pitch=60,vel=100;reg [4:0] tone=4;
 reg ls=0,lp=0;wire [7:0] le;wire [575:0] map;wire locked;wire [63:0] ui;
 reg lv=0;wire lr,sv;reg sr=0;reg [575:0] lm=0;wire [591:0] sd;reg [31:0] ss=32'h30000000;
 reg [159:0] reply;reg [31:0] expected_crc,token=42;reg [575:0] edited;integer checks=0;
 instrument_features #(.MS_CYCLES(2)) d(clk,rst,qv,qr,q,rv,rr,response,unavailable,keys,pending,ev,on,key,pitch,vel,tone,ls,lp,le,map,locked,ui,lv,lr,lm,sv,sr,sd,ss,1'b0);
 function automatic [31:0] crc8(input [31:0] c,input [7:0] b);reg [31:0] v;begin v=c^{24'd0,b};for(integer j=0;j<8;j++)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc8=v;end endfunction
 task check(input bit b,input [255:0] why);begin checks++;if(!b)$fatal(1,"%0s state=%d response=%h",why,d.rec_state,reply);end endtask
 task cmd(input [7:0] c,input [8:0] n,input [63:0] data,input [7:0] error);begin
  @(negedge clk);while(!qr)@(negedge clk);q={data,n,c};qv=1;@(negedge clk);qv=0;
  while(!rv)@(negedge clk);reply=response[159:0];check(reply[7:0]==error,"command error");check(response[164:160]<=20,"reply bound");rr=1;@(negedge clk);rr=0;
 end endtask
 task event_note(input bit start,input [5:0] k,input [6:0] p,input [4:0] t);begin @(negedge clk);ev=1;on=start;key=k;pitch=p;tone=t;@(negedge clk);ev=0;end endtask
 task frozen;begin while(d.rec_state!=5)@(negedge clk);end endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;repeat(4)@(negedge clk);
  for(integer j=0;j<36;j++)check(map[j*16+:16]=={8'd31,8'(60+j)},"default mapping");
  cmd('h50,0,0,0);check(reply[63:48]==4096,"capability");cmd('h50,1,0,3);
  edited=map;edited[15:0]={8'd9,8'd21};edited[31:16]={8'd31,8'd108};expected_crc='1;for(integer j=0;j<72;j++)expected_crc=crc8(expected_crc,edited[j*8+:8]);expected_crc=~expected_crc;
  cmd('h52,8,{expected_crc,token},0);
  cmd('h54,4,token,6);
  for(integer j=0;j<36;j++)cmd('h53,7,{8'd0,edited[j*16+:16],8'(j),token},0);
  keys=1;cmd('h54,4,token,5);keys=0;cmd('h54,4,token,0);check(map==edited,"atomic map");
  cmd('h51,1,0,0);check(reply[31:16]=={8'd9,8'd21},"mapped readback");
  cmd('h55,4,expected_crc^1,6);
  // Invalid staging CRC cannot change the active map.
  cmd('h52,8,{32'd0,token},0);for(integer j=0;j<36;j++)cmd('h53,7,{8'd0,edited[j*16+:16],8'(j),token},0);cmd('h54,4,token,9);check(map==edited,"bad crc atomic");
  keys=1;cmd('h61,0,0,5);keys=0;unavailable=1;cmd('h61,0,0,5);unavailable=0;
  cmd('h61,0,0,0);check(locked,"capture lock");cmd('h57,0,0,5);
  event_note(1,0,21,9);repeat(140010)@(negedge clk);event_note(1,1,108,0);event_note(1,2,108,15);event_note(0,1,108,4);
  cmd('h62,0,0,0);frozen();check(!locked,"freeze unlock");
  cmd('h63,0,0,0);check(reply[63:48]==3 && reply[15:8]==5,"record count");token=reply[47:16];expected_crc=32'hffffffff;
  for(integer j=0;j<3;j++)begin cmd('h64,6,{16'd0,16'(j),token},0);for(integer k=8;k<20;k++)expected_crc=crc8(expected_crc,reply[k*8+:8]);if(j==0)check(reply[127:96]>65535,"32 bit held duration");if(j==1)check(reply[151:144]==0,"onset tone retained");if(j==2)check(reply[151:144]==15,"concurrent tone retained");end
  check(~expected_crc==d.final_crc,"full capture CRC");cmd('h64,6,{16'd0,16'd0,token+32'd1},6);
  cmd('h61,0,0,0);for(integer j=0;j<4096;j++)begin event_note(1,0,60,4);if(j!=4095)event_note(0,0,60,4);end
  frozen();check(d.count==4096 && d.reason==2,"full recorder stops explicitly");cmd('h63,0,0,0);token=reply[47:16];expected_crc='1;
  for(integer j=0;j<4096;j++)begin cmd('h64,6,{16'd0,16'(j),token},0);check(reply[127:96]>=1,"nonzero duration");for(integer k=8;k<20;k++)expected_crc=crc8(expected_crc,reply[k*8+:8]);end
  check(~expected_crc==d.final_crc,"4096 download CRC");
  cmd('h65,4,token,0);check(d.count==0 && d.rec_state==0,"clear");
  @(negedge clk);ls=1;@(negedge clk);ls=0;check(locked,"local start");event_note(1,35,108,15);@(negedge clk);lp=1;@(negedge clk);lp=0;frozen();check(d.count==1,"local stop");
  cmd('h61,0,0,0);for(integer j=0;j<36;j++)event_note(1,6'(j),60,5'(j%16));cmd('h62,0,0,0);frozen();check(d.count==36,"capture beyond automatic polyphony");
  cmd('h61,0,0,0);repeat(7200005)@(negedge clk);frozen();check(d.reason==3 && d.elapsed==3600000,"one hour automatic stop");
  $display("PASS tb_performance checks=%0d (4096 capture/CRC, mapping, long duration, duplicate pitch, local control)",checks);$finish;
 end
 initial begin #200000000;$fatal(1,"timeout");end
endmodule
