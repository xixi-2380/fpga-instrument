`timescale 1ns/1ps
`include "config/synth_config.svh"
// Registered serial accumulation. The final conversion includes this cycle's
// last voice, avoiding both a long combinational adder chain and stale sums.
module voice_mixer(
    input wire clk,rst,in_valid,input wire signed [`VOICE_W-1:0] voice_sample,
    input wire first,last,output reg out_valid,
    output reg signed [`DAC_W-1:0] sample);
    reg signed [`MIX_W-1:0] accumulator;
    wire signed [`MIX_W-1:0] extended_sample={{(`MIX_W-`VOICE_W){voice_sample[`VOICE_W-1]}},voice_sample};
    wire signed [`MIX_W-1:0] total=(first?{`MIX_W{1'b0}}:accumulator)+extended_sample;
    wire signed [`MIX_W-1:0] scaled=total >>> (`VOICE_W-`DAC_W);
    always @(posedge clk or posedge rst)begin
        if(rst)begin accumulator<=0;out_valid<=0;sample<=0;end
        else begin
            out_valid<=in_valid && last;
            if(in_valid)begin
                accumulator<=total;
                if(last)begin
                    if(scaled>32767)sample<=16'sh7fff;
                    else if(scaled < -32768)sample<=16'sh8000;
                    else sample<=scaled[`DAC_W-1:0];
                end
            end
        end
    end
endmodule
