`timescale 1ns/1ps
`include "check.svh"
`include "../src/config/synth_config.svh"
// Component integration: production beat/ADSR frame counts, accelerated CE
// spacing. This does not substitute for production-clock serial timing/STA.
module tb_score_articulation;
 localparam integer V=4;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [5:0] subcycle=0;
 always @(posedge clk)if(rst)subcycle<=0;else subcycle<=subcycle+1'b1;
 wire ce=subcycle==63;
 wire valid,on,ready,busy,done,error;
 wire [6:0] id;wire [31:0] fcw;wire [1:0] timbre;
 wire [V-1:0] start,stop,restart,held,active;
 wire [V*32-1:0] frequencies,phases;wire [V*7-1:0] identities;
 wire [V*3-1:0] timbres;wire [16:0] level[0:V-1];
 integer checks=0,frames=0,starts=0,accepted=0,first_slot=-1,new_slot=-1,change_frame=0;
 reg [V*32-1:0] frame_fcw=0;reg [V-1:0] frame_restart=0;
 wire dds_ce=subcycle>=16 && subcycle<20;
 wire [1:0] slot=subcycle[1:0];wire signed [15:0] raw;wire raw_valid;
 reg [31:0] expected_phase[0:V-1];reg [31:0] selected_phase;
 integer expected_sample=0,expected_slot=0,sample_count=0;
 real sample_value;
 score_player #(.BEAT_FRAMES(24000),.TAIL_FRAMES(9604)) source(
  clk,rst,1'b1,ce,ready,valid,on,id,fcw,timbre,busy,done,error);
 voice_allocator #(.VOICES(V)) allocator(
  clk,rst,subcycle>=32,ce,valid,on,id,fcw,active,ready,start,stop,restart,held,
  frequencies,identities,timbre,timbres);
 for(genvar v=0;v<V;v=v+1)begin: envelopes
  adsr_envelope envelope(clk,rst,ce,start[v],stop[v],level[v],active[v],restart[v],1'b0,17'd0);
 end
 dds_sine #(.VOICES(V)) dds(clk,rst,dds_ce,frame_fcw[slot*32+:32],raw,raw_valid,
  phases,frame_restart[slot],slot,2'b0);
 initial for(integer v=0;v<V;v=v+1)expected_phase[v]=0;
 always @(posedge clk)if(!rst)begin
  `CHECK(!error,"default score file remains valid")
  if(valid && ready)begin
   accepted=accepted+1;
   `CHECK(timbre==0,"production articulation uses keyboard sine preset")
  end
  if(raw_valid)begin
   `CHECK($signed(raw)==expected_sample,"DDS sample matches independent sine mathematics")
   `CHECK(phases[expected_slot*32+:32]==expected_phase[expected_slot],"each phase context advances independently")
   sample_count=sample_count+1;
  end
  if(dds_ce)begin
   selected_phase=frame_restart[slot]?0:expected_phase[slot];
   sample_value=$sin(6.283185307179586*selected_phase[31:20]/4096.0)*32767.0;
   expected_sample=sample_value>=0?$rtoi(sample_value+0.5):$rtoi(sample_value-0.5);
   expected_phase[slot]=selected_phase+frame_fcw[slot*32+:32];expected_slot=slot;
  end
  if(ce)begin
   frames=frames+1;frame_fcw<=frequencies;frame_restart<=restart;
   `CHECK($countones(held)<=1,"single melody never holds an accompaniment chord")
   for(integer v=0;v<V;v=v+1)if(start[v])begin
    if(starts==0)begin
     first_slot=v;
     `CHECK(identities[v*7+:7]==60 && restart[v] && level[v]==0,"first C4 attacks from zero")
    end else if(starts==1)begin
     `CHECK(v==first_slot && !restart[v] && identities[v*7+:7]==60,"repeated C4 preserves keyboard retrigger semantics")
     `CHECK(level[v]>16000 && level[v]<18000,"production release leaves expected level at 125ms retrigger")
    end else if(starts==2)begin
     new_slot=v;change_frame=frames;
     `CHECK(v!=first_slot && identities[v*7+:7]==67 && restart[v] && level[v]==0,"G4 receives a new voice and zero-level attack")
     `CHECK(active[first_slot] && !held[first_slot] && level[first_slot]>16000 && level[first_slot]<18000,
       "old C4 tail remains audible independently when G4 starts")
     `CHECK(frequencies[first_slot*32+:32]==32'h016534c3,"old tail keeps C4 pitch instead of jumping to G4")
    end
    starts=starts+1;
   end
   if(starts==3 && frames-change_frame==10000)begin
    `CHECK(accepted==5 && !active[first_slot] && level[first_slot]==0,"old C4 tail naturally reaches zero")
    `CHECK(held[new_slot] && active[new_slot] && level[new_slot]==`ADSR_SUSTAIN_LEVEL,"G4 finishes production attack and decay normally")
    `CHECK(sample_count>200000,"production frame sequence includes sustained independent DDS samples")
    $display("ARTICULATION_METRICS frames=%0d first_slot=%0d new_slot=%0d samples=%0d",frames,first_slot,new_slot,sample_count);
    $display("PASS tb_score_articulation checks=%0d",checks);$finish;
   end
  end
 end
 initial begin #12 rst=0;end
 initial begin #50000000;$fatal(1,"production articulation timeout");end
endmodule
