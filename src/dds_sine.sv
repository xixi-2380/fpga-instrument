`timescale 1ns/1ps
`include "config/synth_config.svh"
module dds_sine(input wire clk,rst,sample_ce,
    input wire [`PHASE_W-1:0] fcw,
    output wire signed [`ROM_DATA_W-1:0] sample, output reg valid,
    output reg [`PHASE_W-1:0] phase,input wire restart);
    wire [`PHASE_W-1:0] sample_phase=restart?{`PHASE_W{1'b0}}:phase;
    sine_rom rom(.clk(clk),.ce(sample_ce && !rst),
        .addr(sample_phase[`PHASE_W-1 -: `ROM_ADDR_W]),.q(sample));
    always @(posedge clk or posedge rst) begin
        if(rst) begin phase<=0; valid<=0; end
        else begin valid<=sample_ce; if(sample_ce) phase<=sample_phase+fcw; end
    end
endmodule
