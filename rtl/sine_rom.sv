`timescale 1ns/1ps
`include "synth_config.svh"
module sine_rom #(parameter ROM_FILE="rom/sine4096.hex")(
    input wire clk, ce, input wire [`ROM_ADDR_W-1:0] addr,
    output reg signed [`ROM_DATA_W-1:0] q);
    reg signed [`ROM_DATA_W-1:0] mem [0:(1<<`ROM_ADDR_W)-1];
    initial $readmemh(ROM_FILE,mem);
    always @(posedge clk) if(ce) q<=mem[addr];
endmodule
