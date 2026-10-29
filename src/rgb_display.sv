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
    input wire visual_sample_valid,input wire signed [15:0] visual_sample,input wire [35:0] visual_notes,
    input wire score_busy,audio_ready,score_error,underrun,ghost,
    output wire lcd_clk,
    (* syn_preserve=1 *) output reg lcd_hs,lcd_vs,
    output reg lcd_en,
    output reg [5:0] lcd_r,lcd_g,lcd_b,
    input wire menu_mode,effects_enabled,input wire [1:0] effect_mode,
    input wire [6:0] echo_percent,room_percent,depth_percent,input wire [4:0] tremolo_rate_hz,
    input wire [6:0] volume_percent,
    input wire touch_enabled,touch_ui_enabled,touch_ready_status,touch_error_status,
    input wire [145:0] more_status,
    input wire latency_valid,input wire [19:0] latency_bcd,input wire [33:0] ultrasonic_status,
    input wire [16:0] encoder_status,input wire [2:0] keypad_online,input wire [2591:0] pcb_status,output wire pcb_visible,input wire [3:0] sustain_time_thousands
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
    function automatic [3:0] count_octet(input [7:0] bitmap);
        reg [1:0] p0,p1,p2,p3;reg [2:0] q0,q1;
        begin
            p0={1'b0,bitmap[0]}+{1'b0,bitmap[1]};p1={1'b0,bitmap[2]}+{1'b0,bitmap[3]};
            p2={1'b0,bitmap[4]}+{1'b0,bitmap[5]};p3={1'b0,bitmap[6]}+{1'b0,bitmap[7]};
            q0={1'b0,p0}+{1'b0,p1};q1={1'b0,p2}+{1'b0,p3};
            count_octet={1'b0,q0}+{1'b0,q1};
        end
    endfunction
    wire [15:0] active_groups,held_groups;
    for(genvar j=0;j<4;j=j+1)begin: count_groups
        assign active_groups[j*4+:4]=count_octet(active_map[j*8+:8]);
        assign held_groups[j*4+:4]=count_octet(held_map[j*8+:8]);
    end
    reg [3:0] active_oct[0:3],held_oct[0:3];
    reg [5:0] active_count,held_count;
    // Passive statistics need not traverse all reduction levels before the
    // snapshot capture. Two audio clocks do not stall the note/audio path.
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)begin
            active_count<=0;held_count<=0;
            for(integer j=0;j<4;j=j+1)begin active_oct[j]<=0;held_oct[j]<=0;end
        end else begin
            for(integer j=0;j<4;j=j+1)begin
                active_oct[j]<=active_groups[j*4+:4];
                held_oct[j]<=held_groups[j*4+:4];
            end
            active_count<=({2'd0,active_oct[0]}+{2'd0,active_oct[1]})+({2'd0,active_oct[2]}+{2'd0,active_oct[3]});
            held_count<=({2'd0,held_oct[0]}+{2'd0,held_oct[1]})+({2'd0,held_oct[2]}+{2'd0,held_oct[3]});
        end
    end
    wire [19:0] legacy_status={TEST_PATTERN!=0,ghost,underrun,score_error,audio_ready,
        score_busy,selected_timbre[1:0],held_count,active_count};
    wire [1023:0] waveform;wire [7:0] peak;wire window_valid;
    audio_visualizer monitor(audio_clk,audio_reset,visual_sample_valid,visual_sample,waveform,peak,window_valid);
    wire [63:0] settings_status={sustain_time_thousands[1:0],tremolo_rate_hz[4],volume_percent,selected_timbre[2],touch_error_status,touch_ready_status,touch_ui_enabled,touch_enabled,
        tremolo_rate_hz[3:0],depth_percent,room_percent,echo_percent,effects_enabled,effect_mode,menu_mode,legacy_status};
    wire [20:0] latency_status=latency_valid===1'b1 ? {1'b1,latency_bcd} : 21'd0;
    // Preserve all original1112 bits; append a small atomic measurement field.
    wire [33:0] sensor_status=(ultrasonic_status[33]===1'b0 || ultrasonic_status[33]===1'b1) ? ultrasonic_status : 34'd0;
    wire [16:0] knobs=(^encoder_status===1'bx)?{12'h150,5'd0}:encoder_status;
    wire [2:0] online=(^keypad_online===1'bx)?3'd0:keypad_online;
    wire [1206:0] source_status={online,visual_notes[35:16],knobs,sensor_status,latency_status,waveform,peak,visual_notes[15:0],settings_status};
    wire [1206:0] pixel_status;
    wire status_valid,update_pulse;
    rgb_status_cdc #(.WIDTH(1207)) status_bridge(audio_clk,pixel_clk,common_reset,source_status,
        pixel_status,status_valid,update_pulse);
    wire [10:0] x,y;
    wire de,hs,vs,frame_start;
    rgb_scan_timing #(.H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_FRONT(H_FRONT),
        .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_FRONT(V_FRONT),
        .HS_ACTIVE(HS_ACTIVE),.VS_ACTIVE(VS_ACTIVE),.DE_ONLY(DE_ONLY))
        scan(pixel_clk,pixel_reset,x,y,de,hs,vs,frame_start);
    wire [23:0] rgb;
    wire [145:0] pixel_more;wire more_valid,more_update;
    rgb_status_cdc #(.WIDTH(146)) more_bridge(audio_clk,pixel_clk,common_reset,more_status,pixel_more,more_valid,more_update);
    wire [2591:0] pixel_pcb;wire pcb_valid,pcb_update;
    wire [2591:0] safe_pcb=pcb_status[2560]===1'b1 ? pcb_status : 2592'd0;
    rgb_status_cdc #(.WIDTH(2592)) pcb_bridge(audio_clk,pixel_clk,common_reset,safe_pcb,pixel_pcb,pcb_valid,pcb_update);
    wire renderer_pcb_visible;wire visible_valid,visible_update;
    rgb_status_cdc #(.WIDTH(1)) pcb_visibility_bridge(pixel_clk,audio_clk,common_reset,
        renderer_pcb_visible,pcb_visible,visible_valid,visible_update);
    wire rendered_de,rendered_hs,rendered_vs;
    reg [10:0] render_x,render_y;
    reg render_de,render_hs,render_vs,render_frame_start;
    always @(posedge pixel_clk)begin
        if(pixel_reset)begin render_x<=0;render_y<=0;render_de<=0;render_hs<=!HS_ACTIVE[0];render_vs<=!VS_ACTIVE[0];render_frame_start<=0;end
        else begin render_x<=x;render_y<=y;render_de<=de;render_hs<=hs;render_vs<=vs;render_frame_start<=frame_start;end
    end
    rgb_ui_renderer renderer(pixel_clk,pixel_reset,render_frame_start,status_valid,pixel_status,
        render_x,render_y,render_de,render_hs,render_vs,rgb,rendered_de,rendered_hs,rendered_vs,pixel_more,pixel_pcb,renderer_pcb_visible);
    // Only the output pin is phase-inverted. It never clocks any internal RTL.
    // At default phase, a panel rising edge has half a pixel period of setup.
    ODDR pixel_clock_forward(.Q0(lcd_clk),.Q1(),.D0(!PCLK_INVERT[0] && !pixel_reset),
        .D1(PCLK_INVERT[0] && !pixel_reset),.TX(1'b0),.CLK(pixel_clk));
    // synthesis translate_off
    GSR GSR(1'b1);
    // synthesis translate_on
    // Final connector registers remove combinational reset muxes at the pads.
    // Async assertion still blanks safely when the pixel clock stops.
    always @(posedge pixel_clk or posedge pixel_reset)begin
        if(pixel_reset)begin
            lcd_en<=0;lcd_hs<=!HS_ACTIVE[0];lcd_vs<=!VS_ACTIVE[0];
            lcd_r<=0;lcd_g<=0;lcd_b<=0;
        end else begin
            lcd_en<=rendered_de;lcd_hs<=rendered_hs;lcd_vs<=rendered_vs;
            lcd_r<=rgb[23:18];lcd_g<=rgb[15:10];lcd_b<=rgb[7:2];
        end
    end
`ifndef SYNTHESIS
    initial if(VOICES<1 || VOICES>32)$fatal(1,"rgb_display supports 1..32 voices");
`endif
endmodule

