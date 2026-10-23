`timescale 1ns/1ps
`include "check.svh"
module tb_rgb_scan_timing;
    // Artificial porches for logic tests, NOT a panel profile.
    parameter integer W=800,H=480,HS=3,HB=5,HF=7,VS=2,VB=4,VF=3,DE_ONLY=0;
    localparam integer HT=W+HS+HB+HF,VT=H+VS+VB+VF;
    reg clk=0,rst=1;always #5 clk=~clk;
    wire [10:0] x,y,x1,y1;
    wire de,hs,vs,fs,de1,hs1,vs1,fs1;
    integer checks=0,i,h,v,visible=0,starts=0,lines=0,row_pixels=0;
    rgb_scan_timing #(.H_ACTIVE(W),.V_ACTIVE(H),.H_SYNC(HS),.H_BACK(HB),.H_FRONT(HF),
        .V_SYNC(VS),.V_BACK(VB),.V_FRONT(VF),.DE_ONLY(DE_ONLY)) low(clk,rst,x,y,de,hs,vs,fs);
    rgb_scan_timing #(.H_ACTIVE(W),.V_ACTIVE(H),.H_SYNC(HS),.H_BACK(HB),.H_FRONT(HF),
        .V_SYNC(VS),.V_BACK(VB),.V_FRONT(VF),.HS_ACTIVE(1),.VS_ACTIVE(1),.DE_ONLY(DE_ONLY))
        high(clk,rst,x1,y1,de1,hs1,vs1,fs1);
    initial begin
        repeat(2)@(negedge clk);
        `CHECK(!de && !fs,"reset suppresses valid pixels and frame pulses")
        rst=0;
        for(i=0;i<2*HT*VT;i=i+1)begin
            h=i%HT;v=(i/HT)%VT;
            #1;
            `CHECK(hs==!(!DE_ONLY && h<HS) && vs==!(!DE_ONLY && v<VS),"exact negative sync widths and positions")
            `CHECK(hs1==!hs && vs1==!vs,"positive sync profile complements negative profile")
            `CHECK({x1,y1,de1,fs1}=={x,y,de,fs},"polarity never changes raster or origin")
            `CHECK(fs==(h==0 && v==0),"one frame-start per complete raster")
            `CHECK(de==(h>=HS+HB && h<HS+HB+W && v>=VS+VB && v<VS+VB+H),"independent half-open active window")
            if(fs)begin starts=starts+1;`CHECK(!de,"snapshot origin lies in blanking") end
            if(de)begin
                visible=visible+1;row_pixels=row_pixels+1;
                `CHECK(x==h-HS-HB && y==v-VS-VB,"active coordinates cover exactly configured rectangle")
            end
            if(h==HT-1)begin
                if(row_pixels!=0)begin
                    `CHECK(row_pixels==W,"each visible row contains exactly W pixels")
                    lines=lines+1;
                end
                row_pixels=0;
            end
            @(negedge clk);
        end
        `CHECK(starts==2 && visible==2*W*H && lines==2*H,"two complete frames have exact area and duration")
        // Interrupt an active frame and require restart from blanking origin.
        repeat((VS+VB)*HT+HS+HB+1)@(negedge clk);
        rst=1;@(negedge clk);
        `CHECK(!de && !fs,"mid-frame reset immediately blanks valid outputs")
        rst=0;#1;
        `CHECK(fs && x==0 && y==0,"reset recovers at complete frame origin")
        $display("PASS tb_rgb_scan_timing checks=%0d",checks);$finish;
    end
    initial begin #30000000;$fatal(1,"scan timeout");end
endmodule

