`timescale 1ns/1ps
`include "check.svh"
module tb_score_seven_timbres;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [4:0] cycle=0;wire ready=cycle>12;
 wire valid,on,busy,done,error;wire [6:0] id;wire [31:0] fcw;wire [2:0] timbre;
 integer checks=0,events=0;reg stalled=0;reg [42:0] offered;
 score_player #(.SCORE_FILE("sim/data/score_seven_timbres.hex"),.SCORE_WORDS(64),.BEAT_FRAMES(4),.TAIL_FRAMES(2048)) dut(
 .clk(clk),.rst(rst),.input_ready(1'b1),.frame_ce(1'b1),.note_ready(ready),.note_valid(valid),.note_on(on),
 .note_id(id),.note_fcw(fcw),.note_timbre(timbre),.busy(busy),.done(done),.error(error));
 always @(posedge clk)if(!rst)begin
  cycle<=cycle+1'b1;
  `CHECK(!error,"extended score format accepted")
  if(stalled)`CHECK(valid && {timbre,on,id,fcw}===offered,"all three timbre bits stable under backpressure")
  stalled=valid && !ready;offered={timbre,on,id,fcw};
  if(valid && ready)begin
   `CHECK(timbre==events/2 && id==80+events/2 && on==(events%2==0),"file IDs and seven timbres decode without overlap")
   events=events+1;
  end
 end
 initial begin
  #12 rst=0;wait(done);#1;`CHECK(events==14 && !busy && !error,"all seven note pairs and release tail complete")
  $display("PASS tb_score_seven_timbres checks=%0d events=%0d",checks,events);$finish;
 end
 initial begin #1000000;$fatal(1,"extended score timeout");end
endmodule
