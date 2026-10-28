`timescale 1ns/1ps
// Four normalized parallel feedback combs: a small, deliberately simple room.
// The recurrence (input + delayed)/2 is bounded and rounds toward zero so
// negative quantization residues cannot circulate forever. No bulk RAM reset.
module audio_reverb #(
    parameter integer D0=1499,D1=1601,D2=1867,D3=2053)(
    input wire clk,rst,in_valid,input wire signed [15:0] in_sample,
    output wire in_ready,output reg out_valid,output reg signed [15:0] out_sample);
    reg busy;
    reg signed [15:0] dry;
    wire signed [15:0] taps[0:3];
    assign in_ready=!rst && !busy;
    wire accept=in_valid && in_ready;
    function automatic signed [15:0] half_zero(input signed [31:0] value);
        begin half_zero=value<0 ? -((-value)>>>1) : value>>>1;end
    endfunction
    for(genvar b=0;b<4;b=b+1)begin: combs
        localparam integer N=b==0?D0:b==1?D1:b==2?D2:D3;
        localparam integer AW=N>1?$clog2(N):1,FW=$clog2(N+1);
        reg signed [15:0] memory[0:N-1];
        reg signed [15:0] history;
        reg [AW-1:0] pointer;
        reg [FW-1:0] filled;
        reg history_valid;
        assign taps[b]=history_valid?history:16'sd0;
        wire signed [31:0] input_ext={{16{dry[15]}},dry};
        wire signed [31:0] history_ext={{16{taps[b][15]}},taps[b]};
        always @(posedge clk)if(!rst)begin
            if(accept)history<=memory[pointer];
            if(busy)memory[pointer]<=half_zero(input_ext+history_ext);
        end
        always @(posedge clk or posedge rst)begin
            if(rst)begin pointer<=0;filled<=0;history_valid<=0;end
            else begin
                if(accept)history_valid<=filled==N;
                if(busy)begin
                    pointer<=pointer==N-1?0:pointer+1'b1;
                    if(filled<N)filled<=filled+1'b1;
                end
            end
        end
    end
    wire signed [31:0] tap0={{16{taps[0][15]}},taps[0]};
    wire signed [31:0] tap1={{16{taps[1][15]}},taps[1]};
    wire signed [31:0] tap2={{16{taps[2][15]}},taps[2]};
    wire signed [31:0] tap3={{16{taps[3][15]}},taps[3]};
    wire signed [31:0] sum=(tap0+tap1)+(tap2+tap3);
    always @(posedge clk or posedge rst)begin
        if(rst)begin busy<=0;dry<=0;out_valid<=0;out_sample<=0;end
        else begin
            out_valid<=0;
            if(accept)begin dry<=in_sample;busy<=1;end
            else if(busy)begin out_sample<=sum>>>2;out_valid<=1;busy<=0;end
        end
    end
    // synthesis translate_off
    initial if(D0<1 || D1<1 || D2<1 || D3<1)$fatal(1,"Invalid room delays");
    // synthesis translate_on
endmodule
