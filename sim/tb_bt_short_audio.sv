`timescale 1ns/1ps
// Production 50MHz scheduler,61.44MHz/48kHz audio,32 render voices and64
// limiter window. Three1ms records are shorter than total lookahead latency.
module tb_bt_short_audio;
 reg clk=0,rst=1,command_valid=0;always #10 clk=~clk;
 reg [63:0] ram=0;tri [3:0] columns;
 integer checks=0,ons=0,offs=0,staged_tag=0,expected_tag=0;
 integer tag_queue[0:62],heard[0:3];realtime started=0;
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.LOCK_N(16),
 .MUTE(4),.FADE(4),.ATTACK(0),.DECAY(0),.SUSTAIN(65536),.RELEASE(0)) dut(
 .clk(clk),.rst(rst),.bt_rx(1'b1),.board_buttons_n(4'hf),.keypad_int_n(3'b111),.ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 always @(posedge clk)case(dut.bluetooth_on.link.core.player_address)
  0:ram<={16'd1,8'd127,8'd60,32'd0};
  1:ram<={16'd1,8'd127,8'd64,32'd1};
  default:ram<={16'd1,8'd127,8'd67,32'd2};
 endcase
 always @(posedge dut.audio_clk)begin
  if(rst || dut.audio_reset!==1'b0 || dut.bt_output_flush)begin
   staged_tag=0;expected_tag=0;for(integer i=0;i<63;i++)tag_queue[i]=0;
  end else begin
   check(!dut.underrun,"production conditioner supplies every I2S frame");
   if(dut.bt_valid && dut.bt_ready)begin
    if(dut.bt_note_on)begin
     check($realtime-started-ons*1000000.0<250000,"real32-voice On handshake within0.25ms");ons++;
    end else offs++;
   end
   if(dut.sound.frame_ce)begin
    expected_tag=tag_queue[0];for(integer i=0;i<62;i++)tag_queue[i]=tag_queue[i+1];
    tag_queue[62]=staged_tag;staged_tag=0;
   end
   if(dut.sound.effect_valid && !dut.sound.engine_reset)begin
    case(dut.sound.automatic_pitch[0])60:staged_tag=1;64:staged_tag=2;67:staged_tag=3;default:staged_tag=0;endcase
   end
   if(dut.sound.limited_valid && dut.sound.limited_sample!=0)begin
    check(expected_tag>0 && expected_tag<=3,"delayed nonzero audio retains its originating note interval");
    heard[expected_tag]++;
   end
  end
 end
 always @(dut.bluetooth_on.link.core.play_state)if(dut.bluetooth_on.link.core.play_state==1)started=$realtime;
 initial begin
  for(integer i=0;i<4;i++)heard[i]=0;
  force dut.bluetooth_on.link.core.player_valid=command_valid;
  force dut.bluetooth_on.link.core.player_command=2'd0;
  force dut.bluetooth_on.link.core.total_notes=16'd3;
  force dut.bluetooth_on.link.core.duration_ms=32'd3;
  force dut.bluetooth_on.link.core.ram_data=ram;
  #100 rst=0;wait(dut.input_ready);repeat(8)@(negedge clk);
  command_valid=1;wait(dut.bluetooth_on.link.core.player_ready);@(negedge clk);command_valid=0;
  wait(ons==3);wait(!dut.bluetooth_on.link.core.manual_inhibit && !dut.bt_inhibit);
  repeat(1000)@(negedge clk);
  check(offs==3 && dut.bluetooth_on.link.core.position_ms==3,"all short records end without scheduler fault");
  check(heard[1]>10 && heard[2]>10 && heard[3]>10,"each1ms note survives subsequent On and final drain");
  check(!dut.bluetooth_on.link.scheduler_fault && dut.visual_sample==0 && dut.sound.tx.latched_l==0 && dut.sound.tx.latched_r==0,"natural end completes only after actual zeroed serial output");
  $display("PASS tb_bt_short_audio checks=%0d note_samples=%0d/%0d/%0d",checks,heard[1],heard[2],heard[3]);$finish;
 end
 initial begin #15000000;$fatal(1,"short audio timeout ons=%0d offs=%0d",ons,offs);end
endmodule
