`timescale 1ns/1ps
`include "config/synth_config.svh"
module clock_reset #(parameter integer LOCK_N=`LOCK_CYCLES)(
    input wire ref_clk,external_reset,lock1,lock2,
    input wire audio_clk,output wire pll1_reset,pll2_reset,audio_reset);
    reg [5:0] por_count=0;
    wire por=~por_count[5];
    always @(posedge ref_clk) if(por) por_count<=por_count+1'b1;
    wire ref_reset;
    wire good1,good2;
    reset_sync ref_sync(ref_clk,external_reset|por,ref_reset);
    assign pll1_reset=ref_reset;
    lock_guard #(.STABLE_CYCLES(LOCK_N)) g1(ref_clk,ref_reset,lock1,good1);
    assign pll2_reset=ref_reset|!good1;
    lock_guard #(.STABLE_CYCLES(LOCK_N)) g2(ref_clk,pll2_reset,lock2,good2);
    reset_sync audio_sync(audio_clk,
        ref_reset|!good1|!good2|!lock1|!lock2,audio_reset);
endmodule
