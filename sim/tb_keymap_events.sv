`timescale 1ns/1ps
module tb_keymap_events;
 reg clk=0;always #5 clk=~clk;reg rst=1,enabled=1,ready=0;reg [35:0] keys=0;reg [575:0] map=0;reg [4:0] preset=4;
 wire valid,on,gate,pending;wire [6:0] id,pitch;wire [31:0] fcw;wire [5:0] last_key;wire [4:0] tone;integer checks=0;
 key_note_events #(.KEYS(36),.MAPPING(1)) d(clk,rst,enabled,keys,ready,valid,on,id,fcw,gate,last_key,preset,tone,map,pitch,pending);
 task check(input bit b,input [255:0] why);begin checks++;if(!b)$fatal(1,"%0s id=%d pitch=%d tone=%d",why,id,pitch,tone);end endtask
 task event_take(input bit start,input [6:0] ident,input [6:0] p,input [4:0] t,input [31:0] f);
 begin while(!valid)@(negedge clk);check(on==start && id==ident && pitch==p && tone==t && fcw==f,"mapped event");
  repeat(7)begin @(negedge clk);check(valid && id==ident && pitch==p && tone==t && fcw==f,"stable backpressure");end ready=1;@(negedge clk);ready=0;end endtask
 initial begin
  for(integer k=0;k<36;k++)map[k*16+:16]={8'd31,8'(60+k)};
  map[15:0]={8'd9,8'd21};map[31:16]={8'd15,8'd21};map[575:560]={8'd31,8'd108};
  repeat(5)@(negedge clk);rst=0;@(negedge clk);keys=3;
  event_take(1,60,21,9,32'd2460658);event_take(1,61,21,15,32'd2460658);
  preset=0;keys=2;event_take(0,60,21,9,32'd2460658);check(gate,"second duplicate key held");
  keys=0;event_take(0,61,21,15,32'd2460658);check(!gate,"both released");
  preset=6;repeat(3)@(negedge clk);keys[35]=1;event_take(1,95,108,6,32'd374557749);
  preset=4;keys=0;event_take(0,95,108,6,32'd374557749);
  check(!pending,"fully drained");$display("PASS tb_keymap_events checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"keymap events timeout");end
endmodule
