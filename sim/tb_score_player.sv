`timescale 1ns/1ps
`include "check.svh"
module tb_score_player;
 parameter integer ENABLE=1,BEAT_FRAMES=8,TAIL_FRAMES=6,SCORE_KIND=0;
 localparam SCORE_FILE=SCORE_KIND==0?"src/scores/twinkle.hex":
  SCORE_KIND==1?"sim/data/score_player_test.hex":
  SCORE_KIND==2?"sim/data/score_player_fault.hex":
  SCORE_KIND==3?"sim/data/score_player_boundary.hex":"sim/data/does_not_exist.hex";
 localparam WORDS=SCORE_KIND==0?512:SCORE_KIND==1?16:1;
 localparam EVENT_COUNT=SCORE_KIND==0?336:6;
 reg clk=0,rst=1,input_ready=0,ready=0,block_ready=0;
 reg [3:0] tick=0;wire frame_ce=tick==15;
 wire valid,on,busy,done,error;wire [6:0] id;wire [31:0] fcw;wire [1:0] timbre;
 integer checks=0,accepted=0,frame_count=0,last_frame=0,off_frame=0,observed=-1;
 integer cycles=0,step,slot,pitch,note,expected_id,expected_timbre,expected_wait;
 integer previous_step,expected_tail,stall_cycles=0;
 reg stalled=0,completion_seen=0;reg [41:0] payload=0;
 real hz;reg [31:0] expected_fcw;
 always #5 clk=~clk;
 always @(posedge clk)if(rst)tick<=0;else tick<=tick+1'b1;
 // Repeated long stalls span frame boundaries, not just single-cycle bubbles.
 always @(negedge clk)begin cycles=cycles+1;ready<=!block_ready && cycles%97>=41;end
 score_player #(.SCORE_FILE(SCORE_FILE),.SCORE_WORDS(WORDS),.ENABLE(ENABLE),
  .BEAT_FRAMES(BEAT_FRAMES),.TAIL_FRAMES(TAIL_FRAMES)) dut(
  .clk(clk),.rst(rst),.input_ready(input_ready),.frame_ce(frame_ce),.note_ready(ready),
  .note_valid(valid),.note_on(on),.note_id(id),.note_fcw(fcw),.note_timbre(timbre),
  .busy(busy),.done(done),.error(error));
 // Independent standard melody; do not read back the ROM to form expectations.
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
   accepted=0;frame_count=0;last_frame=0;off_frame=0;observed=-1;
   stalled=0;completion_seen=0;stall_cycles=0;
  end else begin
   if(frame_ce)frame_count=frame_count+1;
   if(stalled)begin
    `CHECK(valid && {timbre,on,id,fcw}===payload,"all file event fields remain stable until handshake")
    stall_cycles=stall_cycles+1;
   end
   stalled=valid && !ready;payload={timbre,on,id,fcw};
   if(SCORE_KIND<2 && valid && observed!=accepted)begin
    if(SCORE_KIND==0)begin
     step=accepted/8;expected_wait=0;
     if(accepted%8==4)expected_wait=(step%7==6?6:3)*(BEAT_FRAMES/4);
     if(accepted%8==0 && accepted>0)expected_wait=((step-1)%7==6?2:1)*(BEAT_FRAMES/4);
    end else begin
     case(accepted)0,2:expected_wait=BEAT_FRAMES/2;5:expected_wait=BEAT_FRAMES/4;
      default:expected_wait=0;endcase
    end
    if(expected_wait>0)begin
     `CHECK(frame_count-last_frame>=expected_wait && frame_count-last_frame<=expected_wait+1,
       "file waits count exact CE frames plus at most one ROM fetch frame")
    end
    observed=accepted;
   end
   if(valid && ready)begin
    if(SCORE_KIND<2)begin
     `CHECK(accepted<EVENT_COUNT,"file must not emit extra events")
     if(SCORE_KIND==0)begin
      step=accepted/8;slot=accepted%4;note=melody(step);expected_id=slot;
      `CHECK(on==(accepted%8<4),"original score keeps four Ons followed by four Offs")
      if(slot==0)pitch=note;
      else if(note==65 || note==69)case(slot)1:pitch=65;2:pitch=69;default:pitch=72;endcase
      else if(note==62)case(slot)1:pitch=67;2:pitch=71;default:pitch=74;endcase
      else case(slot)1:pitch=60;2:pitch=64;default:pitch=67;endcase
      expected_timbre=slot==0?1:0;
     end else begin
      case(accepted)
       0,2:begin expected_id=17;pitch=66;expected_timbre=2;end
       1,3:begin expected_id=99;pitch=58;expected_timbre=0;end
       default:begin expected_id=17;pitch=72;expected_timbre=1;end
      endcase
      `CHECK(on==(accepted<2 || accepted==4),"custom score releases before same-time identity reuse")
     end
     hz=440.0*(2.0**(($itor(pitch)-69.0)/12.0));
     expected_fcw=$rtoi(hz*4294967296.0/48000.0+0.5);
     `CHECK(id==expected_id && timbre==expected_timbre && fcw==expected_fcw,
       "file-selected pitch, identity and timbre match independent score")
    end
    accepted=accepted+1;last_frame=frame_count;off_frame=frame_count;
   end
   if(ENABLE && done && !completion_seen)begin
    expected_tail=TAIL_FRAMES+(SCORE_KIND==1?BEAT_FRAMES/4:0);
    `CHECK(accepted==EVENT_COUNT && frame_count-off_frame>=expected_tail &&
      frame_count-off_frame<=expected_tail+2,"END and optional final rest precede release tail/handoff")
    completion_seen=1;
   end
  end
 end
 initial begin
  #12 rst=0;repeat(10)@(negedge clk);
  if(!ENABLE)begin
   input_ready=1;repeat(32)@(negedge clk);
   `CHECK(done && !busy && !valid && !error && accepted==0,"disabled player does not read missing file or block keyboard")
  end else if(SCORE_KIND==2 || SCORE_KIND==3)begin
   input_ready=1;wait(error);repeat(20)@(negedge clk);
   `CHECK(busy && !done && !valid,"invalid opcode or ROM overrun cannot hand off an unfinished score")
   `CHECK(accepted==(SCORE_KIND==3?1:0),"bounded ROM never wraps and repeats an event")
   rst=1;#1;`CHECK(!valid && !error,"reset clears file fault")
  end else begin
   `CHECK(busy && !valid && accepted==0,"file source waits for startup permission")
   input_ready=1;block_ready=1;wait(valid);repeat(20)@(negedge clk);block_ready=0;
   wait(done);repeat(3)@(negedge clk);
   `CHECK(completion_seen && !busy && !valid && !error && stall_cycles>10,"one-shot file playback survives long stalls")
   repeat(30)@(negedge clk);
   `CHECK(accepted==EVENT_COUNT && done && !valid,"END never loops automatically")
   rst=1;block_ready=1;#11;rst=0;wait(valid);repeat(5)@(negedge clk);
   `CHECK(accepted==0 && busy && valid,"reset rewinds specified file even with ready blocked")
   rst=1;#1;`CHECK(!valid,"reset cancels an offered file event")
   #11;rst=0;wait(valid);#1;
   `CHECK(on && id==(SCORE_KIND==0?0:17) && timbre==(SCORE_KIND==0?1:2),"replay starts at selected file's first event")
  end
  $display("PASS tb_score_player checks=%0d beat_frames=%0d score_kind=%0d",checks,BEAT_FRAMES,SCORE_KIND);$finish;
 end
 initial begin #1000000000;$fatal(1,"file score player timeout");end
endmodule
