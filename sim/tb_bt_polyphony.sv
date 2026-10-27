`timescale 1ns/1ps
// Production clock rates/frame cadence, real 32-voice synthesis and async CDC.
module tb_bt_polyphony;
 parameter integer EFFECT=0,STEREO=0;
 reg refclk=0,audio=0,rst=1,cv=0;reg [1:0] cmd=0;
 always #10 refclk=~refclk;always #8.138020833 audio=~audio;
 wire cr,done,sv,sr,av,ar,nv,nr,no,flush,frame,ready,underrun,vs;
 wire [1:0] sk,ak,play;wire [6:0] si,sp,svl,ai,ap,avl,ni,nvel,np;
 wire [2:0] nt;wire [31:0] fcw,pos;wire [4:0] addr;reg [63:0] data;
 wire [31:0] active,held;wire [15:0] keys;wire signed [15:0] pcm;
 wire busy,fault;integer checks=0,ons=0,offs=0,flushes=0,peak=0,elapsed=0;
 reg last_flush=0;reg [15:0] off_seen=0;integer first_after_pause;
 realtime cluster_start=0,worst_cluster=0,delta;
 bt_score_player #(.MAX_NOTES(32),.VOICES(16)) player(
 refclk,rst,cv,cr,cmd,done,16'd32,32'd23,addr,data,sv,sr,sk,si,sp,svl,play,pos,busy,fault);
 always @(posedge refclk)begin
  data<={16'(addr<16?3:20),8'(addr[3:0]+112),8'(addr[0]?62:60),32'(addr<16?0:3)};
  if(!rst && sv && sr)begin
   if(sk==0)off_seen[si[3:0]]<=1;
   if(sk==1 && pos==3)begin
    check(off_seen==16'hffff,"all 16 Offs precede next 16 Ons at same millisecond");
    delta=$realtime-cluster_start;
    if(delta>worst_cluster)worst_cluster=delta;
   end
  end
 end
 always @(pos)if(pos==3)cluster_start=$realtime;
 bt_event_cdc #(.WIDTH(23)) cdc(refclk,audio,rst,sv,sr,{sk,si,sp,svl},av,ar,{ak,ai,ap,avl});
 bluetooth_audio_bridge bridge(.clk(audio),.rst(rst),.frame_ce(frame),.event_valid(av),.event_ready(ar),
 .event_kind(ak),.event_id(ai),.event_pitch(ap),.event_velocity(avl),.inhibit(play!=0 || busy),
 .note_valid(nv),.note_ready(nr),.note_on(no),.note_id(ni),.note_fcw(fcw),.note_velocity(nvel),
 .flush(flush),.selected_timbre(3'd0),.note_timbre(nt),.note_pitch(np),.audio_ready(ready));
 synth_core #(.STEREO_ENABLE(STEREO),.MUTE(1),.FADE(1),.ATTACK(2),.DECAY(2),.SUSTAIN(65536),.RELEASE(3)) synth(
 .clk(audio),.rst(rst),.note_valid(nv),.note_ready(nr),.note_on(no),.note_id(ni),.note_fcw(fcw),
 .note_timbre(nt),.flush(flush),.velocity_valid(1'b1),.note_velocity(nvel),.note_pitch(np),.volume_percent(7'd100),
 .input_ready(ready),.frame_ce(frame),.voice_active(active),.voice_held(held),.underrun(underrun),
 .visual_notes(keys),.visual_sample_valid(vs),.visual_sample(pcm),
 .effects_enable(1'b1),.effect_mode(2'(EFFECT)),.effect_cfg_valid(1'b0));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task control(input [1:0] value);begin
  @(negedge refclk);cmd=value;cv=1;wait(cr);@(posedge refclk);#1;
  @(negedge refclk);cv=0;wait(done);@(negedge refclk);
 end endtask
 always @(posedge audio)if(!rst)begin
  check(!underrun,"production frame delivery has no underrun");
  if(flush && !last_flush)flushes++;
  last_flush<=flush;
  if(nv && nr)begin
   check(!flush && ni<16,"independent automatic identity reaches allocator without global flush");
   if(no)ons++;else offs++;
  end
  if(vs)begin
   check(pcm!==16'h8000 && pcm!==16'h7fff,"16-note mix retains peak headroom");
   if($signed(pcm)>peak)peak=$signed(pcm);
  end
 end
 initial begin
  #100 rst=0;wait(ready);control(0);wait(ons==16);repeat(4000)@(negedge audio);
  check($countones(held)==16,"same-pitch overlaps retain 16 independent held voices");
  check(keys==16'h0005,"automatic actual pitches reach key bitmap");
  for(integer k=0;k<16;k++)begin
   check(synth.velocities[k]>=225 && synth.velocities[k]<=256,"each identity has its own velocity");
   check(synth.automatic_pitch[k]==(k[0]?62:60),"each identity has its own pitch");
  end
  check(flushes==2,"only source takeover and explicit initial Silence clear; ordinary Ons preserve history");
  control(1);check(play==2 && held==0 && active==0,"pause silences all voices");
  check(synth.tx.latched_l==0 && synth.tx.latched_r==0,"pause confirmed after actual serial silence");
  first_after_pause=ons;control(2);wait(ons==first_after_pause+16);
  wait(pos>=4);check(ons==48 && offs==16 && !fault,"resume restores all notes and dense boundary completes");
  check(worst_cluster>0 && worst_cluster<1000000,"16 Off +16 On including CDC/synth finish within 1ms");
  check(flushes==3,"resume and dense boundary do not erase global effects");
  check(peak>0,"actual PCM carries polyphonic audio");
  control(3);check(play==0 && held==0 && active==0,"STOP clears every voice");
  repeat(4000)@(negedge audio);check(pcm==0 && keys==0,"stopped audio and visual output return to zero");
  $display("PASS tb_bt_polyphony checks=%0d effect=%0d worst_cluster_us=%0f peak=%0d",checks,EFFECT,worst_cluster/1000.0,peak);$finish;
 end
 always @(posedge refclk)if(!rst && fault)$fatal(1,"production scheduler deadline missed");
 initial begin #20000000;$fatal(1,"polyphony timeout");end
endmodule
