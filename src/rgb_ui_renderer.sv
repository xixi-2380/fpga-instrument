`timescale 1ns/1ps
// Pixel-domain only. status_data must already be an atomic, stable snapshot.
// [19] test pattern, [18] ghost, [17] underrun, [16] score error,
// [15] audio ready, [14] score busy, [13:12] manual timbre,
// [11:6] held voices, [5:0] active voices (including release tails).
module rgb_ui_renderer(
    input wire pixel_clk, rst, frame_start, status_valid,
    input wire [19:0] status_data,
    input wire [10:0] x, y,
    input wire de_in, hs_in, vs_in,
    output reg [23:0] rgb,
    output reg de_out, hs_out, vs_out
);
    localparam [23:0] BG=24'h101826, PANEL=24'h1c293b,
        WHITE=24'he8eef5, DIM=24'h7890a8, CYAN=24'h35d5cf,
        GREEN=24'h65d48b, RED=24'hff6578, AMBER=24'hf4c46b;
    reg [19:0] state;
    reg [23:0] color;
    wire [5:0] active_count=state[5:0]>32 ? 6'd32 : state[5:0];
    wire [5:0] held_count=state[11:6]>32 ? 6'd32 : state[11:6];

    // Original compact 5x7 block font, rows from top to bottom, MSB at left.
    function automatic [34:0] glyph(input [7:0] ch);
        begin
            case(ch)
                "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
                "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
                "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
                "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
                "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
                "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
                "G":glyph=35'b01111_10000_10000_10111_10001_10001_01111;
                "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
                "I":glyph=35'b11111_00100_00100_00100_00100_00100_11111;
                "K":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
                "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
                "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
                "N":glyph=35'b10001_11001_11001_10101_10011_10011_10001;
                "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
                "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
                "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
                "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
                "W":glyph=35'b10001_10001_10001_10101_10101_11011_10001;
                "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
                "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
                "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
                "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
                "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
                "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
                "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
                "/":glyph=35'b00001_00001_00010_00100_01000_10000_10000;
                "?":glyph=35'b01110_10001_00001_00010_00100_00000_00100;
                default:glyph=0;
            endcase
        end
    endfunction

    // Fixed 4x scale: 20x28 ink in each 24x32 character cell.
    function automatic text_pixel(input [127:0] str, input integer length,
        input integer dx, dy);
        integer col, row, index;
        reg [34:0] bits;
        begin
            text_pixel=0;
            if(dx>=0 && dx<length*24 && dy>=0 && dy<28)begin
                index=dx/24; col=(dx%24)>>2; row=dy>>2;
                bits=glyph(str[(length-1-index)*8+:8]);
                if(col<5)text_pixel=bits[34-row*5-col];
            end
        end
    endfunction

    function automatic digit_pixel(input [5:0] count, input integer dx,dy);
        reg [127:0] digits;
        begin
            digits=0;
            digits[31:24]=8'd48+count/10;
            digits[23:16]=8'd48+count%10;
            digits[15:8]="/"; digits[7:0]="3";
            digit_pixel=text_pixel(digits,4,dx,dy) || text_pixel("2",1,dx-96,dy);
        end
    endfunction

    always @* begin
        color=BG;
        if(x>=24 && x<776 && y>=96 && y<448)color=PANEL;
        if(y<8)color=CYAN;
        if(text_pixel("FPGA INSTRUMENT",15,integer'(x)-32,integer'(y)-32))color=WHITE;
        if(text_pixel("MODE",4,integer'(x)-48,integer'(y)-116))color=DIM;
        if(state[14])begin
            if(text_pixel("SCORE",5,integer'(x)-264,integer'(y)-116))color=CYAN;
        end else if(text_pixel("KEYBOARD",8,integer'(x)-264,integer'(y)-116))color=CYAN;
        if(text_pixel("MANUAL TIMBRE",13,integer'(x)-48,integer'(y)-164))color=DIM;
        case(state[13:12])
            0:if(text_pixel("SINE",4,integer'(x)-432,integer'(y)-164))color=WHITE;
            1:if(text_pixel("FLUTE",5,integer'(x)-432,integer'(y)-164))color=WHITE;
            2:if(text_pixel("REED",4,integer'(x)-432,integer'(y)-164))color=WHITE;
            3:if(text_pixel("?",1,integer'(x)-432,integer'(y)-164))color=AMBER;
        endcase
        if(text_pixel("ACTIVE",6,integer'(x)-48,integer'(y)-224) ||
           digit_pixel(active_count,integer'(x)-264,integer'(y)-224))color=CYAN;
        if(text_pixel("HELD",4,integer'(x)-48,integer'(y)-312) ||
           digit_pixel(held_count,integer'(x)-264,integer'(y)-312))color=GREEN;
        // 32 fixed slots, each 22 pixels plus a 2-pixel gap; no frame buffer.
        if(x>=48 && x<752 && (x-48)%22<20)begin
            if(y>=268 && y<288)color=((x-48)/22<active_count)?CYAN:BG;
            if(y>=356 && y<376)color=((x-48)/22<held_count)?GREEN:BG;
        end
        if(text_pixel("AUDIO",5,integer'(x)-48,integer'(y)-404))color=state[15]?GREEN:AMBER;
        if(text_pixel("SCORE",5,integer'(x)-216,integer'(y)-404))color=state[16]?RED:DIM;
        if(text_pixel("BUFFER",6,integer'(x)-384,integer'(y)-404))color=state[17]?RED:DIM;
        if(text_pixel("GHOST",5,integer'(x)-576,integer'(y)-404))color=state[18]?AMBER:DIM;
        if(state[19])begin
            case(x/100)
                0:color=24'hffffff; 1:color=24'hffff00;
                2:color=24'h00ffff; 3:color=24'h00ff00;
                4:color=24'hff00ff; 5:color=24'hff0000;
                6:color=24'h0000ff; default:color=24'h000000;
            endcase
            if(x==0 || x==799 || y==0 || y==479)color=WHITE;
        end
        if(!de_in || x>=800 || y>=480)color=0;
    end

    always @(posedge pixel_clk)begin
        if(rst)begin
            state<=0; rgb<=0; de_out<=0; hs_out<=0; vs_out<=0;
        end else begin
            if(frame_start && status_valid)state<=status_data;
            rgb<=color;
            de_out<=de_in && x<800 && y<480;
            hs_out<=hs_in; vs_out<=vs_in;
        end
    end
endmodule
