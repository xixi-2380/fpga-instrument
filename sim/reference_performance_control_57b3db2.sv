`timescale 1ns/1ps
`include "../src/config/synth_config.svh"
// Twelve pentatonic strings. Coordinates are atomic audio-domain GT911 reports.
// Identity96..107 is disjoint from automatic0..15 and physical piano60..95.
module performance_control_reference_94030a #(parameter integer GATE_FRAMES=1680,STALE_CYCLES=(`AUDIO_HZ/4))(
 input wire clk,rst,frame_ce,input_ready,blocked,menu_mode,can_open,
 input wire snapshot_valid,report_valid,health_valid,ready,error,down,input wire [3:0] count,
 input wire [15:0] x,y,resolution_x,resolution_y,
 input wire [4:0] selected_timbre,input wire note_ready,
 output reg note_valid,note_on,output reg [6:0] note_id,note_pitch,note_velocity,
 output reg [31:0] note_fcw,output reg [4:0] note_timbre,
 output reg active,output wire [63:0] status,output reg [17:0] pitch_ratio,
 output reg chorus_enabled,output wire [8:0] chorus_wet,
 output reg [1:0] chorus_depth,chorus_rate);
 `include "../src/config/keyboard_notes.svh"
 function automatic [5:0] string_key(input integer s);
  begin case(s)
   0:string_key=0;1:string_key=2;2:string_key=4;3:string_key=7;4:string_key=9;
   5:string_key=12;6:string_key=14;7:string_key=16;8:string_key=19;9:string_key=21;
   10:string_key=24;default:string_key=26;
  endcase end
 endfunction
 reg armed,contact,sliding,reverse;
 reg [15:0] previous_x,previous_y;
 reg [11:0] pending,held;reg [10:0] flash[0:11];
 localparam integer GW=GATE_FRAMES>1?$clog2(GATE_FRAMES+1):1;
 localparam integer SW=STALE_CYCLES>1?$clog2(STALE_CYCLES+1):1;
 reg [GW-1:0] gates[0:11];reg [SW-1:0] stale;
 reg [3:0] event_string;reg [17:0] target_ratio;
 reg selected_sound;reg [9:0] slider_position;
 reg [2:0] wet_step;reg [11:0] hits;reg [11:0] glowing;
 integer pick,xx;
 wire good=snapshot_valid && ready && !error && resolution_x==800 && resolution_y==480 && stale<STALE_CYCLES;
 wire point=count==1 && x<800 && y<480;
 wire playable=active && good && !menu_mode && !blocked && input_ready;
 wire on_strings=point && x>=88 && x<=664 && y>=116 && y<348;
 wire slider=point && x>=128 && x<672 && y>=368 && y<416;
 assign chorus_wet={1'b0,wet_step,5'd0};
 // [0]page,[1]chorus,[4:2]mix,[6:5]depth,[8:7]rate,[20:9]lit,
 // [30:21]slider position (0..512),[31]touch healthy,[32]BT blocked.
 assign status={30'd0,selected_sound,blocked,good,slider_position,glowing,chorus_rate,chorus_depth,wet_step,chorus_enabled,active};
 always @*begin
  hits=0;glowing=0;
  for(integer s=0;s<12;s=s+1)begin
   xx=112+s*48;
   glowing[s]=flash[s]!=0;
   if(playable && report_valid && down && on_strings && !sliding && y>=132+s*7)begin
    if(!contact)hits[s]=armed && x>=xx-12 && x<=xx+12;
    else if(previous_y>=116 && previous_y<348)
     hits[s]=(previous_x<xx && x>=xx)||(previous_x>xx && x<=xx);
   end
  end
  pick=-1;
  // Expired/forced Note Off has priority over new On. Replucking one held
  // string explicitly releases its old owner before allocating the new tail.
  for(integer s=11;s>=0;s=s-1)
   if(held[s] && (gates[s]==0 || !playable || pending[s]))pick=s;
  if(pick<0 && playable)begin
   if(reverse)begin for(integer s=0;s<12;s=s+1)if(pending[s])pick=s;end
   else begin for(integer s=11;s>=0;s=s-1)if(pending[s])pick=s;end
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   active<=0;armed<=0;contact<=0;sliding<=0;reverse<=0;previous_x<=0;previous_y<=0;
   pending<=0;held<=0;note_valid<=0;note_on<=0;note_id<=96;note_pitch<=60;
   note_velocity<=100;note_fcw<=0;note_timbre<=5;event_string<=0;
   chorus_enabled<=0;wet_step<=3;chorus_depth<=1;chorus_rate<=1;
   pitch_ratio<=65536;target_ratio<=65536;slider_position<=256;selected_sound<=0;stale<=STALE_CYCLES;
   for(integer s=0;s<12;s=s+1)begin gates[s]<=0;flash[s]<=0;end
  end else begin
   if(health_valid)stale<=0;else if(stale<STALE_CYCLES)stale<=stale+1'b1;
   if(frame_ce)begin
    if(pitch_ratio<target_ratio)pitch_ratio<=target_ratio-pitch_ratio>32?pitch_ratio+18'd32:target_ratio;
    else if(pitch_ratio>target_ratio)pitch_ratio<=pitch_ratio-target_ratio>32?pitch_ratio-18'd32:target_ratio;
    for(integer s=0;s<12;s=s+1)begin
     if(gates[s]!=0)gates[s]<=gates[s]-1'b1;
     if(flash[s]!=0)flash[s]<=flash[s]-1'b1;
    end
   end
   if(menu_mode || !can_open)active<=0;
   if(!good || !active || blocked)begin contact<=0;sliding<=0;target_ratio<=65536;slider_position<=256;end
   if(!good)armed<=0;
   else if(!down)armed<=1;
   if(report_valid && good)begin
    if(!down)begin armed<=1;contact<=0;sliding<=0;target_ratio<=65536;slider_position<=256;end
    else if(!point)begin armed<=0;contact<=0;sliding<=0;target_ratio<=65536;slider_position<=256;end
    else begin
     armed<=0;
     if(armed && !menu_mode && can_open && x>=456 && x<632 && y>=16 && y<64)active<=!active;
     if(active && armed && x>=648 && x<784 && y>=16 && y<64)active<=0;
     if(active && armed && x>=704 && x<784 && y>=104 && y<156)chorus_enabled<=!chorus_enabled;
     if(active && armed && x>=704 && x<784 && y>=176 && y<224)wet_step<=wet_step==4?1:wet_step+1'b1;
     if(active && armed && x>=704 && x<784 && y>=244 && y<292)chorus_depth<=chorus_depth==2?0:chorus_depth+1'b1;
     if(active && armed && x>=704 && x<784 && y>=312 && y<360)chorus_rate<=chorus_rate==2?0:chorus_rate+1'b1;
     if(active && armed && x>=24 && x<164 && y>=420 && y<468)selected_sound<=!selected_sound;
     if(active && armed && x>=184 && x<324 && y>=420 && y<468)begin active<=0;target_ratio<=65536;slider_position<=256;end
     if(playable && (armed || contact))begin
      if(!contact && slider)sliding<=1;
      if((sliding || (!contact && slider)) && y>=352 && y<432)begin
       slider_position<=x<=144?10'd0:x>=656?10'd512:10'(x-16'd144);
       if(x<=144)target_ratio<=58386;
       else if(x>=656)target_ratio<=73562;
       else if(x>=400)target_ratio<=18'd65536+18'(((x-16'd400)*32'd8026)>>8);
       else target_ratio<=18'd65536-18'(((16'd400-x)*32'd7150)>>8);
      end
      contact<=on_strings || slider || sliding;
      if(contact && x!=previous_x)reverse<=x<previous_x;
      previous_x<=x;previous_y<=y;
     end
    end
   end
   for(integer s=0;s<12;s=s+1)begin
    if(note_valid && note_ready && event_string==s)begin
     held[s]<=note_on;
     if(note_on)begin pending[s]<=0;gates[s]<=GATE_FRAMES;flash[s]<=1920;end
     else gates[s]<=0;
    end
    if(hits[s])pending[s]<=1;
    if(!playable)pending[s]<=0;
   end
   if(note_valid)begin if(note_ready)note_valid<=0;end
   else if(pick>=0 && input_ready)begin
    note_valid<=1;event_string<=pick;note_on<=!held[pick];
    note_id<=7'd96+7'(pick);note_pitch<=7'd60+string_key(pick);
    note_fcw<=key_fcw(string_key(pick));note_velocity<=100;
    // Guitar's fast attack/natural decay provides the pluck articulation;
    // on-screen TONE toggles fixed guitar / the existing panel-selected tone.
    note_timbre<=selected_sound?selected_timbre:5'd5;
   end
   if(blocked)begin note_valid<=0;held<=0;pending<=0;end
  end
 end
 // synthesis translate_off
 initial if(GATE_FRAMES<1 || STALE_CYCLES<1)$fatal(1,"Invalid performance timing");
 // synthesis translate_on
endmodule

