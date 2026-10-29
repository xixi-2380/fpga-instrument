`timescale 1ns/1ps
module tb_pcb_touch;
 reg clk=0,rst=1,down=0,page=0;always #5 clk=~clk;
 reg [15:0] x=0,y=0;wire valid;wire [5:0] action;integer checks=0,events=0;
 ui_touch_actions dut(clk,rst,1'b1,1'b1,1'b1,1'b0,down,4'd1,x,y,16'd800,16'd480,2'd0,1'b1,valid,action,1'b0,1'b0,page);
 always @(posedge clk)if(valid)events++;
 task tap(input integer xx,yy,expected);integer events_before;begin
  @(negedge clk);down=0;repeat(2)@(negedge clk);x=xx;y=yy;events_before=events;down=1;
  @(negedge clk);checks++;if(!valid || action!=expected)$fatal(1,"wrong PCB touch %0d,%0d got=%0d",xx,yy,action);
  repeat(5)@(negedge clk);checks++;if(events!=events_before+1)$fatal(1,"held touch repeats");down=0;repeat(2)@(negedge clk);
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;tap(480,440,42);tap(380,440,33);page=1;
  tap(700,32,43);for(integer i=0;i<5;i++)tap(40+i*152,100,44+i);
  tap(60,150,49);tap(170,150,50);tap(280,150,51);tap(390,150,52);tap(500,150,55);tap(600,150,62);tap(720,150,60);
  tap(60,440,57);tap(190,440,58);tap(310,440,59);tap(440,440,56);tap(550,440,61);tap(670,440,53);tap(740,440,54);
  $display("PASS tb_pcb_touch checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"touch timeout");end
endmodule
