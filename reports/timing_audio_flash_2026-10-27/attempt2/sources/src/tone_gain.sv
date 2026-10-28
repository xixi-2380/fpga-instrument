`timescale 1ns/1ps
`include "config/synth_config.svh"
module tone_gain #(parameter integer OUTPUT_W=`DAC_W)(input wire clk,rst,in_valid,
    input wire signed [15:0] in_sample, input wire [16:0] level,
    output reg out_valid, output reg signed [OUTPUT_W-1:0] out_sample);
    localparam signed [41:0] MAX_OUT=(42'sd1 << (OUTPUT_W-1))-1;
    localparam signed [41:0] MIN_OUT=-(42'sd1 << (OUTPUT_W-1));
    wire signed [23:0] voice_q23={in_sample,8'b0};
    wire signed [17:0] level_signed=$signed({1'b0,level});
    wire signed [41:0] product=voice_q23*level_signed;
    wire signed [41:0] scaled=product >>> (16+`GAIN_SHIFT+24-OUTPUT_W);
    always @(posedge clk or posedge rst) begin
        if(rst) begin out_valid<=0; out_sample<=0; end
        else begin
            out_valid<=in_valid;
            if(in_valid) begin
                if(scaled>MAX_OUT) out_sample<=MAX_OUT[OUTPUT_W-1:0];
                else if(scaled < MIN_OUT) out_sample<=MIN_OUT[OUTPUT_W-1:0];
                else out_sample<=scaled[OUTPUT_W-1:0];
            end
        end
    end
endmodule
