`timescale 1ns/1ps
`include "config/synth_config.svh"
module lock_guard #(parameter integer STABLE_CYCLES=`LOCK_CYCLES)(
    input wire clk, rst, lock_async, output reg qualified);
    localparam integer CW=$clog2(STABLE_CYCLES+1);
    wire arst=rst | ~lock_async;
    (* syn_preserve=1, syn_async_reg=1 *) reg [1:0] lock_sync;
    reg [CW-1:0] count;
    always @(posedge clk or posedge arst) begin
        if(arst) begin lock_sync<=0; count<=0; qualified<=0; end
        else begin
            lock_sync<={lock_sync[0],1'b1};
            if(!lock_sync[1]) begin count<=0; qualified<=0; end
            else if(!qualified) begin
                if(count==STABLE_CYCLES-1) qualified<=1;
                else count<=count+1'b1;
            end
        end
    end
endmodule
