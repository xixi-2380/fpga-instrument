`timescale 1ns/1ps
// Real allocator, envelopes, DDS and gain at the production 1280-cycle cadence.
module tb_bt_articulation;
 reg clk=0,rst=1,valid=0,on=0,flush=0;
 reg [6:0] id=0,velocity=127,pitch=60;
 reg [31:0] fcw=23409859;
 always #8.138020833 clk=~clk;
 wire ready,input_ready,frame,underrun;wire [3:0] held,active;
 integer checks=0;
 synth_core #(.VOICES(4),.MUTE(1),.FADE(1)) dut(
 .clk(clk),.rst(rst),.note_valid(valid),.note_on(on),.note_id(id),.note_fcw(fcw),
 .note_ready(ready),.input_ready(input_ready),.frame_ce(frame),.voice_held(held),.voice_active(active),
 .underrun(underrun),.note_timbre(3'd0),.effects_enable(1'b0),.effect_mode(2'd0),
 .effect_cfg_valid(1'b0),.flush(flush),.velocity_valid(1'b1),.note_velocity(velocity),
 .note_pitch(pitch),.volume_percent(7'd100));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task event_note(input bit n,input [6:0] identity,p,v,input [31:0] word);begin
  @(negedge clk);valid=1;on=n;id=identity;pitch=p;velocity=v;fcw=word;
  do @(posedge clk);while(!ready);
  @(negedge clk);valid=0;
 end endtask
 task rendered_frame;begin
  @(posedge clk);while(!frame)@(posedge clk);
  repeat(110)@(negedge clk);
 end endtask
 always @(posedge clk)if(!rst)check(!underrun,"render stays inside production sample deadline");
 initial begin
  #100 rst=0;wait(input_ready);
  for(integer v=0;v<128;v++)check(dut.velocity_gain(7'(v))==(v*256+63)/127,"gain arithmetic matches all MIDI velocities exactly");
  event_note(1,0,60,127,23409859);rendered_frame;
  check(held==1 && dut.voice_gains[0+:9]==256,"first automatic note owns its full gain");
  repeat(4)rendered_frame;
  event_note(0,0,60,0,23409859);rendered_frame;
  check(held==0 && active[0],"old production envelope is still releasing");
  event_note(1,0,62,32,26276679);
  check(held==2 && dut.voice_fcw[31:0]==23409859,"recycled ID allocates a separate voice and preserves old pitch");
  check(dut.voice_fcw[63:32]==26276679 && dut.allocator.pending_restart==2,"new pitch has a fresh phase/envelope command");
  rendered_frame;
  check(dut.voice_gains[0+:9]==256 && dut.voice_gains[9+:9]==65,"new velocity does not alter old release gain");
  repeat(2)rendered_frame;
  event_note(0,0,62,0,26276679);rendered_frame;
  check(held==0 && active[0] && active[1],"Off targets the current instance while both tails survive");
  event_note(1,0,64,96,29494575);rendered_frame;
  check(held==4 && dut.voice_gains[18+:9]==194,"third instance gets a distinct context and velocity");
  check(dut.voice_gains[0+:9]==256 && dut.voice_gains[9+:9]==65,"multiple released instances retain independent gains");
  // Manual pitch identity keeps the existing same-ID retrigger behavior.
  @(negedge clk);flush=1;@(negedge clk);flush=0;
  event_note(1,60,60,127,23409859);rendered_frame;
  repeat(2)rendered_frame;
  event_note(0,60,60,0,23409859);rendered_frame;
  event_note(1,60,60,127,23409859);
  check(held==1 && dut.allocator.pending_restart==0,"manual same-pitch retrigger semantics remain intact");
  @(negedge clk);flush=1;@(negedge clk);flush=0;rendered_frame;
  check(held==0 && active==0,"Silence flush clears all retained instances");
  $display("PASS tb_bt_articulation checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"articulation timeout");end
endmodule
