`timescale 1ns/1ps
module tb_pcb_repeat;
 reg clk=0,rst=1,down=0,page=1;always #5 clk=~clk;
 reg [15:0] x=740,y=440;wire valid;wire [6:0] action;integer events=0,checks=0;
 ui_touch_actions #(.PCB_REPEAT_DELAY(10),.PCB_REPEAT_PERIOD(3)) dut(
 clk,rst,1'b1,1'b1,1'b1,1'b0,down,4'd1,x,y,16'd800,16'd480,2'd0,1'b1,valid,action,1'b0,1'b0,page,1'b0);
 always @(posedge clk)if(valid)events++;
 initial begin
  repeat(3)@(negedge clk);rst=0;repeat(2)@(negedge clk);down=1;
  repeat(21)@(negedge clk);checks++;if(events<4 || action!=54)$fatal(1,"holding PCB plus should repeat after its initial delay");
  x=550;repeat(8)@(negedge clk);checks++;if(valid)$fatal(1,"dragging away must stop adjustment without activating another control");
  down=0;repeat(3)@(negedge clk);page=0;x=740;y=260;events=0;down=1;
  repeat(40)@(negedge clk);checks++;if(events!=1)$fatal(1,"legacy main effect controls must remain one event per touch");
  $display("PASS tb_pcb_repeat checks=%0d",checks);$finish;
 end
endmodule
