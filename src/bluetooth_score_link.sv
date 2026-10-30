`timescale 1ns/1ps
// Optional serial link, not instantiated by keyboard_top until wiring is known.
module bluetooth_score_link #(
 parameter integer CLOCK_HZ=50000000,BAUD=9600,MAX_NOTES=1024,MAX_VOICES=1,LIBRARY_EXTENSION=0,
 NOTE_MIN=48,NOTE_MAX=83,MAX_SONG_MS=3600000,FIFO_DEPTH=512)(
 input wire clk,rst,uart_rx_pin,output wire uart_tx_pin,
 output wire event_valid,input wire event_ready,output wire [1:0] event_kind,
 output wire [6:0] event_id,event_pitch,event_velocity,
 output wire song_valid,upload_active,output wire [1:0] play_state,output wire [31:0] position_ms,
 output wire manual_inhibit,output wire [7:0] last_error,output wire [15:0] received_notes,total_notes,
 output reg overflow,framing_fault,output wire bad_frame,scheduler_fault,
 input wire local_valid,input wire [1:0] local_command,output wire local_ready,local_done,output wire [7:0] local_error,
 input wire storage_lock,output wire storage_ready,input wire storage_write,storage_invalidate,
 input wire [(MAX_NOTES>1?$clog2(MAX_NOTES):1)-1:0] storage_address,input wire [95:0] storage_wdata,output wire [95:0] storage_rdata,
 input wire storage_import,input wire [15:0] storage_count,input wire [31:0] storage_crc,
 output wire storage_done,output wire [7:0] storage_error,output wire [31:0] song_duration,song_crc,
 output wire extension_valid,input wire extension_ready,output wire [7:0] extension_command,
 output wire [8:0] extension_length,output wire [63:0] extension_payload,
 input wire extension_response_valid,output wire extension_response_ready,
 input wire [4:0] extension_response_length,input wire [159:0] extension_response,input wire performance_lock,input wire storage_format,output wire song_format,output wire [4:0] event_timbre,output wire event_legacy);
 localparam integer PW=$clog2(FIFO_DEPTH),CW=$clog2(FIFO_DEPTH+1);
 wire [7:0] data;wire valid,rx_error,ready,tx_valid,tx_ready;wire [7:0] tx_data;
 reg [7:0] fifo[0:FIFO_DEPTH-1];reg [PW-1:0] wr,rd;reg [CW-1:0] count;
 wire pop=count!=0&&ready;
 wire overflow_now=valid&&count==FIFO_DEPTH&&!pop;
 wire fault=rx_error||overflow_now;
 uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) rx(clk,rst,uart_rx_pin,data,valid,rx_error);
 uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) tx(clk,rst,tx_data,tx_valid,tx_ready,uart_tx_pin);
 bluetooth_score_core #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD),.MAX_NOTES(MAX_NOTES),.MAX_VOICES(MAX_VOICES),.LIBRARY_EXTENSION(LIBRARY_EXTENSION),
  .NOTE_MIN(NOTE_MIN),.NOTE_MAX(NOTE_MAX),.MAX_SONG_MS(MAX_SONG_MS)) core(
  .clk(clk),.rst(rst),.rx_valid(count!=0),.rx_data(fifo[rd]),.rx_ready(ready),.rx_fault(fault),
  .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready),.event_valid(event_valid),.event_ready(event_ready),
  .event_kind(event_kind),.event_id(event_id),.event_pitch(event_pitch),.event_velocity(event_velocity),
  .song_valid(song_valid),.upload_active(upload_active),.play_state(play_state),.position_ms(position_ms),
  .manual_inhibit(manual_inhibit),.last_error(last_error),.received_notes(received_notes),.total_notes(total_notes),
  .bad_frame(bad_frame),.scheduler_fault(scheduler_fault),
  .local_valid(local_valid),.local_command(local_command),.local_ready(local_ready),.local_done(local_done),.local_error(local_error),
  .storage_lock(storage_lock),.storage_ready(storage_ready),.storage_write(storage_write),.storage_invalidate(storage_invalidate),
  .storage_address(storage_address),.storage_wdata(storage_wdata),.storage_rdata(storage_rdata),
  .storage_import(storage_import),.storage_count(storage_count),.storage_crc(storage_crc),
  .storage_done(storage_done),.storage_error(storage_error),.song_duration(song_duration),.song_crc(song_crc),
  .performance_lock(performance_lock),.extension_valid(extension_valid),.extension_ready(extension_ready),.extension_command(extension_command),
  .extension_length(extension_length),.extension_payload(extension_payload),.extension_response_valid(extension_response_valid),
  .extension_response_ready(extension_response_ready),.extension_response_length(extension_response_length),.extension_response(extension_response),.storage_format(storage_format),.song_format(song_format),.event_timbre(event_timbre),.event_legacy(event_legacy));
 always @(posedge clk or posedge rst)begin
  if(rst)begin wr<=0;rd<=0;count<=0;overflow<=0;framing_fault<=0;end
  else if(fault)begin wr<=0;rd<=0;count<=0;if(rx_error)framing_fault<=1;if(overflow_now)overflow<=1;end
  else begin
   if(valid)begin fifo[wr]<=data;wr<=wr+1'b1;end
   if(pop)rd<=rd+1'b1;
   case({valid,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;endcase
  end
 end
 // synthesis translate_off
 initial if(FIFO_DEPTH<512 || (FIFO_DEPTH&(FIFO_DEPTH-1))!=0)$fatal(1,"FIFO must be power of two >=512");
 // synthesis translate_on
endmodule
