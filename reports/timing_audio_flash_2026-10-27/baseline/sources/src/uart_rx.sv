`timescale 1ns/1ps
// 8N1, LSB first. One-cycle valid/error pulses; downstream cannot stall RX.
module uart_rx #(
    parameter integer CLOCK_HZ=50000000, BAUD=9600
)(input wire clk,rst,rx, output reg [7:0] data,
  output reg valid,framing_error);
    localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
    localparam integer CW=$clog2(DIV+1);
    localparam [2:0] IDLE=0,START=1,DATA=2,STOP=3,RECOVER=4;
    (* syn_async_reg="true" *) reg rx_meta,rx_sync;
    reg [2:0] state,bit_index;
    reg [CW-1:0] timer;
    reg [7:0] shift;
    always @(posedge clk or posedge rst) begin
        if(rst)begin rx_meta<=1;rx_sync<=1;end
        else begin rx_meta<=rx;rx_sync<=rx_meta;end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin state<=IDLE;timer<=0;bit_index<=0;shift<=0;data<=0;valid<=0;framing_error<=0;end
        else begin
            valid<=0;framing_error<=0;
            case(state)
                IDLE:if(!rx_sync)begin timer<=DIV/2-1;state<=START;end
                START:if(timer!=0)timer<=timer-1'b1;
                    else if(rx_sync)state<=IDLE;
                    else begin timer<=DIV-1;bit_index<=0;state<=DATA;end
                DATA:if(timer!=0)timer<=timer-1'b1;
                    else begin
                        shift[bit_index]<=rx_sync;timer<=DIV-1;
                        if(bit_index==7)state<=STOP;else bit_index<=bit_index+1'b1;
                    end
                STOP:if(timer!=0)timer<=timer-1'b1;
                    else if(rx_sync)begin data<=shift;valid<=1;state<=IDLE;end
                    else begin framing_error<=1;state<=RECOVER;timer<=0;end
                // Following a break, require one full idle bit before accepting.
                RECOVER:if(!rx_sync)timer<=0;
                    else if(timer==DIV-1)begin timer<=0;state<=IDLE;end
                    else timer<=timer+1'b1;
                default:state<=IDLE;
            endcase
        end
    end
    // synthesis translate_off
    initial if(DIV<16)$fatal(1,"UART requires at least 16 clocks/bit");
    // synthesis translate_on
endmodule
