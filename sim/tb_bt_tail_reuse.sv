`timescale 1ns/1ps
`include "check.svh"
// Regression for scheduler identity reuse while the old note still releases.
module tb_bt_tail_reuse;
 parameter integer STEREO=0;
 reg clk=0,rst=1,nv=0,on=0;always #8.138020833 clk=~clk;
 reg [6:0] id=0,pitch=60,velocity=127;reg [31:0] fcw=23409859;
 wire nr,ready,frame,underrun;wire [31:0] active,held;
 integer checks=0,tail_slot=-1,new_slot=-1;
 synth_core #(.STEREO_ENABLE(STEREO),.MUTE(1),.FADE(1),.ATTACK(2),.DECAY(2),.SUSTAIN(65536),.RELEASE(9600)) sound(
 .clk(clk),.rst(rst),.note_valid(nv),.note_on(on),.note_id(id),.note_fcw(fcw),
 .note_ready(nr),.input_ready(ready),.frame_ce(frame),.voice_active(active),.voice_held(held),.underrun(underrun),
 .note_timbre(3'd0),.effects_enable(1'b0),.effect_mode(2'd0),.effect_cfg_valid(1'b0),
 .flush(1'b0),.velocity_valid(1'b1),.note_velocity(velocity),.volume_percent(7'd100),.note_pitch(pitch));
 task frames(input integer n);repeat(n)begin @(posedge frame);@(negedge clk);end endtask
 task event_send(input bit is_on,input [6:0] pp,input [6:0] vv);begin
 @(negedge clk);on=is_on;pitch=pp;velocity=vv;fcw=pp==60?23409859:35075158;nv=1;
 do @(posedge clk);while(!nr);@(negedge clk);nv=0;
 end endtask
 initial begin
 #101 rst=0;wait(ready);event_send(1,60,127);frames(12);
 for(integer i=0;i<32;i++)if(held[i])tail_slot=i;
 `CHECK(tail_slot>=0,"first automatic note owns a voice")
 event_send(0,60,0);frames(3);
 `CHECK(active[tail_slot]&&!held[tail_slot],"old note is audibly releasing before ID reuse")
 event_send(1,67,32);frames(2);
 `CHECK(sound.voice_fcw[tail_slot*32+:32]==23409859,"reused scheduler identity must not retune the old release tail")
 `CHECK(sound.voice_gains[tail_slot*9+:9]==256&&sound.voice_pitches[tail_slot*7+:7]==60,"old release retains its own velocity and pitch metadata")
 for(integer i=0;i<32;i++)if(held[i])new_slot=i;
 `CHECK(new_slot!=tail_slot&&$countones(active)==2,"new onset receives a distinct voice while old tail survives")
 `CHECK(sound.voice_gains[new_slot*9+:9]==65&&sound.voice_pitches[new_slot*7+:7]==67,"new onset has its independent quiet velocity and new pitch")
 event_send(0,67,0);frames(3);
 `CHECK(held==0&&active[tail_slot]&&active[new_slot],"Off releases newest note without retriggering either tail")
 `CHECK(!underrun,"tail overlap meets production PCM deadline")
 $display("PASS tb_bt_tail_reuse checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"tail reuse timeout");end
endmodule
