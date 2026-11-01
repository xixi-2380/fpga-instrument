`timescale 1ns/1ps
module tb_sustain_retrigger;
 parameter integer VOICES=8,TIMBRE=0;
 reg clk=0,rst=1,nv=0,on=0;always #8.138020833 clk=~clk;
 reg [6:0] id=60;reg [31:0] fcw=23409859;
 wire nr,ready,frame,underrun;wire [VOICES-1:0] active,held;
 integer checks=0,old_slot=-1,new_slot=-1,first_sound=-1;
 synth_core #(.VOICES(VOICES),.SUSTAIN_ENABLE(1),.STEREO_ENABLE(1),.MUTE(1),.FADE(1)) sound(
 .clk(clk),.rst(rst),.note_valid(nv),.note_on(on),.note_id(id),.note_fcw(fcw),
 .note_ready(nr),.input_ready(ready),.frame_ce(frame),.voice_active(active),.voice_held(held),.underrun(underrun),
 .note_timbre(5'(TIMBRE)),.effects_enable(1'b1),.effect_mode(2'd0),.effect_cfg_valid(1'b1),
 .effect_echo_wet(9'd256),.effect_room_wet(9'd0),.effect_tremolo_depth(9'd0),.effect_tremolo_rate_hz(5'd20),
 .effect_echo_samples(17'd96000),.effect_mask(3'b001),.flush(1'b0),.output_flush(1'b0),
 .velocity_valid(1'b0),.note_velocity(7'd127),.volume_percent(7'd100),.note_pitch(id),.debug_mute(1'b0));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task frames(input integer n);repeat(n)begin @(posedge frame);@(negedge clk);end endtask
 task event_send(input bit pressed,input [6:0] key);begin
  @(negedge clk);on=pressed;id=key;fcw=key==60?23409859:key==64?29494575:35075158;nv=1;
  do @(posedge clk);while(!nr);@(negedge clk);nv=0;
 end endtask
 initial begin
  #101 rst=0;wait(ready);event_send(1,60);frames(4);
  for(integer i=0;i<VOICES;i++)if(held[i])old_slot=i;
  check(old_slot>=0,"first manual onset owns a physical slot");
  event_send(0,60);frames(2);
  check(active[old_slot] && !held[old_slot],"very short manual tap releases into a sustained voice");
  event_send(1,60);frames(3);
  for(integer i=0;i<VOICES;i++)if(held[i])new_slot=i;
  check(new_slot!=old_slot && active[old_slot],"same-key repeat allocates another slot instead of resetting the previous tail");
  check(sound.voices[0].sustain_on.tail.total==96000,"two-second duration reaches the production voice without overflow");
  event_send(0,60);frames(3);event_send(1,64);frames(2);event_send(1,67);frames(2);
  event_send(0,64);event_send(0,67);frames(3);
  check($countones(active)==4 && held==0,"rapid chord releases preserve all four overlapping tails");
  for(integer n=0;n<110;n++)begin
   frames(1);if(first_sound<0 && (sound.frame_l!=0 || sound.frame_r!=0))first_sound=n;
  end
  check(first_sound>=0 && first_sound<90,"first audible PCM is available within milliseconds, not after the2s tail time");
  check($countones(active)==4 && !underrun,"tails survive later note events and both channels meet their sample deadline");
  $display("PASS tb_sustain_retrigger checks=%0d first_sound_frames=%0d",checks,first_sound);$finish;
 end
 initial begin #10000000;$fatal(1,"sustain retrigger timeout");end
endmodule
