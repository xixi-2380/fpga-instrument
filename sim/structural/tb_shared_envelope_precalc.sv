`timescale 1ns/1ps
module tb_shared_envelope_precalc;
 parameter integer VOICES=32,ATTACK=480,DECAY=4800,RELEASE=9600,INTERVAL=40,FRAMES=5000;
 localparam integer MAX_AD=ATTACK>DECAY?ATTACK:DECAY,MAX_N=MAX_AD>RELEASE?MAX_AD:RELEASE,CW=MAX_N>0?$clog2(MAX_N+1):1;
 reg clk=0,rst=1,ce=0;always #5 clk=~clk;
 reg [VOICES-1:0] on_event=0,off_event=0,restart=0;
 reg [5*VOICES-1:0] timbres=0;
 wire [17*VOICES-1:0] seeds,levels,aq,rq;
 wire [CW*VOICES-1:0] ar,rr;
 integer checks=0,frames=0,cycle=0,seed=32'h2380abcd,random_value;
 envelope_precalc_bank #(.VOICES(VOICES),.ATTACK(ATTACK),.DECAY(DECAY),.RELEASE(RELEASE)) bank(clk,rst,ce,seeds,levels,aq,rq,ar,rr);
 for(genvar v=0;v<VOICES;v=v+1)begin: voices
  wire [16:0] new_level,old_level;wire new_active,old_active;
  instrument_envelope #(.ATTACK(ATTACK),.DECAY(DECAY),.RELEASE(RELEASE),.PRECALC(1),.EXTERNAL_PRECALC(1)) dut(
   .clk(clk),.rst(rst),.sample_ce(ce),.note_on(on_event[v]),.note_off(off_event[v]),.restart(restart[v]),.timbre(timbres[v*5+:5]),.level(new_level),.active(new_active),
   .prepare_seed(seeds[v*17+:17]),.prepare_release(levels[v*17+:17]),.prepared_attack_q(aq[v*17+:17]),.prepared_attack_r(ar[v*CW+:CW]),.prepared_release_q(rq[v*17+:17]),.prepared_release_r(rr[v*CW+:CW]));
  instrument_envelope_baseline #(.ATTACK(ATTACK),.DECAY(DECAY),.RELEASE(RELEASE),.PRECALC(1)) ref_dut(
   .clk(clk),.rst(rst),.sample_ce(ce),.note_on(on_event[v]),.note_off(off_event[v]),.restart(restart[v]),.timbre(timbres[v*5+:5]),.level(old_level),.active(old_active));
  always @(posedge clk)begin
   #0.001;
   if({new_level,new_active,dut.profile,dut.state,dut.drum_age,dut.musical_level,dut.release_step,
     dut.legacy.state,dut.legacy.remaining,dut.legacy.length,dut.legacy.remainder,dut.legacy.error,dut.legacy.base,dut.legacy.level} !==
      {old_level,old_active,ref_dut.profile,ref_dut.state,ref_dut.drum_age,ref_dut.musical_level,ref_dut.release_step,
     ref_dut.legacy.state,ref_dut.legacy.remaining,ref_dut.legacy.length,ref_dut.legacy.remainder,ref_dut.legacy.error,ref_dut.legacy.base,ref_dut.legacy.level})
    begin
     $display("level=%0d/%0d state=%0d/%0d rem=%0d/%0d len=%0d/%0d remainder=%0d/%0d error=%0d/%0d base=%0d/%0d profile=%0d/%0d on/off/restart=%b%b%b",dut.legacy.level,ref_dut.legacy.level,dut.legacy.state,ref_dut.legacy.state,dut.legacy.remaining,ref_dut.legacy.remaining,dut.legacy.length,ref_dut.legacy.length,dut.legacy.remainder,ref_dut.legacy.remainder,dut.legacy.error,ref_dut.legacy.error,dut.legacy.base,ref_dut.legacy.base,dut.profile,ref_dut.profile,on_event[v],off_event[v],restart[v]);
     $fatal(1,"Mismatch voice=%0d cycle=%0d frame=%0d ce=%b aq=%0d/%0d ar=%0d/%0d rq=%0d/%0d rr=%0d/%0d",v,cycle,frames,ce,aq[v*17+:17],ref_dut.legacy.attack_q,ar[v*CW+:CW],ref_dut.legacy.attack_r,rq[v*17+:17],ref_dut.legacy.release_q,rr[v*CW+:CW],ref_dut.legacy.release_r);
    end
  end
 end
 task tick;
  begin @(posedge clk);#0.002;checks=checks+VOICES;cycle=cycle+1;@(negedge clk);end
 endtask
 task release_reset(input integer first_delay);
  begin rst=1;ce=0;on_event=0;off_event=0;restart=0;repeat(3)tick;rst=0;repeat(first_delay)tick;
   ce=1;on_event={VOICES{1'b1}};timbres=0;tick;ce=0;on_event=0;
   repeat(INTERVAL-1)tick;
  end
 endtask
 initial begin
  #1;
  for(integer d=0;d<5;d=d+1)begin release_reset(d);ce=1;tick;ce=0;repeat(INTERVAL-1)tick;end
  for(integer f=0;f<FRAMES;f=f+1)begin
   frames=f;ce=1;
   for(integer v=0;v<VOICES;v=v+1)begin
    random_value=$random(seed);on_event[v]=(random_value&31)==0;off_event[v]=(random_value&63)==1;restart[v]=(random_value&128)!=0;
    if(on_event[v])timbres[v*5+:5]=(random_value>>8)&31;
   end
   tick;ce=0;on_event=0;off_event=0;restart=0;
   repeat(INTERVAL-1)tick;
   if(f%127==126)release_reset(f%5);
  end
  $display("PASS tb_shared_envelope_precalc voices=%0d interval=%0d frames=%0d checks=%0d",VOICES,INTERVAL,FRAMES,checks);$finish;
 end
 initial begin #1000000000;$fatal(1,"timeout");end
endmodule
