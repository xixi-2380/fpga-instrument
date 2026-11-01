`timescale 1ns/1ps
module tb_synth_precalc_compare;
 parameter integer FRAMES=300,OUTPUT_ENABLE=0;
 reg clk=0,rst=1,nv=0,no=0,flush=0,output_flush=0,cfg=0,accepted=0;always #5 clk=~clk;
 reg [6:0] id=0,pitch=60,velocity=127,volume=100;reg [4:0] timbre=0;
 reg [31:0] fcw=23409859;reg [2:0] mask=1;reg [17:0] bend=65536;
 wire nr,nr_ref,ready,ready_ref,bck,bck_ref,ws,ws_ref,din,din_ref,pa,pa_ref,u,u_ref,ce,ce_ref,gate,gate_ref,vs,vs_ref;
 wire [31:0] active,active_ref,held,held_ref;wire [16:0] level,level_ref;wire signed [15:0] sample_value,sample_ref;
 wire [35:0] notes,notes_ref;wire lat,lat_ref;wire [19:0] bcd,bcd_ref;wire muted,muted_ref,cfgready,cfgready_ref,cfgdone,cfgdone_ref;
 integer checks=0,frames=0,serial=0,mixes=0,nonzero=0,seed=32'h2380babe,random_value,cycles=0,events=0;
 synth_core #(.SHARED_ENVELOPE_PRECALC(1),.SUSTAIN_ENABLE(1),.PERFORMANCE_ENABLE(1),.STEREO_ENABLE(1),.VISUAL_KEYS(36),.MUTE(1),.FADE(1),.OUTPUT_ENABLE(OUTPUT_ENABLE),.DELAY_SAMPLES(17),.ROOM_D0(3),.ROOM_D1(5),.ROOM_D2(7),.ROOM_D3(11)) dut(
  .clk(clk),.rst(rst),.note_valid(nv),.note_on(no),.note_id(id),.note_fcw(fcw),.note_pitch(pitch),.note_timbre(timbre),.note_velocity(velocity),.velocity_valid(1'b1),.volume_percent(volume),.flush(flush),.output_flush(output_flush),
  .note_ready(nr),.input_ready(ready),.bck(bck),.ws(ws),.din(din),.pa_enable(pa),.underrun(u),.frame_ce(ce),.gate(gate),.voice_active(active),.voice_held(held),.envelope_level(level),.visual_sample_valid(vs),.visual_sample(sample_value),.visual_notes(notes),.latency_valid(lat),.latency_bcd(bcd),.debug_muted(muted),
  .effects_enable(1'b1),.effect_mode(2'd0),.effect_mask(mask),.effect_cfg_valid(cfg),.effect_echo_wet(9'd96),.effect_room_wet(9'd80),.effect_tremolo_depth(9'd128),.effect_tremolo_rate_hz(5'd5),.effect_echo_samples(17'd120),.effect_cfg_ready(cfgready),.effect_cfg_applied(cfgdone),.debug_mute(1'b0),.manual_pitch_ratio(bend),.chorus_enabled(1'b0),.chorus_wet(9'd96),.chorus_depth(2'd1),.chorus_rate(2'd1));
 synth_core_baseline #(.SUSTAIN_ENABLE(1),.PERFORMANCE_ENABLE(1),.STEREO_ENABLE(1),.VISUAL_KEYS(36),.MUTE(1),.FADE(1),.OUTPUT_ENABLE(OUTPUT_ENABLE),.DELAY_SAMPLES(17),.ROOM_D0(3),.ROOM_D1(5),.ROOM_D2(7),.ROOM_D3(11)) ref_dut(
  .clk(clk),.rst(rst),.note_valid(nv),.note_on(no),.note_id(id),.note_fcw(fcw),.note_pitch(pitch),.note_timbre(timbre),.note_velocity(velocity),.velocity_valid(1'b1),.volume_percent(volume),.flush(flush),.output_flush(output_flush),
  .note_ready(nr_ref),.input_ready(ready_ref),.bck(bck_ref),.ws(ws_ref),.din(din_ref),.pa_enable(pa_ref),.underrun(u_ref),.frame_ce(ce_ref),.gate(gate_ref),.voice_active(active_ref),.voice_held(held_ref),.envelope_level(level_ref),.visual_sample_valid(vs_ref),.visual_sample(sample_ref),.visual_notes(notes_ref),.latency_valid(lat_ref),.latency_bcd(bcd_ref),.debug_muted(muted_ref),
  .effects_enable(1'b1),.effect_mode(2'd0),.effect_mask(mask),.effect_cfg_valid(cfg),.effect_echo_wet(9'd96),.effect_room_wet(9'd80),.effect_tremolo_depth(9'd128),.effect_tremolo_rate_hz(5'd5),.effect_echo_samples(17'd120),.effect_cfg_ready(cfgready_ref),.effect_cfg_applied(cfgdone_ref),.debug_mute(1'b0),.manual_pitch_ratio(bend),.chorus_enabled(1'b0),.chorus_wet(9'd96),.chorus_depth(2'd1),.chorus_rate(2'd1));
 always @(posedge clk)begin
  if(nv && nr)begin accepted=1;events=events+1;end
  if(!rst && ce)frames=frames+1;
  #0.001;checks=checks+1;
  if({nr,ready,bck,ws,din,pa,u,ce,gate,active,held,level,vs,sample_value,notes,lat,bcd,muted,cfgready,cfgdone,dut.output_valid,dut.output_sample,dut.output_valid_r,dut.output_sample_r,dut.mix_valid,dut.stereo_mix_l,dut.stereo_mix_r} !==
     {nr_ref,ready_ref,bck_ref,ws_ref,din_ref,pa_ref,u_ref,ce_ref,gate_ref,active_ref,held_ref,level_ref,vs_ref,sample_ref,notes_ref,lat_ref,bcd_ref,muted_ref,cfgready_ref,cfgdone_ref,ref_dut.output_valid,ref_dut.output_sample,ref_dut.output_valid_r,ref_dut.output_sample_r,ref_dut.mix_valid,ref_dut.stereo_mix_l,ref_dut.stereo_mix_r})$fatal(1,"core output mismatch cycle=%0d frames=%0d",cycles,frames);
  if(!rst)begin
   if(u)$fatal(1,"underrun");
   if(dut.mix_valid)mixes=mixes+1;
   if(dut.output_valid && (dut.output_sample!=0 || dut.output_sample_r!=0))nonzero=nonzero+1;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst=0;
  while(frames<FRAMES)begin
   @(negedge clk);cycles=cycles+1;
   cfg=cycles==2000;
   // The lookahead limiter needs 64 complete samples after engine clear.
   flush=cycles%(OUTPUT_ENABLE?200007:10007)==13 || cycles%(OUTPUT_ENABLE?200007:10007)==14;
   output_flush=cycles%(OUTPUT_ENABLE?250009:31009)==19;
   if(nv && accepted)begin nv=0;accepted=0;end
   else if(!nv && ready && cycles%43==0)begin
    random_value=$random(seed);nv=1;no=(random_value&3)!=0;id=events%3==0?events%16:60+events%48;pitch=48+events%40;timbre=events%26;velocity=48+events%80;fcw=23409859+events*7919;
   end
   if(cycles%12811==0)bend=bend==65536?73562:65536;
  end
  if(events<100 || mixes<100 || nonzero<20)$fatal(1,"insufficient activity %0d %0d %0d",events,mixes,nonzero);
  $display("PASS tb_synth_precalc_compare checks=%0d frames=%0d events=%0d mixes=%0d nonzero=%0d output_enable=%0d",checks,frames,events,mixes,nonzero,OUTPUT_ENABLE);$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
