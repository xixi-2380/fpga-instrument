`timescale 1ns/1ps
`include "synth_config.svh"
module startup_envelope #(parameter integer MUTE=`MUTE_FRAMES, FADE=`FADE_FRAMES)(
    input wire clk,rst,frame_ce,output reg pa_enable,output reg [16:0] level);
    localparam integer MW=$clog2(MUTE+1), FW=$clog2(FADE+1);
    reg [MW-1:0] mute_count;
    reg [FW-1:0] fade_count;
    wire [31:0] next_level=((fade_count+32'd1)*32'd65536)/FADE;
    always @(posedge clk or posedge rst) begin
        if(rst) begin mute_count<=0; fade_count<=0; pa_enable<=0; level<=0; end
        else if(frame_ce) begin
            if(!pa_enable) begin
                // The first boundary STARTS frame zero; MUTE complete frames
                // have elapsed only at boundary MUTE (not MUTE-1).
                if(mute_count==MUTE) pa_enable<=1;
                else mute_count<=mute_count+1'b1;
            end else if(fade_count<FADE) begin
                fade_count<=fade_count+1'b1;
                level<=next_level[16:0];
            end
        end
    end
endmodule
