`timescale 1ns/1ps
`include "config/keyboard_config.svh"
module matrix_keypad #(
    parameter integer SLOT_CYCLES=`KEY_SLOT_CYCLES,
    SETTLE_CYCLES=`KEY_SETTLE_CYCLES,DEBOUNCE_SCANS=`KEY_DEBOUNCE_SCANS)(
    input wire clk,rst,input wire [3:0] row_n,
    output wire [3:0] col_enable,
    output reg [15:0] keys,output reg scan_valid,ghost);
    localparam integer SW=$clog2(SLOT_CYCLES+1);
    localparam integer DW=DEBOUNCE_SCANS>1?$clog2(DEBOUNCE_SCANS+1):1;
    (* syn_preserve=1, syn_async_reg=1 *) reg [3:0] rows_meta,rows_sync;
    reg [SW-1:0] slot_count;
    reg [1:0] column;
    reg [15:0] work;
    reg [3:0] early_rows;
    reg [DW-1:0] debounce [0:15];
    reg ambiguous;
    reg [3:0] common_rows;
    integer a,b,k;
    assign col_enable=rst?4'b0:(4'b0001<<column);
    always @* begin
        ambiguous=0;common_rows=0;
        for(integer c=0;c<4;c=c+1)
            for(integer d=c+1;d<4;d=d+1)begin
                for(integer rr=0;rr<4;rr=rr+1)
                    common_rows[rr]=work[rr*4+c] && work[rr*4+d];
                if((common_rows & (common_rows-4'd1))!=0) ambiguous=1;
            end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin rows_meta<=4'hf;rows_sync<=4'hf;end
        else begin rows_meta<=row_n;rows_sync<=rows_meta;end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            slot_count<=0;column<=0;work<=0;keys<=0;scan_valid<=0;ghost<=0;early_rows<=4'hf;
            for(integer i=0;i<16;i=i+1)debounce[i]<=0;
        end else begin
            scan_valid<=0;
            if(slot_count==SETTLE_CYCLES-1)early_rows<=rows_sync;
            // Require low at both settled and late samples. A row still low
            // from the preceding column must not create a second key.
            if(slot_count==SLOT_CYCLES-2)
                for(integer rr=0;rr<4;rr=rr+1)work[rr*4+column]<=!rows_sync[rr] && !early_rows[rr];
            if(slot_count==SLOT_CYCLES-1)begin
                slot_count<=0;column<=column+1'b1;
                if(column==3)begin
                    scan_valid<=1;ghost<=ambiguous;
                    for(integer i=0;i<16;i=i+1)begin
                        // A rectangle without per-key diodes is ambiguous.
                        // Clear accepted keys immediately; do not invent notes.
                        if(ambiguous)begin keys[i]<=0;debounce[i]<=0;end
                        else if(work[i]==keys[i])debounce[i]<=0;
                        else if(debounce[i]==DEBOUNCE_SCANS-1)begin
                            keys[i]<=work[i];debounce[i]<=0;
                        end else debounce[i]<=debounce[i]+1'b1;
                    end
                end
            end else slot_count<=slot_count+1'b1;
        end
    end
    // synthesis translate_off
    initial begin
        if(SETTLE_CYCLES<3 || SLOT_CYCLES<=SETTLE_CYCLES+1 || DEBOUNCE_SCANS<1)
            $fatal(1,"Invalid matrix scan timing");
    end
    // synthesis translate_on
endmodule
