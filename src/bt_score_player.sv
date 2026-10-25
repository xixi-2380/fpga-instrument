`timescale 1ns/1ps
// Downloaded-record scheduler; 64-bit RAM records are NOT old score ROM words.
// Internal kind: 0=Off,1=On,2=urgent silence,3=natural end (drain then silence).
// One clock domain. A future audio-domain bridge must retain the full event.
module bt_score_player #(
 parameter integer CLOCK_HZ=50000000,MAX_NOTES=1024,VOICES=1,
 parameter integer AW=(MAX_NOTES>1?$clog2(MAX_NOTES):1))(
 input wire clk,rst,input wire command_valid,output wire command_ready,
 input wire [1:0] command,output reg command_done,
 input wire [15:0] note_count,input wire [31:0] song_duration,
 output reg [AW-1:0] ram_address,input wire [63:0] ram_data,
 output wire event_valid,input wire event_ready,output reg [1:0] event_kind,
 output reg [6:0] event_id,event_pitch,event_velocity,
 output reg [1:0] play_state,output reg [31:0] position_ms,
 output wire busy,output reg deadline_error);
 localparam integer MS_CYCLES=CLOCK_HZ/1000;
 localparam [3:0] IDLE=0,WAIT_TICK=1,SILENCE=2,OFF_BEGIN=3,OFF_SCAN=4,EMIT_OFF=5,
  ON_CHECK=6,FETCH=7,FETCH_WAIT=8,FETCH_LATCH=9,FREE_SCAN=10,EMIT_ON=11,RESUME_SCAN=12,RESUME_EMIT=13;
 reg [3:0] state;reg [1:0] action;reg [31:0] ms_counter;
 reg [15:0] pc;reg [63:0] next_record;reg next_valid;
 reg [VOICES-1:0] active;reg [31:0] end_ms[0:VOICES-1];
 reg [6:0] pitches[0:VOICES-1],velocities[0:VOICES-1];
 reg [6:0] scan;reg fault_pending,natural_finish;
 wire time_tick=play_state==1 && ms_counter==MS_CYCLES-1;
 assign command_ready=!rst&&(state==IDLE||state==WAIT_TICK);
 assign busy=!rst && state!=IDLE && state!=WAIT_TICK;
 assign event_valid=!rst&&(state==SILENCE||state==EMIT_OFF||state==EMIT_ON||state==RESUME_EMIT);
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;action<=0;ms_counter<=0;pc<=0;next_record<=0;next_valid<=0;active<=0;
   event_kind<=0;event_id<=0;event_pitch<=0;event_velocity<=0;scan<=0;
   play_state<=0;position_ms<=0;command_done<=0;ram_address<=0;deadline_error<=0;fault_pending<=0;natural_finish<=0;
   for(integer i=0;i<VOICES;i=i+1)begin end_ms[i]<=0;pitches[i]<=0;velocities[i]<=0;end
  end else begin
   command_done<=0;deadline_error<=0;
   if(play_state==1)begin if(time_tick)ms_counter<=0;else ms_counter<=ms_counter+1'b1;end
   else ms_counter<=0;
   if(time_tick && state!=WAIT_TICK && !fault_pending)begin fault_pending<=1;deadline_error<=1;end
   if(command_valid&&command_ready)begin
    action<=command;natural_finish<=0;
    if(command==2 && play_state==2)begin scan<=0;state<=RESUME_SCAN;end
    else if((command==1&&play_state==2)||(command==2&&play_state==1))command_done<=1;
    else begin if(command==1)play_state<=2;else play_state<=0;event_kind<=2;event_id<=0;event_pitch<=0;event_velocity<=0;state<=SILENCE;end
   end else case(state)
    IDLE:;
    WAIT_TICK:if(fault_pending)begin action<=3;natural_finish<=0;event_kind<=2;event_id<=0;event_pitch<=0;event_velocity<=0;state<=SILENCE;end
     else if(time_tick)begin position_ms<=position_ms+1'b1;state<=OFF_BEGIN;end
    SILENCE:if(event_ready)begin
     if(action==0)begin // PLAY after external automatic-voice flush is acknowledged
      pc<=0;next_valid<=0;active<=0;play_state<=1;position_ms<=0;ms_counter<=0;fault_pending<=0;state<=OFF_BEGIN;command_done<=1;
     end else if(action==1)begin play_state<=2;state<=IDLE;command_done<=1;end
     else begin play_state<=0;active<=0;next_valid<=0;fault_pending<=0;state<=IDLE;if(!natural_finish)position_ms<=0;command_done<=!natural_finish;end
    end
    OFF_BEGIN:begin scan<=0;state<=OFF_SCAN;end
    OFF_SCAN:if(active[scan]&&end_ms[scan]<=position_ms)begin
      event_kind<=0;event_id<=scan;event_pitch<=pitches[scan];event_velocity<=0;state<=EMIT_OFF;
     end else if(scan==VOICES-1)state<=ON_CHECK;else scan<=scan+1'b1;
    EMIT_OFF:if(event_ready)begin active[scan]<=0;if(scan==VOICES-1)state<=ON_CHECK;else begin scan<=scan+1'b1;state<=OFF_SCAN;end end
    ON_CHECK:if(fault_pending)state<=WAIT_TICK;
     else if(!next_valid&&pc<note_count)state<=FETCH;
     else if(next_valid&&next_record[31:0]<=position_ms)begin scan<=0;state<=FREE_SCAN;end
     else if(pc==note_count && active==0)begin action<=3;natural_finish<=1;play_state<=0;event_kind<=3;event_id<=0;event_pitch<=0;event_velocity<=0;state<=SILENCE;end
     else state<=WAIT_TICK;
    FETCH:begin ram_address<=pc[AW-1:0];state<=FETCH_WAIT;end
    FETCH_WAIT:state<=FETCH_LATCH;
    FETCH_LATCH:begin next_record<=ram_data;next_valid<=1;state<=ON_CHECK;end
    FREE_SCAN:if(!active[scan])begin
      active[scan]<=1;end_ms[scan]<={16'b0,next_record[63:48]}+next_record[31:0];
      pitches[scan]<=next_record[38:32];velocities[scan]<=next_record[46:40];
      event_kind<=1;event_id<=scan;event_pitch<=next_record[38:32];event_velocity<=next_record[46:40];
      next_valid<=0;pc<=pc+1'b1;state<=EMIT_ON;
     end else if(scan==VOICES-1)begin fault_pending<=1;deadline_error<=1;state<=WAIT_TICK;end
     else scan<=scan+1'b1;
    EMIT_ON:if(event_ready)state<=ON_CHECK;
    RESUME_SCAN:if(active[scan])begin event_kind<=1;event_id<=scan;event_pitch<=pitches[scan];event_velocity<=velocities[scan];state<=RESUME_EMIT;end
     else if(scan==VOICES-1)begin play_state<=1;ms_counter<=0;state<=WAIT_TICK;command_done<=1;end
     else scan<=scan+1'b1;
    RESUME_EMIT:if(event_ready)begin
     if(scan==VOICES-1)begin play_state<=1;ms_counter<=0;state<=WAIT_TICK;command_done<=1;end
     else begin scan<=scan+1'b1;state<=RESUME_SCAN;end
    end
    default:begin state<=IDLE;play_state<=0;deadline_error<=1;end
   endcase
  end
 end
 // synthesis translate_off
 initial if(VOICES<1||VOICES>32||CLOCK_HZ<1000||CLOCK_HZ%1000!=0)$fatal(1,"invalid scheduler parameters");
 // synthesis translate_on
endmodule
