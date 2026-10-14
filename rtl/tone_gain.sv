`timescale 1ns/1ps
`include "synth_config.svh"
module tone_gain(input wire clk,rst,in_valid,
    input wire signed [15:0] in_sample, input wire [16:0] level,
    output reg out_valid, output reg signed [15:0] out_sample);
    wire signed [23:0] voice_q23={in_sample,8'b0};
    wire signed [17:0] level_signed=$signed({1'b0,level});
    wire signed [41:0] product=voice_q23*level_signed;
    wire signed [41:0] scaled=product >>> (16+`GAIN_SHIFT+8);
    always @(posedge clk or posedge rst) begin
        if(rst) begin out_valid<=0; out_sample<=0; end
        else begin
            out_valid<=in_valid;
            if(in_valid) begin
                if(scaled>42'sd32767) out_sample<=16'sh7fff;
                else if(scaled < -42'sd32768) out_sample<=16'sh8000;
                else out_sample<=scaled[15:0];
            end
        end
    end
endmodule
