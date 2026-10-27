`timescale 1ns/1ps
`include "check.svh"
// Independent per-voice fixed-point/phase/mix scoreboard, then reference
// effect/volume instances for channel isolation, and an external-pin I2S sink.
module tb_stereo_audio;
 reg clk=0,rst=1,nv=0,no=0,flush=0,fx=0,cfg=0;
 always #8.138020833 clk=~clk;
 reg [6:0] id=0,pitch=60,vel=127,volume=100;reg [2:0] timbre=0;reg [1:0] mode=0;
 reg [31:0] fcw=23409859;
 wire nr,ready,bck,ws,din,frame,u,vs;wire signed [15:0] visual;
 wire [31:0] held,active;wire er=rst||flush;
 integer checks=0,frames_count=0,terms=0,mixes=0,serial_words=0,different=0,peak=0,steals=0,mute_samples=0,cycles=0,last_boundary=0,max_delivery=0;
 reg [15:0] rom[0:28671];
 reg [31:0] phases[0:31],expected_fcw[0:31];
 integer expected_gain[0:31],expected_pitch[0:31],expected_timbre[0:31];
 reg signed [63:0] term[0:31],level_calc,sum_l,sum_r,tmp,left_term,right_term;
 reg [31:0] phase_use;integer addr,romv;reg [31:0] restarted;
 reg signed [15:0] dry_l=0,dry_r=0;
 wire refv_l,refv_r,refov_l,refov_r;
 wire signed [15:0] ref_fx_l,ref_fx_r,ref_out_l,ref_out_r;
 wire unused_ready_l,unused_ready_r;
 reg pending_valid=0;reg [15:0] pending_l=0,pending_r=0,current_l=0,current_r=0;
 reg rx_synced=0,previous_ws=1;integer bitn=0,ch=0,word=0;reg [15:0] pair_l,pair_r;
 synth_core #(.OUTPUT_ENABLE(0),.STEREO_ENABLE(1),.MUTE(1),.FADE(1),.ATTACK(4),.DECAY(4),.SUSTAIN(65536),.RELEASE(40),
 .DELAY_SAMPLES(17),.ROOM_D0(3),.ROOM_D1(5),.ROOM_D2(7),.ROOM_D3(11)) sound(
 .clk(clk),.rst(rst),.note_valid(nv),.note_on(no),.note_id(id),.note_fcw(fcw),.note_pitch(pitch),
 .note_timbre(timbre),.velocity_valid(1'b1),.note_velocity(vel),.volume_percent(volume),.flush(flush),
 .note_ready(nr),.input_ready(ready),.bck(bck),.ws(ws),.din(din),.frame_ce(frame),.underrun(u),
 .voice_held(held),.voice_active(active),.visual_sample_valid(vs),.visual_sample(visual),
 .effects_enable(fx),.effect_mode(mode),.effect_cfg_valid(cfg),.effect_echo_wet(9'd128),
 .effect_room_wet(9'd96),.effect_tremolo_depth(9'd192),.effect_tremolo_rate_hz(4'd7));
 // Reference inputs are mathematical sums, not DUT samples; effect algorithms
 // themselves retain the separately verified existing implementation.
 audio_effects #(.DELAY_SAMPLES(17),.D0(3),.D1(5),.D2(7),.D3(11)) ref_left(
 .clk(clk),.rst(er),.enable(fx),.mode(mode),.in_valid(sound.mix_valid),.in_sample(dry_l),
 .in_ready(unused_ready_l),.out_valid(refv_l),.out_sample(ref_fx_l),.cfg_valid(cfg),
 .cfg_echo_wet(9'd128),.cfg_room_wet(9'd96),.cfg_tremolo_depth(9'd192),.cfg_tremolo_rate_hz(4'd7));
 audio_effects #(.DELAY_SAMPLES(17),.D0(3),.D1(5),.D2(7),.D3(11)) ref_right(
 .clk(clk),.rst(er),.enable(fx),.mode(mode),.in_valid(sound.mix_valid),.in_sample(dry_r),
 .in_ready(unused_ready_r),.out_valid(refv_r),.out_sample(ref_fx_r),.cfg_valid(cfg),
 .cfg_echo_wet(9'd128),.cfg_room_wet(9'd96),.cfg_tremolo_depth(9'd192),.cfg_tremolo_rate_hz(4'd7));
 master_volume ref_volume_l(clk,rst,refv_l,ref_fx_l,volume,refov_l,ref_out_l);
 master_volume ref_volume_r(clk,rst,refv_r,ref_fx_r,volume,refov_r,ref_out_r);
 function automatic signed [15:0] sat(input signed [63:0] value);
 if(value>32767)sat=32767;else if(value < -32768)sat=-32768;else sat=value[15:0];endfunction
 task more(input integer n);integer target;begin target=frames_count+n;wait(frames_count>=target);@(negedge clk);end endtask
 task send(input bit is_on,input integer ident,pp,vv,tt);begin
 @(negedge clk);nv=1;no=is_on;id=ident;pitch=pp;vel=vv;timbre=tt;
 // Exact reproducible phase step, intentionally independent of MIDI conversion.
 fcw=(pp-40)*1357911;
 do @(posedge clk);while(!nr);@(negedge clk);nv=0;
 end endtask
 always @(posedge er)begin
 for(integer k=0;k<32;k++)begin phases[k]=0;expected_fcw[k]=0;expected_gain[k]=256;expected_pitch[k]=0;expected_timbre[k]=0;end
 terms=0;mixes=0;pending_valid=0;pending_l=0;pending_r=0;
 end
 always @(posedge rst)begin
 current_l=0;current_r=0;rx_synced=0;previous_ws=1;bitn=0;ch=0;word=0;
 end
 always @(posedge clk)begin
 cycles++;
 if(!er)begin
 `CHECK(!u,"stereo channels never underrun")
 if(nv&&nr&&no)begin
 if(active[sound.allocator.target])steals++;
 expected_fcw[sound.allocator.target]=fcw;
 expected_gain[sound.allocator.target]=(vel*256+63)/127;
 expected_pitch[sound.allocator.target]=pitch;
 expected_timbre[sound.allocator.target]=timbre;
 end
 if(sound.gain_valid)begin
 `CHECK(sound.sample_voice==terms,"all physical voice slots render in order")
 `CHECK($signed(sound.gain_sample)==term[terms],"voice sample matches independent signed arithmetic")
 terms++;
 end
 if(sound.mix_valid)begin
 `CHECK(terms==32&&mixes==0,"one complete 32-voice mix per frame")
 `CHECK($signed(sound.stereo_mix_l)==dry_l&&$signed(sound.stereo_mix_r)==dry_r,"both dry channels match independent weighted sums")
 mixes++;
 end
 `CHECK(sound.output_valid===refov_l&&sound.output_valid_r===refov_r,"both PCM valid pipelines agree with reference")
 if(sound.output_valid)begin
 `CHECK(cycles-last_boundary<=544,"both post-effect stereo samples meet original production render budget")
 if(cycles-last_boundary>max_delivery)max_delivery=cycles-last_boundary;
 `CHECK(sound.output_sample===ref_out_l&&sound.output_sample_r===ref_out_r,"left and right effects/volume never cross-contaminate")
 `CHECK(vs&&visual==($signed({ref_out_l[15],ref_out_l})+$signed({ref_out_r[15],ref_out_r}))>>>1,"display is signed stereo average")
 if(ref_out_l!=ref_out_r)different++;
 if($signed(ref_out_l)>peak)peak=$signed(ref_out_l);
 if(volume==0)mute_samples++;else mute_samples=0;
 if(mute_samples>258)
 `CHECK(ref_out_l==0&&ref_out_r==0,"both channels reach exact digital mute")
 end
 end
 // Model frame queue independently, consume old pair before a simultaneous fill.
 if(!rst&&frame)begin
 frames_count++;last_boundary=cycles;current_l=pending_valid?pending_l:0;current_r=pending_valid?pending_r:0;pending_valid=0;
 end
 if(!er&&refov_l)begin pending_valid=1;pending_l=ref_out_l;pending_r=ref_out_r;end
 if(!er&&frame)begin
 for(integer k=0;k<32;k++)begin
 phase_use=sound.voice_restart[k]?0:phases[k];phases[k]=phase_use+expected_fcw[k];
 addr=phase_use[31:20];romv=$signed(rom[expected_timbre[k]*4096+addr]);
 term[k]=romv;
 end
 #0.001;
 sum_l=0;sum_r=0;terms=0;mixes=0;
 for(integer k=0;k<32;k++)begin
 `CHECK(sound.voice_gains[k*9+:9]==expected_gain[k]&&sound.voice_pitches[k*7+:7]==expected_pitch[k],"per-physical-voice expression metadata survives source ID reuse")
 level_calc=sound.voice_level[k];level_calc=(level_calc*sound.startup_level)>>>16;
 level_calc=(level_calc*expected_gain[k])>>>8;
 term[k]=(term[k]*level_calc)>>>13;
 if(expected_pitch[k]<60)begin left_term=term[k]-(term[k]>>>2);right_term=term[k]>>>2;end
 else if(expected_pitch[k]<66)begin left_term=term[k];right_term=term[k]>>>1;end
 else if(expected_pitch[k]<72)begin left_term=term[k]>>>1;right_term=term[k];end
 else begin left_term=term[k]>>>2;right_term=term[k]-(term[k]>>>2);end
 sum_l+=left_term;sum_r+=right_term;
 end
 dry_l=sat(sum_l>>>8);dry_r=sat(sum_r>>>8);
 end
 end
 always @(posedge bck)if(!rst)begin
 if(rx_synced)begin
 if(bitn==0&&ch==0)begin pair_l=current_l;pair_r=current_r;end
 word=((word<<1)|din)&65535;
 if(bitn==15)begin
 `CHECK(ws!=previous_ws&&ws!=ch,"standard I2S boundary completes old channel LSB")
 `CHECK(word==(ch==0?pair_l:pair_r),"external-pin I2S word matches complete expected stereo pair")
 serial_words++;ch=ws;word=0;bitn=0;
 end else begin `CHECK(ws==previous_ws,"I2S has sixteen data bits per word") bitn++;end
 end else if(ws!=previous_ws)begin rx_synced=1;ch=ws;bitn=0;word=0;end
 previous_ws=ws;
 end
 initial begin
 for(integer k=0;k<32;k++)begin phases[k]=0;expected_fcw[k]=0;expected_gain[k]=256;expected_pitch[k]=0;expected_timbre[k]=0;end
 $readmemh("src/rom/sine4096.hex",rom,0,4095);$readmemh("src/rom/flute4096.hex",rom,4096,8191);
 $readmemh("src/rom/reed4096.hex",rom,8192,12287);$readmemh("src/rom/cello4096.hex",rom,12288,16383);
 $readmemh("src/rom/piano4096.hex",rom,16384,20479);$readmemh("src/rom/guitar4096.hex",rom,20480,24575);
 $readmemh("src/rom/vibraphone4096.hex",rom,24576,28671);
 #101 rst=0;wait(ready);
 for(integer k=0;k<16;k++)send(1,k,48+2*k,32+6*k,k%7);
 more(50);`CHECK($countones(held)==16,"sixteen notes including repeated timbres play concurrently")
 for(integer k=0;k<16;k++)send(0,k,48+2*k,0,0);
 for(integer k=0;k<16;k++)send(1,k,79-2*k,127-5*k,(k+3)%7);
 more(10);`CHECK($countones(held)==16&&$countones(active)>16,"reused source IDs overlap release tails without retuning")
 fx=1;cfg=1;@(negedge clk);cfg=0;
 for(integer e=0;e<3;e++)begin mode=e;more(530);end
 volume=0;more(270);`CHECK(sound.output_sample==0&&sound.output_sample_r==0,"screen volume mutes both speakers")
 volume=100;more(270);`CHECK(different>100&&peak>0,"both independent stereo data and audible-range samples exist")
 @(negedge clk);flush=1;more(3);@(negedge clk);flush=0;more(5);
 `CHECK(held==0&&active==0&&sound.tx.latched_l==0&&sound.tx.latched_r==0,"Silence clears all stereo effect histories and serial samples")
 for(integer k=0;k<16;k++)send(1,k,60+k,127,0);
 more(10);@(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;wait(ready);more(6);
 `CHECK(sound.output_sample==0&&sound.output_sample_r==0&&!u,"mid-stream reset recovers to exact stereo silence")
 `CHECK(serial_words>4000,"external I2S receiver observed sustained stereo output")
 $display("PASS tb_stereo_audio checks=%0d frames=%0d serial_words=%0d differing_pairs=%0d max_delivery=%0d",checks,frames_count,serial_words,different,max_delivery);$finish;
 end
 initial begin #100000000;$fatal(1,"stereo audio timeout frames=%0d",frames_count);end
endmodule
