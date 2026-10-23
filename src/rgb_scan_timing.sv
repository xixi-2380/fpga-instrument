`timescale 1ns/1ps
// No panel-specific timing defaults: zero porches/syncs are invalid sentinels.
// Supply all six values and both polarities from a verified panel profile.
module rgb_scan_timing #(
    parameter integer H_ACTIVE=800,V_ACTIVE=480,
    H_SYNC=0,H_BACK=0,H_FRONT=0,V_SYNC=0,V_BACK=0,V_FRONT=0,
    HS_ACTIVE=0,VS_ACTIVE=0,DE_ONLY=0
)(
    input wire pixel_clk,rst,
    output wire [10:0] x,y,
    output wire de,hs,vs,frame_start
);
    localparam integer H_TOTAL=H_SYNC+H_BACK+H_ACTIVE+H_FRONT;
    localparam integer V_TOTAL=V_SYNC+V_BACK+V_ACTIVE+V_FRONT;
    localparam integer X_START=H_SYNC+H_BACK,Y_START=V_SYNC+V_BACK;
    reg [10:0] hpos,vpos;
    wire visible_h=(hpos>=X_START && hpos<X_START+H_ACTIVE);
    wire visible_v=(vpos>=Y_START && vpos<Y_START+V_ACTIVE);
    // Coordinates outside the active window are deterministic zero; DE gates them.
    assign x=visible_h ? hpos-X_START : 11'd0;
    assign y=visible_v ? vpos-Y_START : 11'd0;
    assign de=!rst && visible_h && visible_v;
    assign hs=(!DE_ONLY && hpos<H_SYNC) ? HS_ACTIVE[0] : !HS_ACTIVE[0];
    assign vs=(!DE_ONLY && vpos<V_SYNC) ? VS_ACTIVE[0] : !VS_ACTIVE[0];
    // Origin is inside vertical AND horizontal blanking, before any active pixel.
    assign frame_start=!rst && hpos==0 && vpos==0;
    always @(posedge pixel_clk)begin
        if(rst)begin hpos<=0;vpos<=0;end
        else if(hpos==H_TOTAL-1)begin
            hpos<=0;
            if(vpos==V_TOTAL-1)vpos<=0;
            else vpos<=vpos+1'b1;
        end else hpos<=hpos+1'b1;
    end
`ifndef SYNTHESIS
    initial begin
        if(H_ACTIVE<1 || V_ACTIVE<1 || H_SYNC<0 || V_SYNC<0 ||
           (!DE_ONLY && (H_SYNC<1 || V_SYNC<1)) ||
           H_BACK<1 || V_BACK<1 || H_FRONT<1 || V_FRONT<1 ||
           H_TOTAL>2048 || V_TOTAL>2048 ||
           (HS_ACTIVE!=0 && HS_ACTIVE!=1) || (VS_ACTIVE!=0 && VS_ACTIVE!=1))
            $fatal(1,"rgb_scan_timing requires an explicit, valid panel timing profile");
    end
`endif
endmodule
