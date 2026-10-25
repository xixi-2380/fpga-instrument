`timescale 1ns/1ps
// Verilog-2001. clk_hz must be a whole multiple of 1 MHz, >= 1 MHz.
// rst: async assertion, synchronous release in the reference-clock domain.
module ultrasonic_range #(
    parameter integer CLK_HZ = 50000000
)(
    input wire clk, input wire rst, input wire echo_async,
    output reg trig,
    output reg [8:0] distance_cm,
    output reg sample_done, output reg sample_valid,
    output reg [2:0] error_code
);
    localparam integer US_DIV = CLK_HZ / 1000000;
    function integer clog2;
        input integer n; integer v;
        begin v=n-1; clog2=0; while(v>0) begin clog2=clog2+1; v=v>>1; end
              if(clog2<1) clog2=1; end
    endfunction
    localparam integer US_LAST = US_DIV-1;
    reg [clog2(US_DIV)-1:0] us_divider;
    wire us_tick = (us_divider == US_LAST[clog2(US_DIV)-1:0]);
    // Only echo_meta may consume the asynchronous pin.
    (* syn_preserve = 1, syn_async_reg = 1 *) reg echo_meta;
    (* syn_preserve = 1, syn_async_reg = 1 *) reg echo_sync;
    always @(posedge clk or posedge rst) begin
        if(rst) begin echo_meta<=0; echo_sync<=0; us_divider<=0; end
        else begin
            echo_meta<=echo_async; echo_sync<=echo_meta;
            if(us_tick) us_divider<=0; else us_divider<=us_divider+1'b1;
        end
    end
    localparam IDLE=2'd0, TRIGGER=2'd1, WAIT_RISE=2'd2, MEASURE=2'd3;
    reg [1:0] state;
    reg [15:0] period_us, timer_us, width_us;
    reg [9:0] whole_cm;
    reg [5:0] fraction_us;
    wire [10:0] rounded_cm = {1'b0,whole_cm} + ((fraction_us>=29) ? 11'd1 : 11'd0);
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            // Wait a full quiet interval after reset before transmitting.
            state<=IDLE; period_us<=0; timer_us<=0; width_us<=0;
            whole_cm<=0; fraction_us<=0; trig<=0; distance_cm<=0;
            sample_done<=0; sample_valid<=0; error_code<=0;
        end else begin
            sample_done<=0; sample_valid<=0;
            if(us_tick) begin
                if(period_us<59999) period_us<=period_us+1'b1;
                case(state)
                    IDLE: begin
                        trig<=0;
                        if(period_us==59999) begin
                            period_us<=0; timer_us<=0;
                            if(echo_sync) begin
                                sample_done<=1; error_code<=4; // Echo already high
                            end else begin trig<=1; state<=TRIGGER; end
                        end
                    end
                    TRIGGER: begin
                        if(timer_us==19) begin
                            trig<=0; timer_us<=0; state<=WAIT_RISE;
                        end else timer_us<=timer_us+1'b1;
                    end
                    WAIT_RISE: begin
                        if(echo_sync) begin
                            width_us<=1; whole_cm<=0; fraction_us<=1;
                            timer_us<=0; state<=MEASURE;
                        end else if(timer_us==29999) begin
                            sample_done<=1; error_code<=1; state<=IDLE;
                        end else timer_us<=timer_us+1'b1;
                    end
                    MEASURE: begin
                        if(!echo_sync) begin
                            sample_done<=1; state<=IDLE;
                            if(width_us>=116 && rounded_cm>=2 && rounded_cm<=400) begin
                                distance_cm<=rounded_cm[8:0]; sample_valid<=1; error_code<=0;
                            end else error_code<=3;
                        end else if(width_us==29999) begin
                            sample_done<=1; error_code<=2; state<=IDLE;
                        end else begin
                            width_us<=width_us+1'b1;
                            // Sequential quotient/remainder: no combinational /58.
                            if(fraction_us==57) begin fraction_us<=0; whole_cm<=whole_cm+1'b1; end
                            else fraction_us<=fraction_us+1'b1;
                        end
                    end
                    default: begin state<=IDLE; trig<=0; end
                endcase
            end
        end
    end
    // synthesis translate_off
    initial if(CLK_HZ<1000000 || CLK_HZ%1000000!=0)
        $fatal(1,"ultrasonic_range needs an integer-MHz reference clock");
    // synthesis translate_on
endmodule
