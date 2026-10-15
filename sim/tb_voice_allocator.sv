`timescale 1ns/1ps
`include "check.svh"
module tb_voice_allocator;
 reg clk=0,rst=1,enabled=0,ce=0,valid=0,on=0;
 reg [6:0] id=0;reg [31:0] fcw=0;reg [3:0] active=0;
 always #5 clk=~clk;
 wire ready;wire [3:0] start,stop,restart,held;wire [127:0] words;wire [27:0] ids;
 integer checks=0,serial=0,target,oldest;
 integer age[0:3];reg [6:0] owner[0:3];reg [31:0] frequency[0:3];
 reg [3:0] owned=0,model_held=0,pending=0,reset_pending=0,committed=0;
 reg [3:0] expected_start,expected_stop,expected_restart;
 voice_allocator dut(clk,rst,enabled,ce,valid,on,id,fcw,active,ready,start,stop,restart,held,words,ids);
 task model_reset;begin
  serial=0;owned=0;model_held=0;pending=0;reset_pending=0;committed=0;
  for(integer i=0;i<4;i=i+1)begin age[i]=0;owner[i]=0;frequency[i]=0;end
 end endtask
 task compare;begin
  `CHECK(held==model_held,"held ownership matches independent timestamp allocator")
  for(integer i=0;i<4;i=i+1)if(owned[i])begin
   `CHECK(ids[i*7+:7]==owner[i] && words[i*32+:32]==frequency[i],"note identity and FCW stay with allocated slot")
  end
 end endtask
 task event_note(input bit n,input [6:0] note);begin
  @(negedge clk);valid=1;on=n;id=note;fcw=32'h10000+note;
  wait(ready);@(posedge clk);#1;
  target=-1;
  for(integer i=0;i<4;i=i+1)if(owned[i] && owner[i]==note)target=i;
  if(n)begin
   if(target<0)for(integer i=3;i>=0;i=i-1)
    if(!owned[i] || (!active[i] && !model_held[i] && !pending[i] && !committed[i]))target=i;
   if(target<0)begin
    oldest=-1;
    for(integer i=0;i<4;i=i+1)if(!model_held[i] && !pending[i])
     if(oldest<0)oldest=i;else if(age[i]<age[oldest])oldest=i;
    target=oldest;
   end
   if(target<0)begin
    target=0;for(integer i=1;i<4;i=i+1)if(age[i]<age[target])target=i;
   end
   if(!owned[target] || owner[target]!=note)reset_pending[target]=1;
   owned[target]=1;model_held[target]=1;owner[target]=note;frequency[target]=fcw;
   age[target]=serial;serial=serial+1;pending[target]=1;
  end else if(target>=0)model_held[target]=0;
  compare;
  @(negedge clk);valid=0;
 end endtask
 task frame;begin
  @(negedge clk);ce=1;#1;
  expected_start=pending;expected_stop=committed & ~model_held & ~pending;
  expected_restart=pending & reset_pending;
  `CHECK(!ready && start==expected_start && stop==expected_stop && restart==expected_restart,
   "frame commands preserve starts, targeted releases and ownership resets")
  @(posedge clk);#1;
  for(integer i=0;i<4;i=i+1)
   if(!model_held[i] && !active[i] && !pending[i] && !committed[i])owned[i]=0;
  committed=(committed & ~expected_stop)|pending;pending=0;reset_pending=0;
  compare;@(negedge clk);ce=0;
 end endtask
 initial begin
  model_reset;#12 rst=0;#1;`CHECK(!ready && held==0,"startup holds event admission")
  enabled=1;
  event_note(1,60);event_note(1,61);event_note(1,62);event_note(1,63);
  `CHECK(held==15,"four independent notes occupy four voices")
  frame;active=15;
  event_note(0,61);frame;`CHECK(held==13,"one Note Off does not release peers")
  event_note(1,65);`CHECK(ids[7+:7]==65,"released tail is preferred to a held voice")
  frame;event_note(0,61);`CHECK(held==15,"stale Note Off cannot silence the reused voice")
  event_note(1,66);`CHECK(ids[0+:7]==66,"fifth held note steals the oldest assignment")
  frame;event_note(0,60);`CHECK(held==15,"stolen old note release is ignored")
  event_note(1,66);frame;`CHECK(expected_restart==0,"same-note retrigger preserves existing phase and level")
  for(integer n=0;n<160;n=n+1)begin
   event_note(1,7'(70+n%40));
   if(n%3==0)event_note(0,7'(70+(n+37)%40));
   if(n%7==0)frame;
  end
  frame;
  @(negedge clk);rst=1;#1;active=0;model_reset;
  `CHECK(held==0 && !ready,"reset clears all ownership")
  @(negedge clk);rst=0;
  event_note(1,60);event_note(0,60);frame;
  `CHECK(expected_start==1 && held==0,"short On/Off is retained without leaving a held note")
  frame;`CHECK(expected_stop==1,"short note is released on following frame")
  frame;event_note(1,60);frame;
  `CHECK(expected_restart==1,"completed release makes slot available with clean restart")
  $display("PASS tb_voice_allocator checks=%0d",checks);$finish;
 end
 initial begin #100000;$fatal(1,"allocator timeout");end
endmodule
