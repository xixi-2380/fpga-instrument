`timescale 1ns/1ps
`include "config/synth_config.svh"
// Sum signed Q1.23 voices in 40 bits; truncate and saturate only after mixing.
module voice_mixer #(parameter integer VOICES=4)(
    input wire clk,rst,in_valid,input wire [VOICES*`VOICE_W-1:0] samples,
    output reg out_valid,output reg signed [`DAC_W-1:0] sample);
    wire signed [`MIX_W-1:0] partial [0:VOICES];
    assign partial[0]=0;
    for(genvar i=0;i<VOICES;i=i+1)begin: sum_voices
        assign partial[i+1]=partial[i]+$signed({{(`MIX_W-`VOICE_W){samples[i*`VOICE_W+`VOICE_W-1]}},samples[i*`VOICE_W+:`VOICE_W]});
    end
    wire signed [`MIX_W-1:0] total=partial[VOICES];
    wire signed [`MIX_W-1:0] scaled=total >>> (`VOICE_W-`DAC_W);
    always @(posedge clk or posedge rst)begin
        if(rst)begin out_valid<=0;sample<=0;end
        else begin
            out_valid<=in_valid;
            if(in_valid)begin
                if(scaled>32767)sample<=16'sh7fff;
                else if(scaled < -32768)sample<=16'sh8000;
                else sample<=scaled[`DAC_W-1:0];
            end
        end
    end
endmodule
