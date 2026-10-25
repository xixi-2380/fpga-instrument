`timescale 1ns/1ps
// Input and output are signed PCM, NOT unsigned DAC / PWM codes.
// sample_ce is a one-clock enable in this same clk domain.
// Every accepted sample appears at sample_out one clk later with out_valid=1.
module audio_master_gain #(
    parameter integer SAMPLE_BITS=16,
    parameter integer SLEW_SAMPLES=4 // full-scale ramp: 1024 samples ~=21.3ms @48kHz
)(
    input wire clk, input wire rst,
    input wire [8:0] gain_target,
    input wire sample_ce,
    input wire signed [SAMPLE_BITS-1:0] sample_in,
    output reg signed [SAMPLE_BITS-1:0] sample_out,
    output reg out_valid,
    output reg [8:0] gain_current
);
    function integer clog2;
        input integer n; integer v;
        begin v=n-1; clog2=0; while(v>0) begin clog2=clog2+1; v=v>>1; end
            if(clog2<1) clog2=1; end
    endfunction
    localparam integer SLEW_LAST = SLEW_SAMPLES-1;
    reg [clog2(SLEW_SAMPLES)-1:0] slew_count;
    wire [8:0] requested_gain = (gain_target>256) ? 9'd256 : gain_target;
    reg signed [SAMPLE_BITS+9:0] product;
    reg sample_pending;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            gain_current<=256; slew_count<=0; product<=0;
            sample_pending<=0; sample_out<=0; out_valid<=0;
        end else begin
            sample_pending<=sample_ce; out_valid<=sample_pending;
            if(sample_pending) sample_out<=product >>> 8;
            if(sample_ce) begin
                product <= $signed(sample_in) * $signed({1'b0,gain_current});
                if(gain_current==requested_gain) slew_count<=0;
                else if(slew_count==SLEW_LAST[clog2(SLEW_SAMPLES)-1:0]) begin
                    slew_count<=0;
                    if(gain_current<requested_gain) gain_current<=gain_current+1'b1;
                    else gain_current<=gain_current-1'b1;
                end else slew_count<=slew_count+1'b1;
            end
        end
    end
    // synthesis translate_off
    initial if(SAMPLE_BITS<2 || SLEW_SAMPLES<1) $fatal(1,"Invalid master gain parameters");
    // synthesis translate_on
endmodule
