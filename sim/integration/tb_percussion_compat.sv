`timescale 1ns/1ps
// App-exported canonical records run through the unchanged production validator
// and scheduler. It is not a UART/radio/STA test and uses a 1MHz scheduler clock
// parameter to keep the five-second musical example inexpensive to simulate.
module tb_percussion_compat;
 reg clk=0,rst=1,start=0,cmd_valid=0;always #5 clk=~clk;
 reg [95:0] records[0:63];wire [5:0] va,pa;reg [95:0] vd,pd;
 wire done,vbusy,cr,cd,ev,pbusy,fault,legacy;wire [7:0] error;
 wire [31:0] duration,pos;wire [1:0] kind,play;wire [6:0] id,pitch,velocity;wire [4:0] timbre;
 integer checks=0,ons=0,offs=0,clears=0;reg [15:0] held=0;reg [31:0] endings[0:15];
 localparam integer NOTE_MIN=21,NOTE_MAX=108;
 `include "config/score_record.svh"
 score_validator #(.MAX_NOTES(64),.VOICES(16),.NOTE_MIN(21),.NOTE_MAX(108)) validator(
  clk,rst,start,16'd6,32'h488e9eb5,va,vd,vbusy,done,error,duration,1'b1);
 bt_score_player #(.CLOCK_HZ(1000000),.MAX_NOTES(64),.VOICES(16)) player(
  clk,rst,cmd_valid,cr,2'd0,cd,16'd6,32'd5000,pa,pd,ev,1'b1,kind,id,pitch,velocity,play,pos,pbusy,fault,1'b1,timbre,legacy);
 always @(posedge clk)begin vd<=records[va];pd<=records[pa];end
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s on=%0d off=%0d pos=%0d",why,ons,offs,pos);end endtask
 always @(posedge clk)if(!rst)begin
  if(fault)$fatal(1,"original production scheduler deadline error");
  if(ev)begin
   check(!legacy,"extended drum identity preserved");
   if(kind==1)begin
    check(ons<6 && {timbre,pitch,velocity}=={records[ons][68:64],records[ons][38:32],records[ons][46:40]},"App record timbre/pitch/velocity reaches scheduler");
    check(pos==records[ons][31:0] && !held[id],"On time and independent logical identity");
    held[id]=1;endings[id]=records[ons][31:0]+records[ons][63:48];ons++;
   end else if(kind==0)begin
    check(held[id] && pos==endings[id],"each one-shot record gets its exact final Off");held[id]=0;offs++;
   end else begin clears++;held=0;end
  end
 end
 initial begin
  reg [95:0] rec;integer keys;
  $readmemh("android/examples/drums_gong_records96.hex",records,0,5);
  keys=0;
  for(integer key=0;key<128;key++)begin
   rec={16'd0,8'd9,3'd0,score_drum(8'(key)),score_drum_ms(score_drum(8'(key))),8'd100,8'(key),32'd0};
   if(score_drum(8'(key))!=31)begin check(score_record_valid(rec,1),"existing canonical drum record accepted");keys++;end
   else check(!score_record_valid(rec,1),"unmapped raw GM key remains rejected by unchanged wire validator");
  end
  check(keys==22,"old firmware accepts exactly22 keys in10 drum groups");
  repeat(4)@(negedge clk);rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);check(error==0 && duration==5000,"actual old validator accepts Java fixture CRC and duration");
  @(negedge clk);cmd_valid=1;do @(posedge clk);while(!cr);@(negedge clk);cmd_valid=0;
  wait(ons==6 && offs==6 && play==0 && !pbusy);repeat(5)@(negedge clk);
  check(clears==2 && held==0,"start clear and natural finish release all events");
  $display("PASS tb_percussion_compat checks=%0d ons=%0d offs=%0d clears=%0d",checks,ons,offs,clears);$finish;
 end
 initial begin #80000000;$fatal(1,"percussion compatibility timeout");end
endmodule
