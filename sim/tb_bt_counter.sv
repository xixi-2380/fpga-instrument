`timescale 1ns/1ps
// Boundary coverage for the segmented carry chains; protocol behavior is
// independently covered by the full upload/player/library regressions.
module tb_bt_counter;
 reg clk=0,rst=1;always #5 clk=~clk;
 wire [31:0] position;integer checks=0;reg [31:0] random_state=32'h5a25c0de;
 bt_score_player #(.MAX_NOTES(16),.VOICES(16)) player(
 .clk(clk),.rst(rst),.command_valid(1'b0),.command(2'd0),.note_count(16'd0),
 .song_duration(32'd0),.ram_data(64'd0),.event_ready(1'b1),.position_ms(position));
 spi_nor_flash flash(.clk(clk),.rst(rst),.request_valid(1'b0),.operation(2'd0),
 .address(24'd0),.length(9'd0),.writes_enabled(1'b0),.buffer_write(1'b0),
 .buffer_index(8'd0),.buffer_wdata(8'd0),.read_index(8'd0),.miso(1'b1));
 flash_song_library lib_dut(.clk(clk),.rst(rst),.request_valid(1'b0),.command(2'd0),
 .song_index(5'd0),.song_name(56'd0),.lookup_index(5'd0),.ram_valid(1'b0),.ram_count(16'd0),
 .ram_duration(32'd0),.ram_crc(32'd0),.storage_ready(1'b0),.storage_rdata(64'd0),
 .storage_done(1'b0),.storage_error(8'd0),.upload_active(1'b0),.flash_initialized(1'b0),
 .flash_supported(1'b0),.flash_ready(1'b0),.flash_done(1'b0),.flash_error(8'd0),.read_data(8'd0));
 timbre_control control(.clk(clk),.rst(rst),.buttons_n(4'h6),.ui_action_valid(1'b1),
 .ui_action(6'd13),.cfg_ready(1'b1));
 task check_position(input [31:0] value);begin
  @(negedge clk);player.position_ms=value;player.ms_counter=49999;
  player.state=player.WAIT_TICK;player.play_state=1;player.fault_pending=0;
  @(posedge clk);#1;checks++;
  if(position!==(value+32'd1))$fatal(1,"32-bit position carry failed %h -> %h",value,position);
 end endtask
 task check_generation(input [31:0] value);begin
  @(negedge clk);lib_dut.generation=value;
  @(posedge clk);#1;checks++;
  if(lib_dut.writing_generation!==(value+32'd1))$fatal(1,"directory generation wrap failed %h",value);
 end endtask
 task check_hold(input [25:0] value);reg terminal;reg [25:0] expected;begin
  terminal=value==49151999;expected=terminal?value:value+26'd1;
  @(negedge clk);control.stable_buttons=6;control.press_event=0;control.release_event=0;
  control.menu_holding=1;control.menu_fired=0;control.menu_hold=value;control.menu_terminal=terminal;control.menu_mode=0;
  control.holding=1;control.long_fired=0;control.hold_count=value;control.effect_terminal=terminal;control.effect_mode=0;
  control.selected=0;control.effects_enabled=0;
  @(posedge clk);#1;checks+=3;
  if(control.menu_hold!==expected || control.hold_count!==expected)$fatal(1,"long hold carry failed %h",value);
  if(control.menu_terminal!==(expected==49151999) || control.effect_terminal!==(expected==49151999))$fatal(1,"terminal lookahead shifted a cycle");
  if(control.selected!==(terminal?3'd0:3'd3) || control.menu_mode!==terminal || control.long_fired!==terminal)
   $fatal(1,"long press/UI arbitration changed at production threshold");
 end endtask
 task check_timeout(input [25:0] value);reg [25:0] expected;begin
  @(negedge clk);flash.state=flash.X_WAIT;flash.timeout_count=value;
  expected=value<50000000 ? value+26'd1 : value;
  @(posedge clk);#1;checks++;
  if(flash.timeout_count!==expected)$fatal(1,"timeout carry/saturation failed %h",value);
 end endtask
 initial begin
  #12 rst=0;
  check_position(0);check_position(255);check_position(65535);check_position(16777215);
  check_position(32'h7fffffff);check_position(32'hfffffffe);check_position(32'hffffffff);
  for(integer i=0;i<2000;i++)begin
   random_state=(random_state<<1)^(random_state[31]?32'h04c11db7:32'd0);
   check_position(random_state);
  end
  check_timeout(0);check_timeout(255);check_timeout(65535);check_timeout(16777215);
  check_timeout(49999998);check_timeout(49999999);check_timeout(50000000);check_timeout(26'h3ffffff);
  check_generation(0);check_generation(255);check_generation(65535);check_generation(16777215);check_generation(32'hffffffff);
  check_hold(0);check_hold(255);check_hold(65535);check_hold(16777215);
  check_hold(49151997);check_hold(49151998);check_hold(49151999);
  $display("PASS tb_bt_counter checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"counter timeout");end
endmodule
