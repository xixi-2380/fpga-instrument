`timescale 1ns/1ps
`include "config/synth_config.svh"
module audio_timing #(parameter integer HALF_CYCLES=`BCK_HALF_CYCLES)(
    input wire clk, rst, output reg bck, output wire rise_ce, fall_ce,frame_ce,
    output reg [4:0] bit_index,output wire frame_pre_ce);
    localparam integer CW=$clog2(HALF_CYCLES+1);
    reg [CW-1:0] count;
    reg frame_boundary;
    // With HALF_CYCLES>1 the boundary FF is already asynchronously zero in
    // reset. Do not add the high-fanout reset into its otherwise registered CE.
    // HALF_CYCLES=1 retains the legacy first-edge special case exactly.
    assign frame_ce=HALF_CYCLES==1 ? (!rst && frame_boundary) : frame_boundary;
    assign fall_ce=!rst && count==HALF_CYCLES-1 && bck;
    assign rise_ce=!rst && count==HALF_CYCLES-1 && !bck;
    assign frame_pre_ce=HALF_CYCLES==1 ? (!bck && bit_index==31) :
        (count==HALF_CYCLES-2 && bck && bit_index==0);
    // Predict the same boundary one clock ahead so the high-fanout envelope
    // CE is a register output, not counter/decode logic in every ADSR path.
    always @(posedge clk or posedge rst) begin
        if(rst) begin count<=0; bck<=1; bit_index<=0;frame_boundary<=HALF_CYCLES==1;end
        else begin
        frame_boundary<=frame_pre_ce;
        if(count==HALF_CYCLES-1) begin
            count<=0; bck<=~bck;
            if(!bck) bit_index<=bit_index+1'b1;
        end else count<=count+1'b1;
        end
    end
endmodule
