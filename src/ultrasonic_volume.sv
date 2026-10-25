`timescale 1ns/1ps
// Only sample_valid readings enter the median history. Invalid attempts hold gain.
module ultrasonic_volume(
    input wire clk, input wire rst,
    input wire sample_valid, input wire [8:0] distance_cm,
    output reg [8:0] filtered_cm,
    output reg [8:0] gain_target, // unsigned Q1.8: 0=mute, 256=unity
    output reg control_valid
);
    reg seeded; reg [8:0] old1, old2;
    function [8:0] median3;
        input [8:0] a,b,c;
        begin
            if(a>b) begin
                if(b>c) median3=b; else if(a>c) median3=c; else median3=a;
            end else begin
                if(a>c) median3=a; else if(b>c) median3=c; else median3=b;
            end
        end
    endfunction
    wire [8:0] next_cm = seeded ? median3(distance_cm,old1,old2) : distance_cm;
    function [8:0] map_gain;
        input [8:0] cm;
        begin
            if(cm<=5) map_gain=256;
            else if(cm>=40) map_gain=0;
            else case(cm)
                9'd6: map_gain=9'd249;
                9'd7: map_gain=9'd241;
                9'd8: map_gain=9'd234;
                9'd9: map_gain=9'd227;
                9'd10: map_gain=9'd219;
                9'd11: map_gain=9'd212;
                9'd12: map_gain=9'd205;
                9'd13: map_gain=9'd197;
                9'd14: map_gain=9'd190;
                9'd15: map_gain=9'd183;
                9'd16: map_gain=9'd176;
                9'd17: map_gain=9'd168;
                9'd18: map_gain=9'd161;
                9'd19: map_gain=9'd154;
                9'd20: map_gain=9'd146;
                9'd21: map_gain=9'd139;
                9'd22: map_gain=9'd132;
                9'd23: map_gain=9'd124;
                9'd24: map_gain=9'd117;
                9'd25: map_gain=9'd110;
                9'd26: map_gain=9'd102;
                9'd27: map_gain=9'd95;
                9'd28: map_gain=9'd88;
                9'd29: map_gain=9'd80;
                9'd30: map_gain=9'd73;
                9'd31: map_gain=9'd66;
                9'd32: map_gain=9'd59;
                9'd33: map_gain=9'd51;
                9'd34: map_gain=9'd44;
                9'd35: map_gain=9'd37;
                9'd36: map_gain=9'd29;
                9'd37: map_gain=9'd22;
                9'd38: map_gain=9'd15;
                9'd39: map_gain=9'd7;
                default: map_gain=256;
            endcase
        end
    endfunction
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            seeded<=0; old1<=0; old2<=0; filtered_cm<=0;
            gain_target<=256; control_valid<=0;
        end else begin
            control_valid<=0;
            if(sample_valid) begin
                seeded<=1; old1<=distance_cm;
                old2<=seeded ? old1 : distance_cm;
                filtered_cm<=next_cm; gain_target<=map_gain(next_cm); control_valid<=1;
            end
        end
    end
endmodule
