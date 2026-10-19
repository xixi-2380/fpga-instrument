`timescale 1ns/1ps
`include "check.svh"
module tb_key_note_events;
 reg clk=0,rst=1,enabled=0,ready=0;always #5 clk=~clk;
 reg [15:0] keys=0,observed=0;
 wire valid,on,gate;wire [6:0] id;wire [31:0] fcw;wire [3:0] last_key;
 wire [1:0] event_timbre;reg [1:0] selected_timbre=0;
 always @(negedge clk)if(!rst)selected_timbre<=selected_timbre==2?0:selected_timbre+1'b1;
 reg stalled=0;reg [41:0] payload;
 integer checks=0,events=0,idx;
 real hz;reg [31:0] expected;
 key_note_events dut(clk,rst,enabled,keys,ready,valid,on,id,fcw,gate,last_key,selected_timbre,event_timbre);
 always @(posedge clk)begin
  if(rst)begin observed=0;stalled=0;events=0;end
  else begin
   if(stalled)begin `CHECK(valid && {event_timbre,on,id,fcw}===payload,"offered event survives backpressure and changed keys") end
   stalled=valid && !ready;payload={event_timbre,on,id,fcw};
   if(valid && ready)begin
    `CHECK(id>=60 && id<=75,"matrix adapter emits reusable MIDI note identities")
    idx=id-60;hz=440.0*(2.0**(($itor(id)-69.0)/12.0));
    expected=$rtoi(hz*4294967296.0/48000.0+0.5);
    `CHECK(fcw==expected,"all sixteen FCWs match independent equal-temperament calculation")
    `CHECK(observed[idx]!=on,"each actual state change emits exactly one event")
    observed[idx]=on;events=events+1;
   end
  end
 end
 task settled(input [15:0] wanted);integer timeout;begin
  timeout=0;
  while(observed!=wanted || valid || dut.reported_keys!=wanted)begin
   @(negedge clk);timeout=timeout+1;
   if(timeout>200)$fatal(1,"note dispatcher did not converge");
  end
  `CHECK(gate==(|wanted),"adapter observation gate follows acknowledged state")
 end endtask
 initial begin
  #12 rst=0;keys=16'hffff;repeat(10)@(negedge clk);
  `CHECK(!valid && observed==0,"startup admission holds events")
  enabled=1;wait(valid);#1;payload={event_timbre,on,id,fcw};
  repeat(10)@(negedge clk);keys=0;repeat(10)@(negedge clk);
  `CHECK(valid && {event_timbre,on,id,fcw}===payload,"pending event is not withdrawn when keys change")
  ready=1;settled(0);`CHECK(events==2,"queued press is followed by its release, with no stuck note")
  keys=16'hffff;settled(16'hffff);`CHECK(events==18,"all simultaneous key presses are delivered")
  keys=0;settled(0);`CHECK(events==34,"all simultaneous releases are delivered")
  keys=1;settled(1);keys=2;wait(valid);#1;
  `CHECK(!on && id==60,"release selected before new press in a changed snapshot")
  settled(2);`CHECK(last_key==1,"last-key observation belongs to input adapter")
  keys=0;settled(0);
  ready=0;keys=16'h0200;wait(valid);#1;
  `CHECK(id==69 && fcw==32'h0258bf26,"A4 is independent of allocator slot")
  rst=1;#1;`CHECK(!valid && !gate,"reset discards a backpressured event")
  keys=0;#17 rst=0;ready=1;repeat(20)@(negedge clk);
  `CHECK(!valid && observed==0,"reset leaves no phantom event")
  $display("PASS tb_key_note_events checks=%0d",checks);$finish;
 end
 initial begin #100000;$fatal(1,"key event timeout");end
endmodule

