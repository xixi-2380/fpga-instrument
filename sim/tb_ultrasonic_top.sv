`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
// 50MHz reference domain -> atomic CDC -> 61.44MHz PCM -> frame buffer/I2S.
// TEST-ONLY timing compression: sensor CLK_HZ parameter is divided by 50;
// Echo pulse/delay time is divided by the same factor. Audio clocks stay real.
// Production 50MHz sensor timing is separately tested with tb_ultrasonic_range.
// Gain slew=1 here; production slew=4 is separately tested at the gain unit.
// PLLs are explicitly behavioral substitutes; this is NOT STA/vendor validation.
module tb_ultrasonic_top;
    parameter integer RANGE_CLK_HZ=1000000,GAIN_SLEW_SAMPLES=1;
    localparam integer SENSOR_TIME_SCALE=50000000/RANGE_CLK_HZ;
    reg clk=0,rst=1,echo=0; always #10 clk=~clk;
    reg [15:0] pressed=0;
    tri [3:0] columns,reference_columns;
    wire [3:0] selected,reference_selected,rows,reference_rows;
    wire trig,reference_trig;
    integer checks=0,frames=0,pcm_checks=0,unity_checks=0,zero_checks=0;
    integer score_on=0,score_off=0;
    reg check_unity=0,check_mute=0;
    keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.ULTRASONIC_ENABLE(1),
        .SCORE_BEAT_FRAMES(4),.LOCK_N(16),.MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.RELEASE(2),
        .SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2)) dut(
        .clk(clk),.rst(rst),.board_buttons_n(4'hf),.key_row(rows),.key_col(columns),
        .ultrasonic_echo(echo),.ultrasonic_trig(trig));
    keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.ULTRASONIC_ENABLE(0),
        .SCORE_BEAT_FRAMES(4),.LOCK_N(16),.MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.RELEASE(2),
        .SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2)) reference_audio(
        .clk(clk),.rst(rst),.board_buttons_n(4'hf),.key_row(reference_rows),.key_col(reference_columns),
        .ultrasonic_echo(1'b0),.ultrasonic_trig(reference_trig));
    defparam dut.ultrasonic_on.range_reader.CLK_HZ=RANGE_CLK_HZ;
    defparam dut.sound.MASTER_GAIN_SLEW_SAMPLES=GAIN_SLEW_SAMPLES;
    for(genvar k=0;k<4;k=k+1)begin
        assign selected[k]=(columns[k]===1'b0);
        assign reference_selected[k]=(reference_columns[k]===1'b0);
    end
    passive_matrix_model keyboard(pressed,selected,rows);
    passive_matrix_model reference_keyboard(pressed,reference_selected,reference_rows);
    integer pending=0,expected=0,next_expected,incoming;
    reg [8:0] captured_gain=256;
    always @(posedge clk)begin
        if(!dut.ultrasonic_on.gain_bridge.source_reset &&
           !dut.ultrasonic_on.gain_bridge.acknowledge && dut.ultrasonic_on.gain_bridge.request_sync[1])
            captured_gain=dut.ultrasonic_on.gain_ref;
    end
    always @(posedge dut.audio_clk)begin
        if(dut.audio_reset!==1'b0)begin pending=0;expected=0;end
        else begin
            // Independent signed integer arithmetic, evaluated before the gain step.
            incoming=dut.sound.effect_valid;
            next_expected=($signed(dut.sound.effect_sample)*int'(dut.sound.master_gain_current)) >>> 8;
            if(dut.frame_ce)frames=frames+1;
            if(dut.note_valid && dut.note_ready && dut.score_busy)begin
                if(dut.note_on)score_on=score_on+1;else score_off=score_off+1;
            end
            if(check_unity)begin
                `CHECK(dut.MAX_BCLK===reference_audio.MAX_BCLK && dut.MAX_LRCLK===reference_audio.MAX_LRCLK && dut.MAX_DIN===reference_audio.MAX_DIN,"unity preserves complete serial output against disabled reference")
                unity_checks=unity_checks+1;
            end
            #0.001;
            `CHECK(!dut.underrun && !dut.score_error,"gesture cannot underrun or corrupt score")
            `CHECK(dut.sound.output_valid===pending,"master gain has defined pipeline latency")
            if(pending)begin
                `CHECK($signed(dut.sound.output_sample)===expected,"end-to-end post-FX gain sample matches reference")
                pcm_checks=pcm_checks+1;
            end
            if(dut.ultrasonic_on.gain_update)
                `CHECK(dut.ultrasonic_on.gain_audio===captured_gain,"atomic gain snapshot equals held source payload")
            if(check_mute && dut.frame_ce)begin
                `CHECK(dut.gate && dut.sound.frame_l==0 && dut.sound.frame_r==0,"far gesture mutes both channels while retaining held note")
                zero_checks=zero_checks+1;
            end
            pending=incoming;expected=next_expected;
        end
    end
    task more_frames(input integer n);integer target;begin
        target=frames+n;wait(frames>=target);@(negedge dut.audio_clk);
    end endtask
    task response(input integer cm);begin
        @(posedge trig);@(negedge trig);#(300000/SENSOR_TIME_SCALE);echo=1;
        #(cm*58000/SENSOR_TIME_SCALE);echo=0;
        @(posedge dut.ultrasonic_on.sample_valid);#1;
        `CHECK(dut.ultrasonic_on.distance_cm==cm,"physical Echo pulse reaches distance decoder")
    end endtask
    task reach_gain(input integer expected_gain);begin
        wait(dut.ultrasonic_gain==expected_gain);
        wait(dut.sound.master_gain_current==expected_gain);
        more_frames(4);
        `CHECK(dut.ultrasonic_on.gain_valid && dut.sound.master_gain_current==expected_gain,"filtered target crosses CDC and slew completes")
    end endtask
    initial begin
        #213;rst=0;
        wait(dut.input_ready);wait(!dut.score_busy);more_frames(6);
        `CHECK(score_on==42 && score_off==42,"all 84 automatic score events survive added gain path")
        `CHECK(!reference_trig && dut.ultrasonic_gain==256,"disabled module parks Trig; startup stays at unity")
        pressed=16'h0001;wait(dut.gate);more_frames(10);
        check_unity=1;more_frames(20);check_unity=0;
        response(5);reach_gain(256);
        response(20);response(20);reach_gain(146);
        `CHECK(dut.gate && reference_audio.gate,"volume control cannot steal note ownership")
        response(40);response(40);reach_gain(0);
        check_mute=1;more_frames(10);
        @(posedge trig);@(posedge dut.ultrasonic_on.sample_done);#1;
        `CHECK(!dut.ultrasonic_on.sample_valid && dut.ultrasonic_on.error_code==1,"missing Echo is an invalid attempt")
        `CHECK(dut.ultrasonic_on.gain_ref==0 && dut.sound.master_gain_current==0,"invalid attempt retains last mute gain")
        check_mute=0;
        response(5);response(5);reach_gain(256);
        check_unity=1;more_frames(20);check_unity=0;
        pressed=0;wait(!dut.gate);more_frames(10);
        `CHECK(dut.voice_active==0 && dut.sound.frame_l==0 && dut.sound.frame_r==0,"note releases and returns to exact zero after hand movement")
        // USR while a measurement is active must reset both clock domains cleanly.
        @(posedge trig);@(negedge trig);#(300000/SENSOR_TIME_SCALE);echo=1;#(100000/SENSOR_TIME_SCALE);
        rst=1;echo=0;#213;
        `CHECK(dut.ultrasonic_gain==256 && !trig && !dut.gate,"USR cancels in-flight measurement and held voice")
        rst=0;wait(dut.input_ready);wait(!dut.score_busy);more_frames(6);
        `CHECK(score_on==84 && score_off==84 && !dut.underrun,"score restarts with matched releases and no stale gain")
        `CHECK(pcm_checks>1000 && unity_checks>1000 && zero_checks>=10,"exercise real audio and serial traffic")
        $display("PASS tb_ultrasonic_top checks=%0d pcm=%0d unity_serial=%0d muted_frames=%0d score_on=%0d score_off=%0d sensor_time_scale=%0d gain_slew=%0d",checks,pcm_checks,unity_checks,zero_checks,score_on,score_off,SENSOR_TIME_SCALE,GAIN_SLEW_SAMPLES);$finish;
    end
    initial begin #1000000000;$fatal(1,"ultrasonic integration timeout");end
endmodule
