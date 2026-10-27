`timescale 1ns/1ps
// End-to-end timestamp checked from accepted On and external I2S bit edges.
module tb_audio_latency;
 parameter integer STEREO=0;
 reg clk=0,rst=1,nv=0,on=1,flush=0,hard=0;always #8.138020833 clk=~clk;
 reg [6:0] id=60,volume=100;wire nr,ir,bck,ws,din,pa,u,frame_ce,gate,valid;
 wire [31:0] active,held;wire [16:0] level;wire [19:0] bcd;
 integer checks=0,frames=0,bitn=0,channel=0,measured,reference_units;
 reg synced=0,previous_ws=1,waiting=0,finished=0;reg [15:0] expected_epoch;
 realtime accepted_at=0,completed_at=0;
 synth_core #(.STEREO_ENABLE(STEREO),.MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.RELEASE(2)) sound(
 .clk(clk),.rst(rst),.note_valid(nv),.note_on(on),.note_id(id),.note_fcw(32'd23409859),.note_timbre(3'd0),
 .note_ready(nr),.input_ready(ir),.bck(bck),.ws(ws),.din(din),.pa_enable(pa),.underrun(u),
 .frame_ce(frame_ce),.gate(gate),.voice_active(active),.voice_held(held),.envelope_level(level),
 .effects_enable(1'b0),.effect_mode(2'd0),.effect_cfg_valid(1'b0),.volume_percent(volume),
 .flush(flush),.output_flush(hard),.velocity_valid(1'b0),.note_velocity(7'd127),.note_pitch(id),
 .latency_valid(valid),.latency_bcd(bcd));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task more(input integer n);integer target;begin target=frames+n;wait(frames>=target);#1;end endtask
 task offer(input integer ident);begin
  @(negedge clk);id=ident;nv=1;wait(nr);@(posedge clk);
  accepted_at=$realtime;#0.001;expected_epoch=sound.latency_meter.epoch;finished=0;waiting=1;
  @(negedge clk);nv=0;
 end endtask
 task finish_measure;begin
  wait(finished);repeat(24)@(negedge clk);
  measured=bcd[19:16]*10000+bcd[15:12]*1000+bcd[11:8]*100+bcd[7:4]*10+bcd[3:0];
  reference_units=$rtoi((completed_at-accepted_at)/10000.0);
  check(valid && measured>=reference_units-1 && measured<=reference_units+1,"BCD matches physical LEFT-LSB edge within0.01ms");
  check(measured>=133 && measured<140,"includes64-frame output delay and actual serializer phase");
  $display("MEASURED_LATENCY units10us=%0d edge_reference=%0d",measured,reference_units);
 end endtask
 always @(posedge clk)if(!rst)begin
  if(frame_ce)frames++;check(!u,"latency observation never stalls audio");
 end
 always @(posedge bck)if(!rst)begin
  if(synced)begin
   if(bitn==15)begin
    if(channel==0 && waiting && sound.serial_tag[16] && sound.serial_tag[15:0]==expected_epoch)begin
     completed_at=$realtime;waiting=0;finished=1;
    end
    channel=ws;bitn=0;
   end else bitn++;
  end else if(ws!=previous_ws)begin synced=1;channel=ws;bitn=0;end
  previous_ws=ws;
 end
 initial begin
  #100 rst=0;wait(ir);more(80);check(!valid,"homepage has no invented latency before first On");
  offer(60);finish_measure();more(10);
  // A polyphonic second On must not measure the already-playing first voice.
  offer(64);finish_measure();
  volume=0;more(270);offer(67);finish_measure();
  check(sound.output_sample==0,"digital-pipeline latency is defined even while user-muted");
  offer(69);@(negedge clk);flush=1;hard=1;waiting=0;repeat(5)@(negedge clk);flush=0;hard=0;
  more(75);check(!sound.latency_meter.awaiting,"urgent clear cancels an in-flight measurement");
  check(sound.volume_control.gain==0,"measurement/flush does not restore muted volume");
  $display("PASS tb_audio_latency checks=%0d",checks);$finish;
 end
 initial begin #25000000;$fatal(1,"latency test timeout");end
endmodule
