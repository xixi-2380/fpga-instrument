`timescale 1ns/1ps
module tb_release_admission;
 reg clk=0,rst=1,enabled=0,ready=0;always #5 clk=~clk;
 reg [35:0] keys=0,observed=0;reg [4:0] timbre=0;
 wire valid,on,gate;wire [6:0] id;wire [31:0] fcw;wire [5:0] last_key;wire [4:0] tone;
 key_note_events #(.KEYS(36)) dut(clk,rst,enabled,keys,ready,valid,on,id,fcw,gate,last_key,timbre,tone);
 integer checks=0,ons=0,offs=0;reg stalled=0;reg [44:0] previous;
 always @(posedge clk)begin
  if(rst)begin observed=0;stalled=0;end
  else begin
   checks++;
   if(stalled && (!valid || {on,id,fcw,tone}!==previous))$fatal(1,"Held event changed before handshake");
   stalled=valid&&!ready;previous={on,id,fcw,tone};
   if(valid && ready)begin
    if(id<60 || id>95 || observed[id-60]===on)$fatal(1,"Duplicate/invalid acknowledged transition");
    observed[id-60]=on;if(on)ons++;else offs++;
   end
  end
 end
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task settle(input [35:0] wanted);integer budget;begin
  budget=0;
  while(observed!==wanted || dut.reported_keys!==wanted || valid || dut.lookup_pending || dut.select_pending)begin
   clocks(1);budget++;if(budget>1000)$fatal(1,"Adapter failed to drain admission=%b keys=%h observed=%h",enabled,keys,observed);
  end
  checks++;
 end endtask
 initial begin
  clocks(3);rst=0;clocks(2);
  // On is already offered: disabling admission never withdraws its payload.
  enabled=1;keys=1;wait(valid);@(negedge clk);enabled=0;keys=0;timbre=15;
  clocks(300);if(!valid || !on || id!=60)$fatal(1,"Backpressured On was withdrawn");
  ready=1;settle(0);
  if(ons!=1 || offs!=1)$fatal(1,"Short accepted On lacked matching Off");
  // Disable during priority/ROM preparation, before valid has risen.
  enabled=1;ready=0;keys=2;wait(dut.select_pending);@(negedge clk);enabled=0;keys=0;
  clocks(50);ready=1;settle(0);
  if(ons!=2 || offs!=2)$fatal(1,"In-flight priority selection lost release");
  // A new key while disabled must not prevent an old key's Off.
  enabled=1;keys=4;settle(4);enabled=0;keys=8;settle(0);
  clocks(30);if(valid || observed)$fatal(1,"Disabled fresh press was admitted");
  keys=0;clocks(5);
  // held means held, without an arbitrary maximum duration.
  enabled=1;keys=16;settle(16);enabled=0;clocks(1000);
  if(observed!=16 || !gate)$fatal(1,"A legitimate held key was forcibly timed out");
  keys=0;settle(0);
  // A36-key chord released while blocked drains every acknowledged key.
  enabled=1;keys='1;settle('1);enabled=0;keys=0;settle(0);
  if(ons!=offs)$fatal(1,"Unbalanced final ownership");
  $display("PASS tb_release_admission checks=%0d ons=%0d offs=%0d",checks,ons,offs);$finish;
 end
 initial begin #100000;$fatal(1,"Admission release timeout");end
endmodule
