
`timescale 1ns/1ps
module tb_audio_ab;
 reg clk=0,rst=1,nv=0,on=0;always #40.690104167 clk=~clk;
 reg [6:0] id=60;reg [31:0] fcw=23409859;wire nr,ready,frame;integer fd,frames=0,first=-1;string dir;
 synth_core #(.VOICES(8),.STEREO_ENABLE(1),.MUTE(1),.FADE(1),
`ifdef FIXED
 .SUSTAIN_ENABLE(1),
`endif
 .OUTPUT_GAIN(24)) sound(.clk(clk),.rst(rst),.note_valid(nv),.note_on(on),.note_id(id),.note_fcw(fcw),.note_timbre(3'd0),
 .note_ready(nr),.input_ready(ready),.frame_ce(frame),.effects_enable(1'b1),.effect_mode(2'd0),.effect_cfg_valid(1'b1),
 .effect_echo_wet(9'd256),.effect_room_wet(9'd0),.effect_tremolo_depth(9'd0),.effect_tremolo_rate_hz(5'd5),
 .effect_echo_samples(17'd7200),.effect_mask(3'b001),.flush(1'b0),.output_flush(1'b0),.velocity_valid(1'b0),
 .note_velocity(7'd127),.volume_percent(7'd100),.note_pitch(id));
 defparam sound.timing.HALF_CYCLES=4;
 always @(posedge frame)if(ready)begin #1;
  $fwrite(fd,"%0d,%0d\n",$signed(sound.frame_l),$signed(sound.frame_r));
  if(first<0 && (sound.frame_l!=0 || sound.frame_r!=0))first=frames;
  frames++;
 end
 task waitframes(input integer n);integer target;begin target=frames+n;wait(frames>=target);@(negedge clk);end endtask
 task event_send(input bit pressed,input [6:0] key);begin
  @(negedge clk);on=pressed;id=key;fcw=key==60?23409859:key==64?29494575:35075158;nv=1;
  do @(posedge clk);while(!nr);@(negedge clk);nv=0;
 end endtask
 initial begin
  if(!$value$plusargs("OUT=%s",dir))$fatal(1,"missing output");fd=$fopen({dir,"/pcm.csv"},"w");
  #100 rst=0;wait(ready);waitframes(512); // settle wet/ramp before the first short tap
  $display("ONSET_FRAME %0d",frames);event_send(1,60);waitframes(96);event_send(0,60);waitframes(96);
  event_send(1,60);waitframes(96);event_send(0,60);waitframes(96);
  event_send(1,64);event_send(1,67);waitframes(96);event_send(0,64);event_send(0,67);
  waitframes(17000);$fclose(fd);$display("PASS tb_audio_ab first_sound_frame=%0d total=%0d",first,frames);$finish;
 end
 initial begin #500000000;$fatal(1,"AB timeout");end
endmodule
