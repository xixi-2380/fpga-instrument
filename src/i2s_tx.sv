`timescale 1ns/1ps
// MAX98357A: standard I2S, 16 bits/channel, LRCLK low=left. Data changes on
// falling BCLK and is sampled on rising BCLK. A WS transition precedes the new
// MSB by one bit; the boundary bit is the PREVIOUS channel's LSB, not padding.
module i2s_tx(input wire clk,rst,fall_ce,input wire [4:0] bit_index,
    input wire [15:0] frame_l,frame_r,output reg ws,din);
    reg [15:0] latched_l,latched_r;
    always @(posedge clk or posedge rst)begin
        if(rst)begin ws<=1;din<=0;latched_l<=0;latched_r<=0;end
        else if(fall_ce)begin
            ws<=bit_index[4];
            if(bit_index==0)begin
                // Atomically take the new pair, while finishing the old right
                // word. frame_buffer supplies its old pending pair at this CE.
                latched_l<=frame_l;latched_r<=frame_r;din<=latched_r[0];
            end else if(bit_index<=16)din<=latched_l[16-bit_index];
            else din<=latched_r[32-bit_index];
        end
    end
endmodule
