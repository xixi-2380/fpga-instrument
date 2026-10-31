`timescale 1ns/1ps
// Exhaust the complete16-bit length domain, including invalid0/1/256+.
// Compare actual core wires against the original unsigned32-bit expressions.
module tb_bt_packet_math;
 reg [15:0] length_value=0;reg format=0;
 wire [4:0] record_size=format ? 5'd12 : 5'd8;
 wire [5:0] old_count=format ? (length_value-2)/12 : (length_value-2)/8;
 wire old_invalid=length_value<record_size+2 || length_value>254 || (length_value-2)%record_size!=0;
 bluetooth_score_core #(.MAX_NOTES(4)) dut(.clk(1'b0),.rst(1'b0),
  .rx_valid(1'b0),.rx_data(8'd0),.rx_fault(1'b0),.tx_ready(1'b0),.event_ready(1'b0),
  .local_valid(1'b0),.local_command(2'd0),.storage_lock(1'b0),.storage_write(1'b0),.storage_invalidate(1'b0),
  .storage_address(2'd0),.storage_wdata(96'd0),.storage_import(1'b0),.storage_count(16'd0),.storage_crc(32'd0),
  .extension_ready(1'b0),.extension_response_valid(1'b0),.extension_response_length(5'd0),.extension_response(160'd0),.storage_format(1'b0));
 integer checks=0;
 initial begin
 force dut.len=length_value;force dut.song_format=format;
 for(integer f=0;f<2;f=f+1)begin
 format=f;
 for(integer n=0;n<65536;n=n+1)begin
 length_value=n;#1;
 if(dut.incoming_count!==old_count || dut.data_length_invalid!==old_invalid)
  $fatal(1,"packet arithmetic format=%0d len=%0d",f,n);
 checks=checks+1;
 end end
 $display("PASS tb_bt_packet_math checks=%0d",checks);$finish;
 end
endmodule
