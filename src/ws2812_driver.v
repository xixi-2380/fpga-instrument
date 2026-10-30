// WS2812B: runtime RGB, brightness, on/off and active LED count.
module ws2812_driver #(
    parameter integer LED_COUNT = 21,
    parameter integer CLK_MHZ = 50
)(
    input wire clk, rst_n, start, enable,
    input wire [7:0] brightness, active_count,
    input wire [LED_COUNT*24-1:0] rgb_data, // LED 0 = [23:0], RRGGBB
    output reg data,
    output wire busy,
    output reg done
);
    localparam integer BIT_TIME = (CLK_MHZ*1260+999)/1000;
    localparam integer HIGH_0 = (CLK_MHZ*360+999)/1000;
    localparam integer HIGH_1 = (CLK_MHZ*680+999)/1000;
    localparam integer RESET_TIME = CLK_MHZ*300;
    localparam BOOT=0, IDLE=1, LOAD=2, SEND=3, LATCH=4;
    reg [2:0] state;
    reg [LED_COUNT*24-1:0] frame;
    reg [23:0] pixel;
    reg [7:0] level, count;
    integer timer, led_index, bit_index;
    assign busy = state != IDLE;

    function [7:0] dim;
        input [7:0] color, brightness;
        reg [15:0] result;
        begin
            result = color * brightness;
            result = result / 16'd255;
            dim = result[7:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= BOOT;
            timer <= 0;
            data <= 0;
            done <= 0;
        end else begin
            data <= 0;
            done <= 0;
            case (state)
                BOOT, LATCH:
                    if (timer == RESET_TIME-1) begin
                        timer <= 0;
                        done <= state == LATCH;
                        state <= IDLE;
                    end else timer <= timer+1;
                IDLE: if (start) begin
                    frame <= rgb_data;
                    level <= enable ? brightness : 8'd0;
                    count <= active_count;
                    led_index <= 0;
                    bit_index <= 23;
                    timer <= 0;
                    state <= LOAD;
                end
                LOAD: begin
                    pixel <= led_index < count ?
                        {dim(frame[15:8],level), dim(frame[23:16],level),
                         dim(frame[7:0],level)} : 24'd0;
                    state <= SEND;
                end
                SEND: begin
                    data <= timer < (pixel[23] ? HIGH_1 : HIGH_0);
                    if (timer == BIT_TIME-1) begin
                        timer <= 0;
                        pixel <= {pixel[22:0],1'b0};
                        if (bit_index != 0) bit_index <= bit_index-1;
                        else begin
                            bit_index <= 23;
                            frame <= frame >> 24;
                            led_index <= led_index+1;
                            state <= led_index == LED_COUNT-1 ? LATCH : LOAD;
                        end
                    end else timer <= timer+1;
                end
                default: begin state <= BOOT; timer <= 0; end
            endcase
        end
    end
endmodule