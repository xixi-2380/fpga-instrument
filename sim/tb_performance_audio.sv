`timescale 1ns/1ps
module tb_performance_audio;
 reg clk=0,rst=1,nv=0,no=0,chorus=0,flush=0;
 reg [6:0] id=0,pitch=60;reg [31:0] fcw=23409859;reg [17:0] ratio=65536;
 wire nr,ready,frame,u,vs;wire signed [15:0] visual;wire [31:0] held,active;
 integer trace_fd;string trace_dir;reg reset_pending=1;reg signed [15:0] dry_l,dry_r;
 integer checks=0,cycle=0,last_frame=0,max_delivery=0,renders=0,slots=0;
 reg [31:0] model_phase[0:31];reg [15:0] sine[0:4095];
 reg [31:0] expected_step,expected_start;reg [63:0] math_product;integer v;
 always #8.138020833 clk=~clk;
 synth_core #(.PERFORMANCE_ENABLE(1),.STEREO_ENABLE(1),.OUTPUT_ENABLE(1),.SUSTAIN_ENABLE(1),.MUTE(1),.FADE(1),.ATTACK(2),.DECAY(2),.SUSTAIN(65536),.RELEASE(4)) dut(
 .clk(clk),.rst(rst),.note_valid(nv),.note_on(no),.note_id(id),.note_fcw(fcw),.note_pitch(pitch),.note_timbre(5'd0),
 .velocity_valid(1'b1),.note_velocity(7'd100),.volume_percent(7'd100),.flush(flush),.output_flush(flush),
 .note_ready(nr),.input_ready(ready),.frame_ce(frame),.underrun(u),.voice_held(held),.voice_active(active),
 .visual_sample_valid(vs),.visual_sample(visual),.effects_enable(1'b0),.effect_mode(2'd0),.effect_mask(3'b000),
 .effect_cfg_valid(1'b0),.effect_echo_wet(9'd64),.effect_echo_samples(17'd7200),.effect_room_wet(9'd64),.effect_tremolo_depth(9'd128),.effect_tremolo_rate_hz(5'd5),
 .manual_pitch_ratio(ratio),.chorus_enabled(chorus),.chorus_wet(9'd128),.chorus_depth(2'd2),.chorus_rate(2'd2));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s slot=%0d step=%0d/%0d",why,v,dut.slot_fcw,expected_step);end endtask
 task event_note(input bit on,input integer ident,word_fcw,note_pitch);begin
  @(negedge clk);nv=1;no=on;id=ident;fcw=word_fcw;pitch=note_pitch;
  while(!nr)@(negedge clk);@(negedge clk);nv=0;
 end endtask
 task frames(input integer k);repeat(k)begin @(posedge clk);while(!frame)@(posedge clk);@(negedge clk);end endtask
 always @(posedge clk)begin
  cycle++;
  if(rst||dut.engine_reset)begin reset_pending=1;for(integer k=0;k<32;k++)model_phase[k]=0;end
  else begin
   if(dut.stereo_mix_valid)begin dry_l=dut.stereo_mix_l;dry_r=dut.stereo_mix_r;end
   if(frame)last_frame=cycle;
   if(dut.dds_ce)begin
    slots++;v=dut.prepared_voice;
    expected_step=dut.frame_fcw[v*32+:32];
    if(dut.voice_ids[v*7+:7]>=60 && dut.voice_ids[v*7+:7]<=107)begin
     math_product=64'(expected_step)*64'(dut.frame_pitch_ratio);expected_step=(math_product+32768)>>16;
    end
    check(dut.slot_fcw===expected_step,"manual-only Q16 bend reference");
    expected_start=dut.slot_restart?32'd0:model_phase[v];model_phase[v]=expected_start+expected_step;
    #0.001;check(dut.phase[v*32+:32]===model_phase[v],"phase continuous through live bend");
    check(dut.raw_sample===$signed(sine[expected_start>>20]),"DDS sample matches independent phase/ROM");
   end
   if(dut.effect_valid)begin
    $fwrite(trace_fd,"%0d %0d 128 2 2 %0d %0d %0d %0d\n",reset_pending,chorus,dry_l,dry_r,dut.effect_sample,dut.effect_sample_r);reset_pending=0;
    renders++;if(cycle-last_frame>max_delivery)max_delivery=cycle-last_frame;
    check(cycle-last_frame<544,"32voice chorus delivery within existing budget");
   end
   if(vs)check((^visual)!==1'bx&&!u,"defined production output without underrun");
  end
 end
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",trace_dir))trace_dir=".";trace_fd=$fopen({trace_dir,"/chorus_chain.txt"},"w");
  $readmemh("src/rom/sine4096.hex",sine);repeat(4)@(negedge clk);rst=0;wait(ready);
  for(integer k=0;k<16;k++)event_note(1,k,23409859+k*11321,60+k);
  for(integer k=0;k<12;k++)event_note(1,96+k,23409859+k*13512,60+k);
  for(integer k=0;k<4;k++)event_note(1,60+k,23409859+k*17111,60+k);
  frames(10);check(&held,"all32 voices coexist");ratio=73562;frames(32);chorus=1;frames(1500);
  ratio=58386;frames(32);chorus=0;frames(150);ratio=65536;frames(32);
  for(integer k=0;k<16;k++)event_note(0,k,0,0);
  for(integer k=0;k<12;k++)event_note(0,96+k,0,0);
  for(integer k=0;k<4;k++)event_note(0,60+k,0,0);
  frames(40);check(held==0&&active==0,"all manual and automatic owners release");
  flush=1;repeat(5)@(negedge clk);flush=0;frames(20);check(held==0&&!u,"flush clears chorus history and ownership");
  check(max_delivery<544&&slots>50000,"production sample schedule exercised");
  $fclose(trace_fd);$display("PASS tb_performance_audio checks=%0d slots=%0d renders=%0d max_delivery=%0d",checks,slots,renders,max_delivery);$finish;
 end
 initial begin #100000000;$fatal(1,"performance audio timeout");end
endmodule
