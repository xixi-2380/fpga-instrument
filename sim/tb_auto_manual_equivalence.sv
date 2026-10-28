`timescale 1ns/1ps
`include "check.svh"
// Same sample-boundary events, full velocity, fresh identities in both paths.
// Different scheduler identities must not change the PCM or stereo framing.
// Released-ID reuse has intentionally different semantics; tested separately.
module tb_auto_manual_equivalence;
 parameter integer TIMBRE=-1;
 reg clk=0,rst=1,nv=0,on=0;always #8.138020833 clk=~clk;
 reg [6:0] ident=0,pitch=60;reg [31:0] fcw=23409859;
 reg [2:0] timbre=0,mask=0;
 wire ar,mr,ai,mi,af,mf,au,mu,ab,mb,aw,mw,ad,md;
 wire [31:0] aa,ma,ah,mh;
 integer checks=0,outputs=0,fd,scene=0;reg [4095:0] file;
 synth_core #(.STEREO_ENABLE(1),.MUTE(1),.FADE(1)) automatic_path(
 .clk(clk),.rst(rst),.note_valid(nv),.note_on(on),.note_id(ident),.note_fcw(fcw),
 .note_ready(ar),.input_ready(ai),.frame_ce(af),.underrun(au),.voice_active(aa),.voice_held(ah),
 .bck(ab),.ws(aw),.din(ad),.note_timbre(timbre),.note_pitch(pitch),.note_velocity(7'd127),.velocity_valid(1'b1),
 .flush(1'b0),.output_flush(1'b0),.volume_percent(7'd100),.effects_enable(1'b0),.effect_mode(2'd0),
 .effect_mask(mask),.effect_cfg_valid(1'b0),.effect_echo_samples(15'd960));
 synth_core #(.STEREO_ENABLE(1),.MUTE(1),.FADE(1)) manual_path(
 .clk(clk),.rst(rst),.note_valid(nv),.note_on(on),.note_id(pitch),.note_fcw(fcw),
 .note_ready(mr),.input_ready(mi),.frame_ce(mf),.underrun(mu),.voice_active(ma),.voice_held(mh),
 .bck(mb),.ws(mw),.din(md),.note_timbre(timbre),.note_pitch(pitch),.note_velocity(7'd127),.velocity_valid(1'b0),
 .flush(1'b0),.output_flush(1'b0),.volume_percent(7'd100),.effects_enable(1'b0),.effect_mode(2'd0),
 .effect_mask(mask),.effect_cfg_valid(1'b0),.effect_echo_samples(15'd960));
 task frames(input integer n);repeat(n)begin @(posedge af);@(negedge clk);end endtask
 task send_note(input bit yes,input integer id);begin
  @(negedge clk);on=yes;ident=id;pitch=60+id;fcw=23409859+id*1000003;nv=1;
  do @(posedge clk);while(!ar);`CHECK(mr,"identical allocator handshake boundary")
  @(negedge clk);nv=0;
 end endtask
 always @(posedge clk)if(!rst)begin
  `CHECK(!au && !mu,"both paths meet every production frame")
  `CHECK({ab,aw,ad}==={mb,mw,md},"external I2S bit/frame identical for matched input events")
  `CHECK(automatic_path.output_valid===manual_path.output_valid,"equal output delivery cycle")
  if(automatic_path.output_valid)begin
   `CHECK(automatic_path.output_sample===manual_path.output_sample && automatic_path.output_sample_r===manual_path.output_sample_r,"bit-exact stereo PCM independent of source identity")
   `CHECK(aa===ma && ah===mh,"physical ownership and release envelopes match")
   `CHECK(automatic_path.stereo_mix_l===manual_path.stereo_mix_l,"left mix matches")
   $fdisplay(fd,"%0d %0d %0d %0d %0d %0d",scene,$countones(ah),$signed(automatic_path.output_sample),$signed(automatic_path.output_sample_r),automatic_path.limiter_gain,automatic_path.stereo_on.right_limiter_gain);
   outputs=outputs+1;
  end
 end
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",file))$fatal(1,"missing output directory");
  fd=$fopen({file,"/auto_manual_pcm.txt"},"w");
  for(integer t=TIMBRE<0?0:TIMBRE;t<(TIMBRE<0?7:TIMBRE+1);t++)for(integer e=0;e<2;e++)begin
   @(negedge clk);rst=1;nv=0;timbre=t;mask=e?7:0;repeat(4)@(negedge clk);rst=0;
   wait(ai && mi);frames(70);scene=t*2+e;
   for(integer v=0;v<16;v++)begin
    send_note(1,v);
    if(v==0 || v==3 || v==7 || v==15)begin
     frames(96);`CHECK($countones(ah)==v+1,"1/4/8/16 independent physical voices")
    end
   end
   for(integer v=0;v<16;v++)send_note(0,v);
   frames(80);`CHECK(ah==0 && mh==0,"matched Off drains every held note")
  end
  $fclose(fd);$display("PASS tb_auto_manual_equivalence checks=%0d stereo_frames=%0d scenes=%0d timbre=%0d",checks,outputs,TIMBRE<0?14:2,TIMBRE);$finish;
 end
 initial begin #400000000;$fatal(1,"auto/manual equivalence timeout");end
endmodule
