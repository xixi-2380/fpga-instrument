`timescale 1ns/1ps
`include "check.svh"
module tb_score_player;
 parameter integer ENABLE=1,BEAT_FRAMES=8,TAIL_FRAMES=6;
 reg clk=0,rst=1,input_ready=0,ready=0,block_ready=0;
 reg [1:0] tick=0;wire frame_ce=tick==3;
 wire valid,on,busy,done;wire [6:0] id;wire [31:0] fcw;wire [1:0] timbre;
 integer checks=0,accepted=0,frame_count=0,on_frame=0,off_frame=0,observed=-1;
 integer ticks=0,step,slot,pitch,note,previous_step,expected_gap;
 reg stalled=0,completion_seen=0;reg [41:0] payload=0;
 real hz;reg [31:0] expected_fcw;
 always #5 clk=~clk;
 always @(posedge clk)if(rst)tick<=0;else tick<=tick+1'b1;
 always @(negedge clk)begin ticks=ticks+1;ready<=!block_ready && ticks%7>=2;end
 score_player #(.ENABLE(ENABLE),.BEAT_FRAMES(BEAT_FRAMES),.TAIL_FRAMES(TAIL_FRAMES))
  dut(clk,rst,input_ready,frame_ce,ready,valid,on,id,fcw,timbre,busy,done);
 // Independent musical form: six seven-note phrases, final note two beats.
 function integer melody(input integer index);integer phrase,n;begin
  phrase=index/7;n=index%7;
  if(phrase==0 || phrase==4)case(n)
   0,1:melody=60;2,3,6:melody=67;default:melody=69;endcase
  else if(phrase==1 || phrase==5)case(n)
   0,1:melody=65;2,3:melody=64;4,5:melody=62;default:melody=60;endcase
  else case(n)
   0,1:melody=67;2,3:melody=65;4,5:melody=64;default:melody=62;endcase
 end endfunction
 always @(posedge clk)begin
  if(rst)begin
   accepted=0;frame_count=0;on_frame=0;off_frame=0;observed=-1;stalled=0;completion_seen=0;
  end else begin
   if(frame_ce)frame_count=frame_count+1;
   if(stalled)begin `CHECK(valid && {timbre,on,id,fcw}===payload,"score holds every event field under backpressure") end
   stalled=valid && !ready;payload={timbre,on,id,fcw};
   if(valid && observed!=accepted)begin
    step=accepted/8;
    if(accepted%8==4)begin
     `CHECK(frame_count-on_frame==((step%7==6?2:1)*BEAT_FRAMES*3)/4,"note gate counts exact frame enables")
    end
    if(accepted%8==0 && accepted>0)begin
     previous_step=step-1;
     expected_gap=(previous_step%7==6?2:1)*BEAT_FRAMES-((previous_step%7==6?2:1)*BEAT_FRAMES*3)/4;
     `CHECK(frame_count-off_frame==expected_gap,"note gap counts exact frame enables")
    end
    observed=accepted;
   end
   if(valid && ready)begin
    step=accepted/8;slot=accepted%4;note=melody(step);
    `CHECK(accepted<336 && id==slot && on==(accepted%8<4),"each step emits four Ons then four matching Offs")
    if(slot==0)pitch=note;
    else if(note==65 || note==69)case(slot)1:pitch=65;2:pitch=69;default:pitch=72;endcase
    else if(note==62)case(slot)1:pitch=67;2:pitch=71;default:pitch=74;endcase
    else case(slot)1:pitch=60;2:pitch=64;default:pitch=67;endcase
    hz=440.0*(2.0**(($itor(pitch)-69.0)/12.0));
    expected_fcw=$rtoi(hz*4294967296.0/48000.0+0.5);
    `CHECK(fcw==expected_fcw,"score pitch uses independent equal-temperament FCW")
    `CHECK(timbre==(slot==0?1:0),"melody and chord carry their own preset")
    if(accepted%8==3)on_frame=frame_count;
    if(accepted%8==7)off_frame=frame_count;
    accepted=accepted+1;
   end
   if(ENABLE && done && !completion_seen)begin
    `CHECK(accepted==336 && frame_count-off_frame==TAIL_FRAMES,"handoff waits for the final releases and tail")
    completion_seen=1;
   end
  end
 end
 initial begin
  #12 rst=0;repeat(10)@(negedge clk);
  if(!ENABLE)begin
   input_ready=1;repeat(32)@(negedge clk);
   `CHECK(done && !busy && !valid && accepted==0,"disabled score leaves the keyboard path available")
  end else begin
   `CHECK(busy && !valid && accepted==0,"score waits for startup permission")
   input_ready=1;wait(done);repeat(3)@(negedge clk);
   `CHECK(completion_seen && !busy && !valid,"one-shot completion relinquishes the event source")
   repeat(30)@(negedge clk);
   `CHECK(accepted==336 && done && !valid,"completed score never loops automatically")
   // Reset while an offered event is blocked: no stale packet may survive.
   rst=1;block_ready=1;#11;rst=0;wait(valid);repeat(5)@(negedge clk);
   `CHECK(accepted==0 && busy && valid,"reset restarts at a backpressured first note")
   rst=1;#1;`CHECK(!valid,"reset cancels an offered score packet")
   #11;rst=0;wait(valid);#1;
   `CHECK(on && id==0 && timbre==1 && fcw==32'h016534c3,"reset replay begins with the first melody pitch")
  end
  $display("PASS tb_score_player checks=%0d beat_frames=%0d",checks,BEAT_FRAMES);$finish;
 end
 initial begin #100000000;$fatal(1,"score player timeout");end
endmodule
