`timescale 1ns/1ps
module tb_sustain_carry_equivalence;
 reg clk=0,rst=1,sample_ce=0,note_on=0,note_off=0,enabled=1,base_active=1;
 reg [16:0] base_level=0,duration=96000,phase_step=174,phase_remainder=73216;
 reg [8:0] strength=256;
 wire [16:0] level_new,level_old;wire active_new,active_old;
 sustain_envelope #(.PRECALC(1)) dut(clk,rst,sample_ce,note_on,note_off,enabled,base_level,base_active,duration,phase_step,phase_remainder,strength,level_new,active_new);
 sustain_envelope_baseline ref_dut(clk,rst,sample_ce,note_on,note_off,enabled,base_level,base_active,duration,phase_step,phase_remainder,strength,level_old,active_old);
 always #5 clk=~clk;
 integer cycles=0,checks=0,seed=32'h2380cafe,random_word;
 task check_state;
  begin
   checks=checks+1;
   if({level_new,active_new,dut.owned,dut.running,dut.held_age,dut.remaining,dut.total,dut.step_size,dut.remainder,dut.error,dut.phase,dut.peak,dut.current} !==
      {level_old,active_old,ref_dut.owned,ref_dut.running,ref_dut.held_age,ref_dut.remaining,ref_dut.total,ref_dut.step_size,ref_dut.remainder,ref_dut.error,ref_dut.phase,ref_dut.peak,ref_dut.current})
    $fatal(1,"equivalence mismatch cycle=%0d ce=%b on=%b off=%b enable=%b current old/new=%0d/%0d target=%0d",cycles,sample_ce,note_on,note_off,enabled,ref_dut.current,dut.current,dut.target);
  end
 endtask
 always @(posedge clk)begin #1;check_state();end
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(cycles=0;cycles<250000;cycles=cycles+1)begin
   @(negedge clk);
   random_word=$random(seed);sample_ce=(cycles%2)==0 && (random_word&3)!=0;
   note_on=(random_word&255)==5;note_off=(random_word&127)==7;
   // Frequent short tails and long uninterrupted tails both occur.
   if((random_word&31)==3)enabled=~enabled;
   if((random_word&63)==9)begin
    base_level=$random(seed);base_active=$random(seed);
    strength=$random(seed);
   end
   if((random_word&127)==11)begin
    duration=1+($unsigned($random(seed))%96000);
    phase_step=16777216/duration;phase_remainder=16777216%duration;
   end
   if(cycles%10007==10006)rst=1;
   else if(cycles%10007==0)rst=0;
  end
  @(negedge clk);rst=0;sample_ce=0;enabled=1;note_on=1;note_off=0;
  @(negedge clk);sample_ce=1;
  @(negedge clk);sample_ce=0;note_on=0;base_level=65536;strength=256;duration=96000;phase_step=174;phase_remainder=73216;note_off=1;
  @(negedge clk);sample_ce=1;
  @(negedge clk);sample_ce=0;note_off=0;base_level=0;base_active=0;
  repeat(96005)begin @(negedge clk);sample_ce=1;@(negedge clk);sample_ce=0;end
  $display("PASS tb_sustain_carry_equivalence cycles=%0d checks=%0d",cycles+96008,checks);$finish;
 end
 initial begin #6000000;$fatal(1,"equivalence timeout");end
endmodule
