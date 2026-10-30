`timescale 1ns/1ps
module tb_bt_natural_sustain;
 parameter integer TIMBRE=3,LEGACY=1;
 reg clk=0,rst=1,ev=0,inh=0;always #8.138020833 clk=~clk;
 reg [1:0] kind=0;wire er,nv,nr,on,flush,oflush,frame,ready,quiet,pending;
 wire [6:0] id,vel,pitch;wire [31:0] fcw;wire [4:0] timbre;
 wire [1:0] active,held;wire signed [15:0] pcm;wire pv,under;
 integer checks=0,frames=0,tail_pcm=0,acks=0;
 bluetooth_audio_bridge #(.WAIT_FOR_TAIL(1),.NATURAL_QUIET_FRAMES(85)) bridge(
 .clk(clk),.rst(rst),.frame_ce(frame),.event_valid(ev),.event_ready(er),.event_kind(kind),
 .event_id(7'd0),.event_pitch(7'd60),.event_velocity(7'd127),.inhibit(inh),
 .note_valid(nv),.note_ready(nr),.note_on(on),.note_id(id),.note_fcw(fcw),.note_velocity(vel),
 .flush(flush),.output_flush(oflush),.selected_timbre(LEGACY ? 5'(TIMBRE) : 5'd0),.note_timbre(timbre),.note_pitch(pitch),
 .event_timbre(LEGACY ? 5'd15 : 5'(TIMBRE)),.event_legacy(1'(LEGACY)),.audio_ready(ready),.audio_quiet(quiet),.tail_pending(pending));
 synth_core #(.VOICES(2),.SUSTAIN_ENABLE(1),.STEREO_ENABLE(1),.MUTE(1),.FADE(1),
 .ROOM_D0(7),.ROOM_D1(11),.ROOM_D2(13),.ROOM_D3(17)) sound(
 .clk(clk),.rst(rst),.note_valid(nv),.note_on(on),.note_id(id),.note_fcw(fcw),.note_ready(nr),
 .input_ready(ready),.frame_ce(frame),.voice_active(active),.voice_held(held),.visual_sample(pcm),.visual_sample_valid(pv),
 .note_timbre(timbre),.effects_enable(1'b1),.effect_mode(2'd0),.effect_cfg_valid(1'b1),
 .effect_echo_wet(9'd256),.effect_room_wet(9'd128),.effect_tremolo_depth(9'd128),.effect_tremolo_rate_hz(5'd20),
 .effect_echo_samples(17'd960),.effect_mask(3'b111),.flush(flush),.output_flush(oflush),
 .velocity_valid(1'b1),.note_velocity(vel),.volume_percent(7'd100),.note_pitch(pitch),.debug_mute(1'b0),
 .audio_quiet(quiet),.underrun(under));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task more(input integer n);repeat(n)begin @(posedge frame);@(negedge clk);end endtask
 task send(input [1:0] k);begin
  @(negedge clk);kind=k;ev=1;do @(posedge clk);while(!er);
  @(negedge clk);ev=0;
 end endtask
 always @(posedge clk)if(!rst)begin
  if(frame)frames++;
  if(ev && er)acks++;
  if(pending && pv && pcm!=0)tail_pcm++;
  if(under)$fatal(1,"audio underrun");
 end
 initial begin
  #101 rst=0;wait(ready);inh=1;send(2);send(1);check(timbre==TIMBRE,"legacy selection and extended per-note timbre are preserved");more(1);send(0);send(3);inh=0;
  check(pending && !flush && !oflush,"natural EOF is acknowledged without resetting the short note release");
  more(100);check(pending && active!=0 && held==0,"one-frame tap continues beyond legacy66-frame clear");
  more(400);check(active!=0 && tail_pcm>0,"short cello tap has real stereo PCM throughout its release");
  wait(!pending && !flush);more(5);
  check(active==0 && held==0 && quiet && sound.frame_l==0 && sound.frame_r==0,"natural release and room decay complete in exact digital silence");
  tail_pcm=0;more(256);check(quiet && active==0 && pcm==0,"idle output does not restart after the natural tail finishes");
  inh=1;send(2);send(1);more(1100);
  check(held!=0 && active!=0,"a normal held note is not killed by the20ms release setting");
  send(0);send(3);inh=0;more(2);check(pending && !flush,"second natural tail begins");
  send(2);more(3);check(!pending && active==0 && quiet,"STOP interrupts natural tail promptly and clears both channels");
  check(acks==9,"each event including natural EOF is acknowledged exactly once");
  $display("PASS tb_bt_natural_sustain checks=%0d tailPCM=%0d frames=%0d",checks,tail_pcm,frames);$finish;
 end
 initial begin #200000000;$fatal(1,"natural sustain timeout");end
endmodule
