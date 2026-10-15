`timescale 1ns/1ps
module pt8211_tx(input wire clk,rst,fall_ce,input wire [4:0] bit_index,
    input wire [15:0] frame_l,frame_r,output reg ws,din);
    always @(posedge clk or posedge rst) begin
        if(rst) begin ws<=0;din<=0;end
        else if(fall_ce) begin
            ws<=bit_index[4];
            din<=bit_index[4] ? frame_l[15-bit_index[3:0]] : frame_r[15-bit_index[3:0]];
        end
    end
endmodule
