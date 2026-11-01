`timescale 1ns/1ps
module tb_controls_sensitivity;
 reg ac=0,rc=0,rst=1;always #5 ac=~ac;always #7 rc=~rc;
 reg menu=0,uv=0;reg [6:0] action=63;reg [2:0] online=7;
 wire page;wire [31:0] status;wire [2:0] cv;wire [131:0] data;
 reg [2:0] occupied=0,allowed=7,done=0,fail_mask=0,hang_mask=0;wire [2:0] ready=~occupied & allowed;
 reg [23:0] errors=0;reg server_reset=0;
 integer delays[0:2],left[0:2],starts[0:2],finishes[0:2];
 integer checks=0,seed=32'h2380a003;reg [131:0] expected_data;
 `include "config/ui_layout.svh"
 keyboard_sensitivity #(.TIMEOUT_CYCLES(192)) dut(ac,rc,rst,menu,uv,action,online,page,status,cv,data,ready,done,errors);
 always @(posedge rc)begin
  if(rst || server_reset)begin occupied<=0;done<=0;errors<=0;for(integer b=0;b<3;b++)left[b]<=0;end
  else begin
   done<=0;
   for(integer b=0;b<3;b++)begin
    if(cv[b] && ready[b])begin
     if(data!==expected_data)$fatal(1,"Three-board apply payload mismatch board=%0d data=%h expected=%h",b,data,expected_data);
     for(integer k=0;k<16;k++)if(data[4+8*k+:8]!==expected_data[11:4])$fatal(1,"Global KOR was not uniform");
     occupied[b]<=1;left[b]<=delays[b];starts[b]++;checks++;
    end else if(occupied[b] && !hang_mask[b])begin
     if(left[b]>1)left[b]<=left[b]-1;
     else begin done[b]<=1;errors[b*8+:8]<=fail_mask[b]?8'h22:8'd0;occupied[b]<=0;finishes[b]++;end
    end
   end
  end
 end
 task audio(input integer n);begin repeat(n)@(negedge ac);end endtask
 task tap(input [6:0] a);begin action=a;uv=1;audio(1);uv=0;audio(1);end endtask
 task prepare;
 begin
  for(integer b=0;b<3;b++)begin starts[b]=0;finishes[b]=0;delays[b]=5+17*b;end
  fail_mask=0;hang_mask=0;allowed=7;
  expected_data={{16{status[11:4]}},status[3:0]};
 end endtask
 task wait_result(input bit error_expected,input bit all_completed);integer budget;
 begin
  budget=0;
  while(status[12])begin
   if(status[14])$fatal(1,"Busy task advertised success");
   audio(1);budget++;if(budget>2000)$fatal(1,"Sensitivity completion did not cross domains");
  end
  if(status[13]!==error_expected || status[14]===error_expected)$fatal(1,"Wrong final sensitivity result status=%h",status);
  for(integer b=0;b<3;b++)begin
   if(all_completed && (starts[b]!=1 || finishes[b]!=1))$fatal(1,"Board did not apply exactly once b=%0d starts=%0d finishes=%0d",b,starts[b],finishes[b]);
   if(starts[b]>1)$fatal(1,"CDC replayed one apply to board%0d",b);
  end
  checks++;
 end endtask
 task assert_values(input integer g,k);begin if(status[3:0]!=g || status[11:4]!=k)$fatal(1,"GSR/KOR edit mismatch status=%h wanted=%0d/%0d",status,g,k);checks++;end endtask
 initial begin
  for(integer b=0;b<3;b++)begin starts[b]=0;finishes[b]=0;delays[b]=5+17*b;end
  audio(4);rst=0;audio(12);assert_values(2,4);
  tap(UI_SENSITIVITY);if(page)$fatal(1,"Sensitivity page opened outside settings");menu=1;tap(UI_SENSITIVITY);if(!page)$fatal(1,"Sensitivity page did not open");
  repeat(30)tap(UI_GSR_DOWN);assert_values(0,4);repeat(30)tap(UI_GSR_UP);assert_values(15,4);
  repeat(10)tap(UI_KOR_DOWN);assert_values(15,1);repeat(300)tap(UI_KOR_UP);assert_values(15,255);
  tap(UI_SENS_DEFAULT);assert_values(2,4);tap(UI_GSR_UP);tap(UI_KOR_UP);assert_values(3,5);
  prepare;allowed=0;tap(UI_SENS_APPLY);if(!status[12])$fatal(1,"Apply was not busy");
  // Edits/defaults cannot mutate the in-flight20-bit request snapshot.
  tap(UI_GSR_UP);tap(UI_KOR_DOWN);tap(UI_SENS_DEFAULT);assert_values(3,5);
  tap(UI_SENS_BACK);if(page)$fatal(1,"Page close failed");menu=0;
  audio(12);@(negedge rc);allowed=1;audio(8);@(negedge rc);allowed=5;audio(9);@(negedge rc);allowed=7;
  wait_result(0,1);if(page)$fatal(1,"Completed task reopened a closed page");
  menu=1;tap(UI_SENSITIVITY);prepare;fail_mask=2;tap(UI_SENS_APPLY);wait_result(1,1);
  // Accepted-but-never-finished board must cause error, never false success.
  prepare;hang_mask=4;tap(UI_SENS_APPLY);wait_result(1,0);
  @(negedge rc);server_reset=1;audio(5);server_reset=0;audio(5);
  // A board that never becomes ready must time out as well.
  prepare;allowed=3;tap(UI_SENS_APPLY);wait_result(1,0);if(starts[2]!=0)$fatal(1,"Not-ready board was falsely started");
  allowed=7;audio(5);
  // Crossing256 jobs covers request/completion epoch wrap and random delays.
  for(integer n=0;n<260;n++)begin
   if(n%2==0)tap(UI_GSR_UP);else tap(UI_GSR_DOWN);
   if(n%3==0)tap(UI_KOR_UP);else tap(UI_KOR_DOWN);
   prepare;
   for(integer b=0;b<3;b++)delays[b]=1+$unsigned($random(seed))%50;
   if(n%7==0)fail_mask=3'b1<<($unsigned($random(seed))%3);
   tap(UI_SENS_APPLY);wait_result(fail_mask!=0,1);
  end
  $display("PASS tb_controls_sensitivity checks=%0d",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"Sensitivity CDC timeout");end
endmodule
