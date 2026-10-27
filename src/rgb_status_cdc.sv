`timescale 1ns/1ps
// Four-phase bundled-data snapshot. The two domains share async_reset;
// assert it whenever EITHER domain resets/loses its clock qualification.
// The source never waits for the display and may change source_data each cycle.
// Only captured data is held; intermediate snapshots may be skipped by design.
module rgb_status_cdc #(
    parameter integer WIDTH=20
)(
    input wire source_clk,pixel_clk,async_reset,
    input wire [WIDTH-1:0] source_data,
    output reg [WIDTH-1:0] pixel_data,
    output reg pixel_valid,
    output reg update_pulse
);
    wire source_reset,pixel_reset;
    reset_sync source_reset_sync(source_clk,async_reset,source_reset);
    reset_sync pixel_reset_sync(pixel_clk,async_reset,pixel_reset);
    reg request,acknowledge;
    (* syn_preserve=1,syn_async_reg=1 *) reg [1:0] request_sync,ack_sync;
    (* syn_preserve=1 *) reg [WIDTH-1:0] held_data;
    // Single-bit control synchronizers; do not synchronize payload bits separately.
    always @(posedge source_clk or posedge source_reset)
        if(source_reset)request_sync<=0;
        else request_sync<={request_sync[0],request};
    always @(posedge pixel_clk or posedge pixel_reset)
        if(pixel_reset)ack_sync<=0;
        else ack_sync<={ack_sync[0],acknowledge};

    // Local resets assert asynchronously but release in their own domain.
    // Raw async_reset must not drive wide cross-domain payload CLEAR pins.
    always @(posedge source_clk or posedge source_reset)begin
        if(source_reset)begin acknowledge<=0;held_data<=0;end
        else if(!acknowledge && request_sync[1])begin
            held_data<=source_data;
            acknowledge<=1;
        end else if(acknowledge && !request_sync[1])acknowledge<=0;
    end
    always @(posedge pixel_clk or posedge pixel_reset)begin
        if(pixel_reset)begin
            request<=0;pixel_data<=0;pixel_valid<=0;update_pulse<=0;
        end else begin
            update_pulse<=0;
            if(!request && !ack_sync[1])request<=1;
            else if(request && ack_sync[1])begin
                // Payload has been held while ACK crossed two pixel registers.
                pixel_data<=held_data;
                pixel_valid<=1;
                update_pulse<=1;
                request<=0;
            end
        end
    end
endmodule
