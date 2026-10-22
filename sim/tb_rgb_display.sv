`timescale 1ns/1ps
`include "check.svh"
module tb_rgb_display;
    parameter integer PATTERN=0;
    localparam integer HT=1192,VT=533;
    reg ref_clk=0,audio_clk=0,pll_reset=1,audio_reset=1;
    always #10 ref_clk=~ref_clk;
    always #8.138020833 audio_clk=~audio_clk;
    reg [31:0] active=32'h8000003f,held=32'h80000003;
    reg [1:0] timbre=2;
    reg busy=1,ready=1,error=0,underrun=0,ghost=0;
    reg [38:0] touch_status={1'b1,1'b0,1'b1,4'd1,16'd456,16'd123};
    reg [38:0] frame_touch;
    wire pclk,hs,vs,de;
    wire [5:0] r,g,b;
    reg [19:0] frame_status;
    reg [23:0] expected_color;
    reg [17:0] sampled_rgb;
    integer checks=0,i,px,py,visible=0,row=0,rows=0;
    reg expected_de;
    realtime previous_pclk=0,period;
    rgb_display #(.TEST_PATTERN(PATTERN)) dut(
        ref_clk,pll_reset,audio_clk,audio_reset,active,held,timbre,busy,ready,error,underrun,ghost,
        pclk,hs,vs,de,r,g,b,touch_status);
    always @(posedge pclk)begin
        if(dut.pixel_lock && !dut.pixel_reset)begin
            if(previous_pclk!=0)begin
                period=$realtime-previous_pclk;
                `CHECK(period>28.56 && period<28.59,"official PLL produces 35 MHz pixel clock")
            end
            previous_pclk=$realtime;
            sampled_rgb={r,g,b};#1;
            `CHECK({r,g,b}===sampled_rgb,"RGB stable across forwarded rising sampling edge")
        end else previous_pclk=0;
    end
    initial begin
        #200;pll_reset=0;
        wait(dut.pixel_lock);
        repeat(8)@(negedge dut.pixel_clk);
        `CHECK(!de && {r,g,b}==0,"audio reset holds LCD blank despite locked pixel PLL")
        audio_reset=0;
        wait(dut.status_valid);
        `CHECK(dut.pixel_status[11:0]=={6'd3,6'd7},"all voice bits including bit31 counted in atomic status")
        @(negedge dut.pixel_clk);
        while(!dut.frame_start)@(negedge dut.pixel_clk);
        frame_status=dut.pixel_status;
        frame_touch=dut.pixel_touch_status;
        @(posedge dut.pixel_clk);#1;
        `CHECK(dut.renderer.state===frame_status,"frame origin publishes atomic audio status")
        `CHECK(dut.renderer.touch_state===frame_touch,"frame origin publishes independent reference-domain touch snapshot")
        for(i=1;i<HT*VT;i=i+1)begin
            @(posedge dut.pixel_clk);
            px=dut.x;py=dut.y;expected_de=dut.de;
            #1;
            `CHECK(de===expected_de,"RGB666 connector DE aligned to registered pixel")
            `CHECK(hs && vs,"trial DE-only mode holds both sync pins inactive")
            `CHECK(dut.renderer.state===frame_status,"source changes never tear current UI frame")
            `CHECK(dut.renderer.touch_state===frame_touch,"reference touch changes never tear current UI frame")
            `CHECK((^{r,g,b})!==1'bx,"connector RGB is always defined")
            if(de)begin
                visible=visible+1;row=row+1;
                if(px==799)begin
                    `CHECK(row==800,"connector has exactly 800 samples per visible line")
                    row=0;rows=rows+1;
                end
                if(PATTERN && py==200)begin
                    case(px/100)
                        0:expected_color=24'hffffff;1:expected_color=24'hffff00;
                        2:expected_color=24'h00ffff;3:expected_color=24'h00ff00;
                        4:expected_color=24'hff00ff;5:expected_color=24'hff0000;
                        6:expected_color=24'h0000ff;7:expected_color=0;
                    endcase
                    if(px==0 || px==799)expected_color=24'he8eef5;
                    `CHECK({r,g,b}=={expected_color[23:18],expected_color[15:10],expected_color[7:2]},"RGB888 to connector RGB666 color and bit order")
                end
                if(!PATTERN && py==270 && px>=48 && px<752 && (px-48)%22<20)begin
                    expected_color=((px-48)/22<7)?24'h35d5cf:24'h101826;
                    `CHECK({r,g,b}=={expected_color[23:18],expected_color[15:10],expected_color[7:2]},"live audio count renders seven active slots")
                end
                if(!PATTERN && px==456 && py==123)
                    `CHECK({r,g,b}=={6'h3a,6'h3b,6'h3d},"reference-clock touch coordinate renders white RGB666 crosshair")
            end else `CHECK({r,g,b}==0,"connector blanks all porches")
            if(i==HT*250)begin
                fork
                    begin
                        @(negedge audio_clk);active=32'hffffffff;held=0;timbre=0;busy=0;ghost=1;
                    end
                    begin
                        @(negedge ref_clk);touch_status={1'b1,1'b0,1'b0,4'd0,16'd0,16'd0};
                    end
                join_none
            end
        end
        `CHECK(visible==800*480 && rows==480 && row==0,"full connector frame is exactly 800x480")
        @(posedge dut.pixel_clk);#1;
        `CHECK(dut.renderer.state[18:0]=={1'b1,1'b0,1'b0,1'b1,1'b0,2'd0,6'd0,6'd32},"next frame commits new mode, flags and counts together")
        `CHECK(dut.renderer.touch_state===touch_status,"next frame commits touch release atomically")
        // Force a loss of LOCK in the official PLL connection; don't fake a PLL model.
        force dut.pixel_lock=0;#1;
        `CHECK(!de && {r,g,b}==0,"loss of LOCK blanks without requiring another pixel edge")
        repeat(8)@(negedge ref_clk);
        release dut.pixel_lock;
        wait(!dut.pixel_reset);
        wait(dut.status_valid);
        `CHECK(dut.pixel_status[5:0]==32,"status transfer recovers after PLL lock loss")
        #3;pll_reset=1;#1;
        `CHECK(!de && {r,g,b}==0,"reset blanks connector asynchronously")
        $display("PASS tb_rgb_display checks=%0d pattern=%0d",checks,PATTERN);$finish;
    end
    initial begin #60000000;$fatal(1,"display timeout");end
endmodule
