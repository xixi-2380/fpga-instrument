`timescale 1ns/1ps
// Optional serial link, not instantiated by keyboard_top until wiring is known.
module bluetooth_score_link #(
 parameter integer CLOCK_HZ=50000000,BAUD=9600,MAX_NOTES=1024,MAX_VOICES=1,
 NOTE_MIN=48,NOTE_MAX=83,MAX_SONG_MS=3600000,FIFO_DEPTH=512)(
 input wire clk,rst,uart_rx_pin,output wire uart_tx_pin,
 output wire event_valid,input wire event_ready,output wire [1:0] event_kind,
 output wire [6:0] event_id,event_pitch,event_velocity,
 output wire song_valid,upload_active,output wire [1:0] play_state,output wire [31:0] position_ms,
 output wire manual_inhibit,output wire [7:0] last_error,output wire [15:0] received_notes,total_notes,
 output reg overflow,framing_fault,output wire bad_frame,scheduler_fault);
 localparam integer PW=$clog2(FIFO_DEPTH),CW=$clog2(FIFO_DEPTH+1);
 wire [7:0] data;wire valid,rx_error,ready,tx_valid,tx_ready;wire [7:0] tx_data;
 reg [7:0] fifo[0:FIFO_DEPTH-1];reg [PW-1:0] wr,rd;reg [CW-1:0] count;
 wire pop=count!=0&&ready;
 wire overflow_now=valid&&count==FIFO_DEPTH&&!pop;
 wire fault=rx_error||overflow_now;
 uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) rx(clk,rst,uart_rx_pin,data,valid,rx_error);
 uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) tx(clk,rst,tx_data,tx_valid,tx_ready,uart_tx_pin);
 bluetooth_score_core #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD),.MAX_NOTES(MAX_NOTES),.MAX_VOICES(MAX_VOICES),
  .NOTE_MIN(NOTE_MIN),.NOTE_MAX(NOTE_MAX),.MAX_SONG_MS(MAX_SONG_MS)) core(
  clk,rst,count!=0,fifo[rd],ready,fault,tx_valid,tx_data,tx_ready,
  event_valid,event_ready,event_kind,event_id,event_pitch,event_velocity,
  song_valid,upload_active,play_state,position_ms,manual_inhibit,last_error,received_notes,total_notes,bad_frame,scheduler_fault);
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
