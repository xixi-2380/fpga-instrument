`timescale 1ns/1ps
// D0 diagnostic: original DAC pins retained; user-selected J23 header mirrors for scope access.
// No derived internal clock. Amplifier and DAC data remain hard zero.
module bringup_digital #(parameter integer LOCK_N=100000)(
    input wire clk,rst,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,
    output wire DBG_BCK,DBG_WS,DBG_DIN,DBG_PA_EN);
    wire unused_din,unused_pa;
    tone_top #(.LOCK_N(LOCK_N)) engine(clk,rst,HP_BCK,HP_WS,unused_din,unused_pa);
    assign HP_DIN=1'b0;
    assign PA_EN=1'b0;
    // Both ports share the same internal signal; pad/routing skew is physical.
    assign DBG_BCK=HP_BCK;
    assign DBG_WS=HP_WS;
    assign DBG_DIN=HP_DIN;
    assign DBG_PA_EN=PA_EN;
endmodule
