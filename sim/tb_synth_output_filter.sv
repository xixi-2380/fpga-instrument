`timescale 1ns/1ps
// The integer/float filter math is independently checked by its unit suite.
// Here a bypassed complete engine drives separate reference filters, followed
// by an independent pending-pair/tag scoreboard and an external I2S receiver.
module tb_synth_output_filter;
 parameter integer OUTPUT_ENABLE=1,STEREO=1,MUTE_TEST=0,VOICES=32;
 reg clk=0,rst=1,nv=0,no=0,flush=0,hard=0,cfg=0;always #5 clk=~clk;
 reg [6:0] id=60,pitch=60,velocity=127,volume=100;
 reg [4:0] tone=0;reg [31:0] fcw=23409859;reg [2:0] mask=0;
 wire nr,nrr,ready,readyr,bck,bckr,ws,wsr,din,dinr,pa,par,u,ur,ce,cer,gate,gater,vs,vsr;
 wire [VOICES-1:0] active,activer,held,heldr;wire [16:0] level,levelr;
 wire signed [15:0] visual,visualr;wire [35:0] notes,notesr;
 wire er=rst||hard;
 synth_core #(.VOICES(VOICES),.OUTPUT_FILTER_ENABLE(1),.SHARED_ENVELOPE_PRECALC(1),.SUSTAIN_ENABLE(1),.PERFORMANCE_ENABLE(1),.STEREO_ENABLE(STEREO),.VISUAL_KEYS(36),.MUTE(1),.FADE(1),.ATTACK(4),.DECAY(4),.RELEASE(12),.OUTPUT_ENABLE(OUTPUT_ENABLE),.DELAY_SAMPLES(17),.ROOM_D0(3),.ROOM_D1(5),.ROOM_D2(7),.ROOM_D3(11)) dut(
  .clk(clk),.rst(rst),.note_valid(nv),.note_on(no),.note_id(id),.note_fcw(fcw),.note_pitch(pitch),.note_timbre(tone),.note_velocity(velocity),.velocity_valid(1'b1),.volume_percent(volume),.flush(flush),.output_flush(hard),
  .note_ready(nr),.input_ready(ready),.bck(bck),.ws(ws),.din(din),.pa_enable(pa),.underrun(u),.frame_ce(ce),.gate(gate),.voice_active(active),.voice_held(held),.envelope_level(level),.visual_sample_valid(vs),.visual_sample(visual),.visual_notes(notes),
  .effects_enable(1'b1),.effect_mode(2'd0),.effect_mask(mask),.effect_cfg_valid(cfg),.effect_echo_wet(9'd96),.effect_room_wet(9'd80),.effect_tremolo_depth(9'd128),.effect_tremolo_rate_hz(5'd7),.effect_echo_samples(17'd120),.debug_mute(1'b0),.manual_pitch_ratio(18'd65536),.chorus_enabled(1'b1),.chorus_wet(9'd96),.chorus_depth(2'd1),.chorus_rate(2'd1));
 synth_core #(.VOICES(VOICES),.OUTPUT_FILTER_ENABLE(0),.SHARED_ENVELOPE_PRECALC(1),.SUSTAIN_ENABLE(1),.PERFORMANCE_ENABLE(1),.STEREO_ENABLE(STEREO),.VISUAL_KEYS(36),.MUTE(1),.FADE(1),.ATTACK(4),.DECAY(4),.RELEASE(12),.OUTPUT_ENABLE(OUTPUT_ENABLE),.DELAY_SAMPLES(17),.ROOM_D0(3),.ROOM_D1(5),.ROOM_D2(7),.ROOM_D3(11)) raw(
  .clk(clk),.rst(rst),.note_valid(nv),.note_on(no),.note_id(id),.note_fcw(fcw),.note_pitch(pitch),.note_timbre(tone),.note_velocity(velocity),.velocity_valid(1'b1),.volume_percent(volume),.flush(flush),.output_flush(hard),
  .note_ready(nrr),.input_ready(readyr),.bck(bckr),.ws(wsr),.din(dinr),.pa_enable(par),.underrun(ur),.frame_ce(cer),.gate(gater),.voice_active(activer),.voice_held(heldr),.envelope_level(levelr),.visual_sample_valid(vsr),.visual_sample(visualr),.visual_notes(notesr),
  .effects_enable(1'b1),.effect_mode(2'd0),.effect_mask(mask),.effect_cfg_valid(cfg),.effect_echo_wet(9'd96),.effect_room_wet(9'd80),.effect_tremolo_depth(9'd128),.effect_tremolo_rate_hz(5'd7),.effect_echo_samples(17'd120),.debug_mute(1'b0),.manual_pitch_ratio(18'd65536),.chorus_enabled(1'b1),.chorus_wet(9'd96),.chorus_depth(2'd1),.chorus_rate(2'd1));
 wire expected_valid,expected_valid_r;wire signed [15:0] expected_l,expected_r;wire [16:0] expected_tag,expected_tag_r;
 reg [8:0] reference_zero_samples=0;
 wire reference_silence=reference_zero_samples==260 && volume==0;
 always @(posedge clk or posedge er)
  if(er)reference_zero_samples<=0;
  else if(volume!=0)reference_zero_samples<=0;
  else if(raw.output_valid && reference_zero_samples<260)reference_zero_samples<=reference_zero_samples+1'b1;
 audio_output_filter ref_l(.clk(clk),.rst(er),.in_valid(raw.output_valid),.in_sample(raw.output_sample),.in_tag(raw.volume_output_tag),.silence(reference_silence),.out_valid(expected_valid),.out_sample(expected_l),.out_tag(expected_tag));
 audio_output_filter ref_r(.clk(clk),.rst(er),.in_valid(raw.output_valid_r),.in_sample(raw.output_sample_r),.in_tag(raw.volume_output_tag),.silence(reference_silence),.out_valid(expected_valid_r),.out_sample(expected_r),.out_tag(expected_tag_r));
 wire signed [16:0] expected_visual_sum={expected_l[15],expected_l}+{expected_r[15],expected_r};
 reg pending_valid=0;reg [15:0] pending_l=0,pending_r=0,active_l=0,active_r=0,current_l=0,current_r=0;
 reg [16:0] pending_tag=0,serial_tag=0;
 wire model_ready=!pending_valid||ce;
 wire [15:0] model_frame_l=ce?(pending_valid?pending_l:16'd0):active_l;
 wire [15:0] model_frame_r=ce?(pending_valid?pending_r:16'd0):active_r;
 integer checks=0,frames=0,outputs=0,serial_words=0,different=0,tagged_outputs=0,flushes=0,events=0,mute_outputs=0,resumed_outputs=0;
 reg mute_monitor=0,resumed_monitor=0,force_dc=0;
 always @(force_dc)begin
  if(force_dc)begin force dut.limited_sample=16'sd32767;force raw.limited_sample=16'sd32767;end
  else begin release dut.limited_sample;release raw.limited_sample;end
 end
 generate if(STEREO)begin
  always @(force_dc)begin
   if(force_dc)begin force dut.stereo_on.right_limited_sample=-16'sd32768;force raw.stereo_on.right_limited_sample=-16'sd32768;end
   else begin release dut.stereo_on.right_limited_sample;release raw.stereo_on.right_limited_sample;end
  end
 end endgenerate
 reg rx_synced=0,previous_ws=1;integer bitn=0,ch=0,word=0;reg [15:0] pair_l,pair_r;
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task more(input integer n);integer goal;begin goal=frames+n;wait(frames>=goal);@(negedge clk);end endtask
 task offer(input bit on,input integer key,pp,tt);begin
  @(negedge clk);nv=1;no=on;id=key;pitch=pp;tone=tt;fcw=32'd1307191*(pp-30);
  do @(posedge clk);while(!nr);
  events++;@(negedge clk);nv=0;
 end endtask
 always @(posedge clk)if(!rst)begin
  if(ce)begin frames++;current_l=er?16'd0:(pending_valid?pending_l:16'd0);current_r=er?16'd0:(pending_valid?pending_r:16'd0);end
  check({nr,ready,bck,ws,pa,ce,gate,active,held,level,notes}==={nrr,readyr,bckr,wsr,par,cer,gater,activer,heldr,levelr,notesr},"filter leaves voice control/clocks unchanged");
  check(!u,"filtered complete engine never underruns");
  #0.001;
  check({dut.output_valid,dut.output_valid_r,dut.output_sample,dut.output_sample_r,dut.output_tag,dut.output_tag_r}==={expected_valid,expected_valid_r,expected_l,expected_r,expected_tag,expected_tag_r},"final PCM and tags match separately filtered bypass engine");
  check({dut.volume_valid,dut.volume_valid_r,dut.volume_sample,dut.volume_sample_r}==={raw.output_valid,raw.output_valid_r,raw.output_sample,raw.output_sample_r},"filter is downstream of both master volume stages");
  check(dut.ready===model_ready && {dut.frame_l,dut.frame_r}==={model_frame_l,model_frame_r},"atomic frame queue matches independent pair scoreboard");
  check(dut.serial_tag===serial_tag,"LAT serial tag follows filtered pending pair");
  check(vs===expected_valid,"visualizer uses filtered valid");
  check(dut.filter_silence===reference_silence,"explicit filter mute follows260 accepted zero-volume outputs");
  if(expected_valid)begin
   outputs++;if(expected_l!=expected_r)different++;if(expected_tag[16])tagged_outputs++;
   check(visual===(STEREO?(expected_visual_sum>>>1):expected_l),"visualizer uses final filtered stereo average");
   if(mute_monitor)begin mute_outputs++;check({dut.output_sample,dut.output_sample_r}===32'd0,"zero volume stays exactly digital0 without losing valid/tag");end
   if(resumed_monitor && (dut.output_sample!=0 || dut.output_sample_r!=0))resumed_outputs++;
  end
 end
 always @(posedge clk or posedge er)begin
  if(er)begin pending_valid<=0;pending_l<=0;pending_r<=0;active_l<=0;active_r<=0;pending_tag<=0;serial_tag<=0;end
  else begin
   if(ce)begin
    active_l<=pending_valid?pending_l:16'd0;active_r<=pending_valid?pending_r:16'd0;
    serial_tag<=pending_valid?pending_tag:17'd0;pending_valid<=0;
   end
   if(expected_valid && model_ready)begin pending_valid<=1;pending_l<=expected_l;pending_r<=expected_r;pending_tag<=expected_tag;end
  end
 end
 always @(posedge rst)begin current_l=0;current_r=0;rx_synced=0;previous_ws=1;bitn=0;ch=0;word=0;end
 always @(posedge bck)if(!rst)begin
  if(rx_synced)begin
   if(bitn==0 && ch==0)begin pair_l=current_l;pair_r=current_r;end
   word=((word<<1)|din)&65535;
   if(bitn==15)begin
    check(ws!=previous_ws && ws!=ch,"I2S boundary carries old channel LSB");
    check(word==(ch==0?pair_l:pair_r),"external I2S word matches final filtered atomic pair");
    serial_words++;ch=ws;word=0;bitn=0;
   end else begin check(ws==previous_ws,"I2S word contains16 bits");bitn++;end
  end else if(ws!=previous_ws)begin rx_synced=1;ch=ws;bitn=0;word=0;end
  previous_ws=ws;
 end
 initial begin
  repeat(4)@(negedge clk);rst=0;wait(ready);more(80);
  cfg=1;@(negedge clk);cfg=0;
  for(integer n=0;n<12;n++)offer(1,60+n,54+3*n,n%16);
  more(45);
  for(integer n=0;n<12;n++)offer(0,60+n,54+3*n,n%16);
  more(20);mask=6;
  for(integer n=0;n<8;n++)offer(1,n,48+4*n,n%16);
  more(30);
  // Clear mid-filter transaction: reset every pending stage/tag immediately,
  // while the serializer finishes its already latched word atomically.
  wait(dut.volume_valid);@(negedge clk);hard=1;flush=1;flushes++;
  #0.001;check({dut.output_valid,dut.output_valid_r,dut.output_sample,dut.output_sample_r,dut.output_tag,dut.output_tag_r}===68'd0,"urgent clear cancels filter PCM/valid/tags");
  repeat(3)@(negedge clk);hard=0;flush=0;more(85);
  for(integer n=0;n<4;n++)offer(1,60+n,60+n,n);
  more(20);
  wait(dut.output_valid);@(negedge clk);hard=1;flushes++;repeat(2)@(negedge clk);hard=0;more(85);
  if(MUTE_TEST)begin
   force_dc=1;more(32);volume=0;more(270);
   check(dut.filter_silence,"mute completed after worst-case256-sample volume ramp");
   check({dut.output_sample,dut.output_sample_r,dut.frame_l,dut.frame_r}===64'd0,"zero-volume final PCM and committed pair are digital0");
   mute_monitor=1;more(25);offer(1,67,67,5);more(15);
   volume=100;mute_monitor=0;more(270);
   check(!dut.filter_silence,"raising volume exits explicit filter silence");
   resumed_monitor=1;more(16);resumed_monitor=0;force_dc=0;more(8);
   check(mute_outputs>=35 && resumed_outputs>=10,"mute and restored audio both exercised");
  end
  // One tag per completed onset burst is sufficient in direct output mode;
  // the64-sample limiter repeats tags while its delay line drains.
  $display("ACTIVITY outputs=%0d tagged=%0d serial=%0d events=%0d flushes=%0d mute=%0d resumed=%0d",outputs,tagged_outputs,serial_words,events,flushes,mute_outputs,resumed_outputs);
  check(outputs>200 && tagged_outputs>=3 && serial_words>500 && events==(MUTE_TEST?37:36) && flushes==2,"sufficient filtered/tagged_outputs/serialized integration activity");
  if(STEREO)check(different>30,"left/right filtered signals are independent");
  $display("PASS tb_synth_output_filter checks=%0d frames=%0d outputs=%0d tags=%0d serial_words=%0d differing=%0d output_enable=%0d stereo=%0d mute_test=%0d voices=%0d",checks,frames,outputs,tagged_outputs,serial_words,different,OUTPUT_ENABLE,STEREO,MUTE_TEST,VOICES);$finish;
 end
 initial begin #100000000;$fatal(1,"filtered core timeout");end
endmodule
