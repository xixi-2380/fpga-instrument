`timescale 1ns/1ps
// Keys are already synchronized/debounced by matrix_keypad.
// Exact opposite-corner chord selects once; fully release before selecting again.
module timbre_control(input wire clk,rst,input wire [15:0] keys,
    output reg [1:0] selected);
    reg armed;
    always @(posedge clk or posedge rst)begin
        if(rst)begin selected<=0;armed<=1;end
        else if(keys==0)armed<=1;
        else if(armed && keys==16'h8001)begin
            selected<=selected==2?0:selected+1'b1;
            armed<=0;
        end
    end
endmodule
