`timescale 1ns/1ps
`include "check.svh"
module allocator_case #(parameter integer N=4)(output reg done=0,output integer checks=0);
 reg clk=0,rst=1,enabled=0,ce=0,valid=0,on=0;
 reg [6:0] id=0;reg [31:0] fcw=0;reg [N-1:0] active=0;
 always #5 clk=~clk;
 wire ready;wire [N-1:0] start,stop,restart,held;
 reg [1:0] timbre=0;wire [N*2-1:0] voice_timbres;
 wire [N*32-1:0] words;wire [N*7-1:0] ids;
 integer serial=0,target,oldest;
 reg [1:0] model_timbre[0:N-1];integer age[0:N-1];reg [6:0] owner[0:N-1];reg [31:0] frequency[0:N-1];
 reg [N-1:0] owned=0,model_held=0,pending=0,reset_pending=0,committed=0;
 reg [N-1:0] expected_start,expected_stop,expected_restart;
 voice_allocator #(.VOICES(N)) dut(clk,rst,enabled,ce,valid,on,id,fcw,active,ready,start,stop,restart,held,words,ids,timbre,voice_timbres);
 task model_reset;begin
  serial=0;owned=0;model_held=0;pending=0;reset_pending=0;committed=0;
  for(integer i=0;i<N;i=i+1)begin age[i]=0;owner[i]=0;frequency[i]=0;model_timbre[i]=0;end
 end endtask
 task compare;begin
  `CHECK(held==model_held,"held ownership matches independent timestamp model")
  for(integer i=0;i<N;i=i+1)begin
   `CHECK(dut.rank[i]<N,"rank remains bounded")
   if(owned[i])begin
    `CHECK(voice_timbres[i*2+:2]==model_timbre[i],"timbre stays atomic with ownership across stalls and frames")
    `CHECK(ids[i*7+:7]==owner[i] && words[i*32+:32]==frequency[i],"identity and FCW remain associated")
   end
   for(integer j=i+1;j<N;j=j+1)begin
    `CHECK(dut.rank[i]!=dut.rank[j],"rank is a permutation without wraparound")
    if(owned[i] && owned[j])begin `CHECK(owner[i]!=owner[j],"same identity never occupies two voices") end
   end
  end
 end endtask
 task accept_model(input bit n,input [6:0] note);begin
  target=-1;
  for(integer i=0;i<N;i=i+1)if(owned[i] && owner[i]==note)target=i;
  if(n)begin
   if(target<0)for(integer i=N-1;i>=0;i=i-1)
    if(!owned[i] || (!active[i] && !model_held[i] && !pending[i] && !committed[i]))target=i;
   if(target<0)begin
    oldest=-1;
    for(integer i=0;i<N;i=i+1)if(!model_held[i] && !pending[i])
     if(oldest<0)oldest=i;else if(age[i]<age[oldest])oldest=i;
    target=oldest;
   end
   if(target<0)begin
    target=0;for(integer i=1;i<N;i=i+1)if(age[i]<age[target])target=i;
   end
   if(!owned[target] || owner[target]!=note)reset_pending[target]=1;
   owned[target]=1;model_held[target]=1;owner[target]=note;frequency[target]=fcw;model_timbre[target]=timbre==3?0:timbre;
   age[target]=serial;serial=serial+1;pending[target]=1;
  end else if(target>=0)model_held[target]=0;
  compare;
 end endtask
 task event_note(input bit n,input [6:0] note);integer waited;begin
  @(negedge clk);valid=1;on=n;id=note;fcw=32'h10000+note;timbre=note%4;
  waited=0;
  while(!ready)begin
   @(negedge clk);waited=waited+1;
   `CHECK(waited<=2*N+4,"uninterrupted search has a bounded handshake latency")
  end
  @(posedge clk);#1;accept_model(n,note);
  @(negedge clk);valid=0;
 end endtask
 task frame;begin
  @(negedge clk);ce=1;#1;
  expected_start=pending;expected_stop=committed & ~model_held & ~pending;
  expected_restart=pending & reset_pending;
  `CHECK(!ready && start==expected_start && stop==expected_stop && restart==expected_restart,
   "frame commands preserve starts, targeted releases and restarts")
  @(posedge clk);#1;
  for(integer i=0;i<N;i=i+1)
   if(!model_held[i] && !active[i] && !pending[i] && !committed[i])owned[i]=0;
  committed=(committed & ~expected_stop)|pending;pending=0;reset_pending=0;
  compare;@(negedge clk);ce=0;
 end endtask
 // Ownership and all event fields must remain unchanged before handshake.
 reg [N*42-1:0] previous_metadata;
 always @(posedge clk)if(!rst && !ce && !(valid && ready))begin
  previous_metadata={held,words,ids,voice_timbres};#1;
  if(!rst)begin `CHECK({held,words,ids,voice_timbres}===previous_metadata,
   "unacknowledged search never mutates ownership or timbre") end
 end
 task interrupted_event(input integer mode);integer waited;begin
  @(negedge clk);valid=1;on=1;id=90+mode;fcw=32'h20000+mode;timbre=mode%3;
  if(mode==1)wait(ready);else begin @(posedge clk);#1;end
  if(mode<2)frame; // during search, or exactly before a ready handshake
  else if(mode==2)begin
   @(negedge clk);enabled=0;
   repeat(5)begin @(posedge clk);#1;`CHECK(!ready,"disabled search cannot acknowledge") compare;end
   @(negedge clk);enabled=1;
  end else begin
   @(negedge clk);rst=1;#1;active=0;model_reset;
   `CHECK(!ready && held==0,"reset cancels an unacknowledged search")
   @(negedge clk);rst=0;
  end
  waited=0;
  while(!ready)begin
   @(negedge clk);waited=waited+1;
   `CHECK(waited<=2*N+4,"interrupted search retries without losing its offered event")
  end
  @(posedge clk);#1;accept_model(1,id);
  @(negedge clk);valid=0;frame;
 end endtask
 initial begin
  model_reset;#12 rst=0;#1;`CHECK(!ready && held==0,"startup blocks events")
  enabled=1;
  for(integer i=0;i<N;i=i+1)event_note(1,7'(40+i));
  `CHECK(&held,"all configured voices fill independently")
  frame;active='1;
  event_note(0,40);frame;`CHECK(!held[0] && $countones(held)==N-1,"one release preserves peers")
  event_note(1,100);frame;`CHECK(ids[0+:7]==100 && &held,"released tail precedes held voices")
  event_note(0,40);frame;`CHECK(&held,"stale release cannot stop replacement")
  event_note(1,101);frame;
  `CHECK($countones(held)==N,"overflow note maintains configured voice count")
  `CHECK(ids[(N==1?0:1)*7+:7]==101,"overflow replaces oldest held identity")
  event_note(1,101);frame;`CHECK(expected_restart==0,"same-note retrigger preserves phase")
  // Hold an event while admission is blocked; ownership cannot change.
  @(negedge clk);enabled=0;valid=1;on=0;id=101;fcw=0;
  repeat(5)begin @(posedge clk);#1;`CHECK(!ready,"disabled admission applies backpressure") compare;end
  @(negedge clk);valid=0;enabled=1;
  for(integer n=0;n<600;n=n+1)begin
   event_note(1,7'((n*37+9)%128));
   if(n%3==0)event_note(0,7'((n*11+7)%128));
   if(n%7==0)frame;
  end
  frame;
  @(negedge clk);rst=1;#1;active=0;model_reset;
  `CHECK(held==0 && !ready,"reset clears all ownership")
  @(negedge clk);rst=0;
  event_note(1,60);event_note(0,60);frame;
  `CHECK(expected_start==1 && held==0,"short On/Off retains one start without held note")
  frame;`CHECK(expected_stop==1,"short note releases on following frame")
  frame;event_note(1,60);frame;
  `CHECK(expected_restart==1,"completed release restarts cleanly")
  for(integer mode=0;mode<4;mode=mode+1)interrupted_event(mode);
  $display("ALLOCATOR_CASE voices=%0d checks=%0d",N,checks);done=1;
 end
endmodule
module tb_voice_allocator;
 wire d1,d3,d4,d17,d32;wire integer c1,c3,c4,c17,c32;
 allocator_case #(.N(1)) one(d1,c1);
 allocator_case #(.N(3)) three(d3,c3);
 allocator_case #(.N(4)) four(d4,c4);
 allocator_case #(.N(17)) seventeen(d17,c17);
 allocator_case #(.N(32)) thirty_two(d32,c32);
 initial begin wait(d1 && d3 && d4 && d17 && d32);
  $display("PASS tb_voice_allocator checks=%0d",c1+c3+c4+c17+c32);$finish;end
 initial begin #1000000;$fatal(1,"allocator timeout");end
endmodule

