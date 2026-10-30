`timescale 1ns/1ps
module tb_rgb_led_notes;
 `include "../src/config/rgb_led_config.svh"
 reg clk=0,rst=1,nv=0,on=0,flush=0;always #8.138020833 clk=~clk;
 reg [6:0] id=0,pitch=60;reg [4:0] timbre=0;
 wire ready,nr,frame;wire [20:0] lamps;wire [3:0] active,held;integer checks=0;
 synth_core #(.VOICES(4),.SUSTAIN_ENABLE(1),.OUTPUT_ENABLE(0),.MUTE(1),.FADE(1)) dut(
 .clk(clk),.rst(rst),.note_valid(nv),.note_on(on),.note_id(id),.note_fcw(32'd23409859),
 .note_ready(nr),.input_ready(ready),.frame_ce(frame),.voice_active(active),.voice_held(held),
 .note_timbre(timbre),.note_pitch(pitch),.velocity_valid(1'b1),.note_velocity(7'd127),
 .effects_enable(1'b1),.effect_mode(2'd0),.effect_cfg_valid(1'b1),.effect_echo_wet(9'd256),
 .effect_room_wet(9'd0),.effect_tremolo_depth(9'd0),.effect_tremolo_rate_hz(5'd5),
 .effect_echo_samples(17'd96000),.effect_mask(3'b001),.flush(flush),.output_flush(1'b0),
 .volume_percent(7'd100),.debug_mute(1'b0),.auto_white_held(lamps));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s lamps=%h",why,lamps);end endtask
 task frames(input integer n);repeat(n)begin @(posedge frame);@(negedge clk);end endtask
 task event_note(input bit down,input [6:0] ident,p,input [4:0] tone);begin
  @(negedge clk);id=ident;pitch=p;timbre=tone;on=down;nv=1;
  do @(posedge clk);while(!nr);@(negedge clk);nv=0;frames(3);
 end endtask
 initial begin
  #45;rst=0;wait(ready);frames(3);
  for(integer n=0;n<36;n++)begin
   event_note(1,0,7'(60+n),0);check(lamps==(rgb_white_index(7'(60+n))<21?(21'd1<<rgb_white_index(7'(60+n))):0),"all white pitches and black exclusion");
   event_note(0,0,7'(60+n),0);check(lamps==0,"NoteOff ignores long release tails");
  end
  event_note(1,0,60,0);event_note(1,1,60,0);event_note(0,0,60,0);check(lamps==1,"overlapping pitch stays on until all identities release");
  event_note(0,1,60,0);check(lamps==0,"last identical note off");
  event_note(1,0,60,0);event_note(1,0,64,0);check(lamps==4,"identity reuse excludes old releasing voice");
  event_note(0,0,64,0);event_note(1,0,60,16);check(lamps==0,"drum pitched at white key cannot light");
  event_note(0,0,60,16);event_note(1,0,59,0);check(lamps==0,"below C4 excluded");
  event_note(0,0,59,0);event_note(1,0,96,0);check(lamps==0,"above B6 excluded");
  event_note(0,0,96,0);event_note(1,64,64,0);check(lamps==0,"manual metadata is not auto pitch lighting");
  check(dut.visual_notes[4] && !dut.visual_notes[0],"fixed manual pitch keeps original keyboard highlight");
  event_note(0,64,64,0);event_note(1,0,60,0);flush=1;frames(3);check(lamps==0,"urgent STOP/clear removes lamp metadata");flush=0;
  $display("PASS tb_rgb_led_notes checks=%0d",checks);$finish;
 end
 initial begin #30000000;$fatal(1,"note lamp timeout");end
endmodule
