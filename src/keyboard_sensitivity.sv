`timescale 1ns/1ps
// One editable GSR/KOR pair, with an acknowledged apply on all three buses.
// UI feedback is small; keyboard collection/recovery remains in its driver.
module keyboard_sensitivity #(parameter integer TIMEOUT_CYCLES=100000000)(
 input wire audio_clk,ref_clk,rst,menu_mode,ui_action_valid,input wire [6:0] ui_action,
 input wire [2:0] online,output reg page_open,output wire [31:0] status,
 output wire [2:0] cfg_valid,output wire [131:0] cfg_data,input wire [2:0] cfg_ready,cfg_done,
 input wire [23:0] cfg_error);
 `include "config/ui_layout.svh"
 wire ar,rr;reset_sync ui_reset(audio_clk,rst,ar);reset_sync bus_reset(ref_clk,rst,rr);
 reg [3:0] gsr;reg [7:0] kor,request_epoch;
 reg request_valid,busy,error,success;
 wire request_ready,ref_valid,ref_ready;wire [19:0] ref_request;
 wire [15:0] completion;wire completion_valid;
 reg [7:0] completed_sequence,result_error;
 bt_event_cdc #(.WIDTH(20)) request_bridge(audio_clk,ref_clk,rst,
  request_valid,request_ready,{request_epoch,kor,gsr},ref_valid,ref_ready,ref_request);
 rgb_status_cdc #(.WIDTH(16)) result_bridge(ref_clk,audio_clk,rst,
  {completed_sequence,result_error},completion,completion_valid,);
 assign status={13'd0,online,page_open,success,error,busy,kor,gsr};
 always @(posedge audio_clk or posedge ar)begin
  if(ar)begin gsr<=2;kor<=4;request_epoch<=0;page_open<=0;request_valid<=0;busy<=0;error<=0;success<=0;end
  else begin
   if(request_valid && request_ready)request_valid<=0;
   if(!menu_mode)page_open<=0;
   if(busy && completion_valid && completion[15:8]==request_epoch)begin
    busy<=0;error<=completion[7:0]!=0;success<=completion[7:0]==0;
   end
   if(ui_action_valid)begin
    if(ui_action==UI_SENSITIVITY && menu_mode)page_open<=1;
    if(ui_action==UI_SENS_BACK || ui_action==UI_MODE)page_open<=0;
    if(page_open && !busy)case(ui_action)
     UI_GSR_DOWN:begin if(gsr>0)gsr<=gsr-1'b1;success<=0;error<=0;end
     UI_GSR_UP:begin if(gsr<15)gsr<=gsr+1'b1;success<=0;error<=0;end
     UI_KOR_DOWN:begin if(kor>1)kor<=kor-1'b1;success<=0;error<=0;end
     UI_KOR_UP:begin if(kor<255)kor<=kor+1'b1;success<=0;error<=0;end
     UI_SENS_DEFAULT:begin gsr<=2;kor<=4;success<=0;error<=0;end
     UI_SENS_APPLY:begin request_epoch<=request_epoch+1'b1;request_valid<=1;busy<=1;error<=0;success<=0;end
     default:begin end
    endcase
   end
  end
 end
 localparam CW=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES):1;
 reg [CW-1:0] timer;wire [CW-1:0] timer_next;
 for(genvar k=0;k<CW;k=k+8)begin:timer_bytes
  localparam W=CW-k<8?CW-k:8;
  wire carry;if(k==0)assign carry=1;else assign carry=&timer[k-1:0];
  assign timer_next[k+:W]=timer[k+:W]+carry;
 end
 reg active;reg [2:0] pending,inflight;reg [131:0] applied_data;reg [7:0] job_sequence,job_error;
 wire allow_start=timer<TIMEOUT_CYCLES-1;
 wire [2:0] starts=pending & cfg_ready & {3{allow_start}};
 wire [2:0] finishes=inflight & cfg_done;
 wire [2:0] next_pending=pending & ~starts,next_inflight=(inflight|starts)&~finishes;
 reg [7:0] next_error;
 always @*begin
  next_error=job_error;
  for(integer b=0;b<3;b=b+1)if(finishes[b] && cfg_error[b*8+:8]!=0)next_error=cfg_error[b*8+:8];
 end
 assign cfg_valid=active && allow_start?pending:3'd0;assign cfg_data=applied_data;assign ref_ready=!active;
 always @(posedge ref_clk or posedge rr)begin
  if(rr)begin active<=0;pending<=0;inflight<=0;applied_data<=0;job_sequence<=0;job_error<=0;
   completed_sequence<=0;result_error<=0;timer<=0;end
  else if(!active)begin
   if(ref_valid)begin
    active<=1;pending<=7;inflight<=0;job_sequence<=ref_request[19:12];job_error<=0;timer<=0;
    applied_data<={{16{ref_request[11:4]}},ref_request[3:0]};
   end
  end else begin
   pending<=next_pending;inflight<=next_inflight;job_error<=next_error;
   if(next_pending==0 && next_inflight==0)begin active<=0;completed_sequence<=job_sequence;result_error<=next_error;end
   else if(timer==TIMEOUT_CYCLES-1)begin active<=0;pending<=0;inflight<=0;completed_sequence<=job_sequence;result_error<=8'h31;end
   else timer<=timer_next;
  end
 end
 // synthesis translate_off
 initial if(TIMEOUT_CYCLES<2)$fatal(1,"Sensitivity timeout must be at least two clocks");
 // synthesis translate_on
endmodule
