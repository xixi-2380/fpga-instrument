`timescale 1ns/1ps
module frame_buffer(input wire clk,rst,frame_ce,sample_valid,
    output wire sample_ready, input wire signed [15:0] sample_l,sample_r,
    output wire [15:0] frame_l,frame_r,output reg underrun);
    reg [15:0] pending_l,pending_r,active_l,active_r;
    reg pending_valid,seen_frame;
    assign sample_ready=!pending_valid || frame_ce;
    // At the boundary consume the OLD pending pair; a simultaneous handshake
    // fills the next frame. The serializer sees this pair before the NBA update.
    assign frame_l=frame_ce ? (pending_valid?pending_l:16'b0) : active_l;
    assign frame_r=frame_ce ? (pending_valid?pending_r:16'b0) : active_r;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            pending_l<=0;pending_r<=0;active_l<=0;active_r<=0;
            pending_valid<=0;seen_frame<=0;underrun<=0;
        end else begin
            if(frame_ce) begin
                active_l<=pending_valid?pending_l:16'b0;
                active_r<=pending_valid?pending_r:16'b0;
                pending_valid<=0;
                if(seen_frame && !pending_valid) underrun<=1;
                seen_frame<=1;
            end
            if(sample_valid && sample_ready) begin
                pending_l<=sample_l;pending_r<=sample_r;pending_valid<=1;
            end
        end
    end
endmodule
