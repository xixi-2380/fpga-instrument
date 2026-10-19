`timescale 1ns/1ps
// Single feed-forward echo. Memory is never bulk-reset: fill count masks stale
// samples, including across resets. Read and write occupy different cycles.
module audio_delay #(parameter integer DELAY_SAMPLES=7200)(
    input wire clk,rst,enable,in_valid,input wire signed [15:0] in_sample,
    output wire in_ready,output reg out_valid,output reg signed [15:0] out_sample);
    localparam integer AW=DELAY_SAMPLES>1?$clog2(DELAY_SAMPLES):1;
    localparam integer FW=$clog2(DELAY_SAMPLES+1);
    reg signed [15:0] memory[0:DELAY_SAMPLES-1];
    reg [AW-1:0] pointer;
    reg [FW-1:0] filled;
    reg busy,history_valid;
    reg signed [15:0] dry,history;
    reg [6:0] wet_level,used_level;
    wire accept=in_valid && in_ready;
    assign in_ready=!rst && !busy;
    // 64/256 wet when enabled. Fade one step per accepted audio sample.
    // Weighted average bounds the output without increasing the dry peak.
    wire signed [31:0] dry_ext={{16{dry[15]}},dry};
    wire signed [31:0] delayed_ext=history_valid?{{16{history[15]}},history}:32'sd0;
    wire signed [31:0] level_ext=$signed({25'd0,used_level});
    wire signed [31:0] blend=(dry_ext <<< 8)+(delayed_ext-dry_ext)*level_ext;
    wire signed [31:0] result=blend >>> 8;
    always @(posedge clk)begin
        if(!rst)begin
            if(accept)history<=memory[pointer];
            if(busy)memory[pointer]<=dry;
        end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            pointer<=0;filled<=0;busy<=0;history_valid<=0;dry<=0;
            wet_level<=0;used_level<=0;out_valid<=0;out_sample<=0;
        end else begin
            out_valid<=0;
            if(accept)begin
                dry<=in_sample;history_valid<=filled==DELAY_SAMPLES;
                used_level<=wet_level;busy<=1;
                case(enable)
                    1'b1:if(wet_level<64)wet_level<=wet_level+1'b1;
                    default:if(wet_level!=0)wet_level<=wet_level-1'b1;
                endcase
            end else if(busy)begin
                // Arithmetic is signed, with floor rounding for negatives.
                if(result>32767)out_sample<=16'sh7fff;
                else if(result < -32768)out_sample<=16'sh8000;
                else out_sample<=result[15:0];
                out_valid<=1;busy<=0;
                if(pointer==DELAY_SAMPLES-1)pointer<=0;else pointer<=pointer+1'b1;
                if(filled<DELAY_SAMPLES)filled<=filled+1'b1;
            end
        end
    end
    // synthesis translate_off
    initial if(DELAY_SAMPLES<1)$fatal(1,"Delay length must be positive");
    // synthesis translate_on
endmodule
