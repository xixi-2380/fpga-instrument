`timescale 1ns/1ps
// Trial DE-only profile based on Sipeed's TangMega-138KPro 800x480 example.
// This is NOT a timing specification for the user's QTB203V121C panel.
// Existing audio PLLs are separate and unchanged.
module rgb_display #(
    parameter integer VOICES=32,TEST_PATTERN=0,PCLK_INVERT=1,
    H_SYNC=0,H_BACK=182,H_FRONT=210,V_SYNC=0,V_BACK=8,V_FRONT=45,
    HS_ACTIVE=0,VS_ACTIVE=0,DE_ONLY=1
)(
    input wire ref_clk,pll_reset,audio_clk,audio_reset,
    input wire [VOICES-1:0] voice_active,voice_held,
    input wire [2:0] selected_timbre,
    input wire visual_sample_valid,input wire signed [15:0] visual_sample,input wire [15:0] visual_notes,
    input wire score_busy,audio_ready,score_error,underrun,ghost,
    output wire lcd_clk,lcd_hs,lcd_vs,lcd_en,
    output wire [5:0] lcd_r,lcd_g,lcd_b,
    input wire menu_mode,effects_enabled,input wire [1:0] effect_mode,
    input wire [6:0] echo_percent,room_percent,depth_percent,input wire [3:0] tremolo_rate_hz,
    input wire touch_enabled,touch_ui_enabled,touch_ready_status,touch_error_status,
    input wire language_zh,input wire [1:0] theme_id
);
    wire pixel_clk,pixel_lock,pixel_reset;
    wire common_reset=pll_reset || !pixel_lock || audio_reset;
    // 50 * 21 / 30 = 35 MHz; independent third PLL, no audio clock edits.
    PLL #(.FCLKIN("50"),.IDIV_SEL(1),.FBDIV_SEL(1),.MDIV_SEL(21),
        .ODIV0_SEL(30),.CLKFB_SEL("INTERNAL")) pixel_pll(
        .CLKIN(ref_clk),.CLKOUT0(pixel_clk),.CLKOUT1(),.CLKOUT2(),.CLKOUT3(),
        .CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.CLKFBOUT(),.LOCK(pixel_lock),.RESET(pll_reset),
        .CLKFB(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .ENCLK0(1'b1),.ENCLK1(1'b0),.ENCLK2(1'b0),.ENCLK3(1'b0),
        .ENCLK4(1'b0),.ENCLK5(1'b0),.ENCLK6(1'b0),
        .FBDSEL(6'b0),.IDSEL(6'b0),.MDSEL(7'b0),.MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0),.ODSEL0_FRAC(3'b0),.ODSEL1(7'b0),.ODSEL2(7'b0),
        .ODSEL3(7'b0),.ODSEL4(7'b0),.ODSEL5(7'b0),.ODSEL6(7'b0),
        .DT0(4'b0),.DT1(4'b0),.DT2(4'b0),.DT3(4'b0),
        .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),
        .SSCON(1'b0),.SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),
        .ICPSEL(6'b0),.LPFRES(3'b0),.LPFCAP(2'b0));
    reset_sync pixel_reset_sync(pixel_clk,common_reset,pixel_reset);

    // Balanced reduction instead of a 32-stage serial count in the audio domain.
    function automatic [5:0] count_voices(input [31:0] bitmap);
        reg [1:0] pair_count[0:15];
        reg [2:0] quad_count[0:7];
        reg [3:0] oct_count[0:3];
        reg [4:0] half_count[0:1];
        integer i;
        begin
            for(i=0;i<16;i=i+1)pair_count[i]={1'b0,bitmap[i*2]}+{1'b0,bitmap[i*2+1]};
            for(i=0;i<8;i=i+1)quad_count[i]={1'b0,pair_count[i*2]}+{1'b0,pair_count[i*2+1]};
            for(i=0;i<4;i=i+1)oct_count[i]={1'b0,quad_count[i*2]}+{1'b0,quad_count[i*2+1]};
            for(i=0;i<2;i=i+1)half_count[i]={1'b0,oct_count[i*2]}+{1'b0,oct_count[i*2+1]};
            count_voices={1'b0,half_count[0]}+{1'b0,half_count[1]};
        end
    endfunction
    wire [31:0] active_map=voice_active,held_map=voice_held;
    wire [19:0] legacy_status={TEST_PATTERN!=0,ghost,underrun,score_error,audio_ready,
        score_busy,selected_timbre[1:0],count_voices(held_map),count_voices(active_map)};
    wire [1023:0] waveform;wire [7:0] peak;wire window_valid;
    audio_visualizer monitor(audio_clk,audio_reset,visual_sample_valid,visual_sample,waveform,peak,window_valid);
    wire [63:0] settings_status={7'd0,language_zh,theme_id,selected_timbre[2],touch_error_status,touch_ready_status,touch_ui_enabled,touch_enabled,
        tremolo_rate_hz,depth_percent,room_percent,echo_percent,effects_enabled,effect_mode,menu_mode,legacy_status};
    wire [1111:0] source_status={waveform,peak,visual_notes,settings_status};
    wire [1111:0] pixel_status;
    wire status_valid,update_pulse;
    rgb_status_cdc #(.WIDTH(1112)) status_bridge(audio_clk,pixel_clk,common_reset,source_status,
        pixel_status,status_valid,update_pulse);
    wire [10:0] x,y;
    wire de,hs,vs,frame_start;
    rgb_scan_timing #(.H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_FRONT(H_FRONT),
        .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_FRONT(V_FRONT),
        .HS_ACTIVE(HS_ACTIVE),.VS_ACTIVE(VS_ACTIVE),.DE_ONLY(DE_ONLY))
        scan(pixel_clk,pixel_reset,x,y,de,hs,vs,frame_start);
    wire [23:0] rgb;
    wire rendered_de,rendered_hs,rendered_vs;
    rgb_ui_renderer renderer(pixel_clk,pixel_reset,frame_start,status_valid,pixel_status,
        x,y,de,hs,vs,rgb,rendered_de,rendered_hs,rendered_vs);
    // Only the output pin is phase-inverted. It never clocks any internal RTL.
    // At default phase, a panel rising edge has half a pixel period of setup.
    assign lcd_clk=PCLK_INVERT ? ~pixel_clk : pixel_clk;
    // Ninth renderer stage plus one output stage. Preserve half-cycle PCLK
    // sampling and immediate asynchronous blanking even if pixel clock stops.
    reg [23:0] connector_rgb;
    reg connector_de,connector_hs,connector_vs;
    always @(posedge pixel_clk or posedge pixel_reset)begin
        if(pixel_reset)begin
            connector_rgb<=0;connector_de<=0;
            connector_hs<=!HS_ACTIVE[0];connector_vs<=!VS_ACTIVE[0];
        end else begin
            connector_rgb<=rgb;connector_de<=rendered_de;
            connector_hs<=rendered_hs;connector_vs<=rendered_vs;
        end
    end
    assign lcd_en=connector_de;
    assign lcd_hs=connector_hs;
    assign lcd_vs=connector_vs;
    assign lcd_r=connector_rgb[23:18];
    assign lcd_g=connector_rgb[15:10];
    assign lcd_b=connector_rgb[7:2];
`ifndef SYNTHESIS
    initial if(VOICES<1 || VOICES>32)$fatal(1,"rgb_display supports 1..32 voices");
`endif
endmodule

