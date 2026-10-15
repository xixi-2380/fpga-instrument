`timescale 1ns/1ps
`include "config/synth_config.svh"
module audio_timing #(parameter integer HALF_CYCLES=`BCK_HALF_CYCLES)(
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
