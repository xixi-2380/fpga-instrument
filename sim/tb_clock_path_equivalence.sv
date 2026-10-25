`timescale 1ns/1ps
`include "check.svh"
// Compare every cycle against the unmodified b07c0d5 timing/lock models.
module tb_clock_path_equivalence;
 reg clk=0,rst=1,lock_async=0;always #5 clk=~clk;
 wire [3:0] timing_equal;wire [4:0] lock_equal,qualified;
 integer checks=0;
 for(genvar g=0;g<4;g=g+1)begin: timing_cases
  localparam integer N=g==0?1:g==1?2:g==2?3:20;
  wire b,r,f,s,br,rr,fr,sr;wire [4:0] i,ir;
  audio_timing #(.HALF_CYCLES(N)) actual(clk,rst,b,r,f,s,i);
  timing_reference #(.HALF_CYCLES(N)) reference_model(clk,rst,br,rr,fr,sr,ir);
  assign timing_equal[g]={b,r,f,s,i}==={br,rr,fr,sr,ir};
 end
 for(genvar g=0;g<5;g=g+1)begin: lock_cases
  localparam integer N=g==0?1:g==1?255:g==2?256:g==3?257:100000;
  wire q,qr;
  lock_guard #(.STABLE_CYCLES(N)) actual(clk,rst,lock_async,q);
  lock_reference #(.STABLE_CYCLES(N)) reference_model(clk,rst,lock_async,qr);
  assign lock_equal[g]=(q===qr) && (actual.count===reference_model.count);
  assign qualified[g]=q;
 end
 always @(negedge clk)begin #1;
  `CHECK(&timing_equal,"registered sampling strobe is cycle-exact for HALF_CYCLES 1,2,3,20")
  `CHECK(&lock_equal,"split/predicted lock counter and qualification are cycle-exact including byte carries")
 end
 initial begin
  #23 rst=0;lock_async=1;repeat(100020)@(negedge clk);
  `CHECK(&qualified,"all five stability intervals qualify")
  #3 lock_async=0;#1;`CHECK(qualified==0,"lock loss asserts qualification reset asynchronously")
  #3 lock_async=1;repeat(100020)@(negedge clk);
  `CHECK(&qualified,"same qualification timing after lock-loss restart")
  #3 rst=1;#1;`CHECK(qualified==0,"USR clears all lock guards")
  #4 rst=0;repeat(300)@(negedge clk);
  $display("PASS tb_clock_path_equivalence checks=%0d",checks);$finish;
 end
 initial begin #3000000;$fatal(1,"clock path equivalence timeout");end
endmodule
`timescale 1ns/1ps
`include "../src/config/synth_config.svh"
module timing_reference #(parameter integer HALF_CYCLES=`BCK_HALF_CYCLES)(
    input wire clk, rst, output reg bck, output wire rise_ce, fall_ce, frame_ce,
    output reg [4:0] bit_index);
    localparam integer CW=$clog2(HALF_CYCLES+1);
    reg [CW-1:0] count;
    assign fall_ce=!rst && count==HALF_CYCLES-1 && bck;
    assign rise_ce=!rst && count==HALF_CYCLES-1 && !bck;
    assign frame_ce=fall_ce && bit_index==0;
    always @(posedge clk or posedge rst) begin
        if(rst) begin count<=0; bck<=1; bit_index<=0; end
        else if(count==HALF_CYCLES-1) begin
            count<=0; bck<=~bck;
            if(!bck) bit_index<=bit_index+1'b1;
        end else count<=count+1'b1;
    end
endmodule
`timescale 1ns/1ps
`include "../src/config/synth_config.svh"
module lock_reference #(parameter integer STABLE_CYCLES=`LOCK_CYCLES)(
    input wire clk, rst, lock_async, output reg qualified);
    localparam integer CW=$clog2(STABLE_CYCLES+1);
    wire arst=rst | ~lock_async;
    (* syn_preserve=1, syn_async_reg=1 *) reg [1:0] lock_sync;
    reg [CW-1:0] count;
    always @(posedge clk or posedge arst) begin
        if(arst) begin lock_sync<=0; count<=0; qualified<=0; end
        else begin
            lock_sync<={lock_sync[0],1'b1};
            if(!lock_sync[1]) begin count<=0; qualified<=0; end
            else if(!qualified) begin
                if(count==STABLE_CYCLES-1) qualified<=1;
                else count<=count+1'b1;
            end
        end
    end
endmodule
