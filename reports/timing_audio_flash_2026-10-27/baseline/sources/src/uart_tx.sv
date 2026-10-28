`timescale 1ns/1ps
// Accept exactly when valid && ready. Payload is latched on acceptance.
module uart_tx #(
    parameter integer CLOCK_HZ=50000000, BAUD=9600
)(input wire clk,rst,input wire [7:0] data,input wire valid,
  output wire ready,output reg tx);
    localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
    localparam integer CW=$clog2(DIV+1);
    reg busy;
    reg [CW-1:0] timer;
    reg [3:0] bit_index;
    reg [9:0] shift;
    assign ready=!busy && !rst;
    always @(posedge clk or posedge rst)begin
        if(rst)begin busy<=0;timer<=0;bit_index<=0;shift<=10'h3ff;tx<=1;end
        else if(!busy)begin
            tx<=1;
            if(valid)begin shift<={1'b1,data,1'b0};tx<=0;busy<=1;timer<=DIV-1;bit_index<=0;end
        end else if(timer!=0)timer<=timer-1'b1;
        else if(bit_index==9)begin busy<=0;tx<=1;end
        else begin shift<={1'b1,shift[9:1]};tx<=shift[1];bit_index<=bit_index+1'b1;timer<=DIV-1;end
    end
    // synthesis translate_off
    initial if(DIV<16)$fatal(1,"UART requires at least 16 clocks/bit");
    // synthesis translate_on
endmodule
