`timescale 1ns/1ps
module tb_bt_player_production;
 reg clk=0,rst=1,cmd_valid=0;always #10 clk=~clk;
 wire cmd_ready,done,ev,ready,busy,fault;wire [1:0] kind,play;wire [6:0] id,pitch,velocity;
 wire [31:0] position;wire [1:0] addr;reg [63:0] ram;
 integer checks=0,ons=0,offs=0,stall=0;realtime started=0,delay_ns;
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 bt_score_player #(.CLOCK_HZ(50000000),.MAX_NOTES(4),.VOICES(1)) dut(
 clk,rst,cmd_valid,cmd_ready,2'd0,done,16'd3,32'd3,addr,ram,
 ev,ready,kind,id,pitch,velocity,play,position,busy,fault);
 always @(posedge clk)case(addr)
  0:ram<={16'd1,8'd100,8'd60,32'd0};
  1:ram<={16'd1,8'd100,8'd62,32'd1};
  default:ram<={16'd1,8'd100,8'd64,32'd2};
 endcase
 assign ready=ev && stall==2500;
 always @(posedge clk)begin
  if(rst || !ev || ready)stall<=0;else if(stall<2500)stall<=stall+1;
  if(!rst)begin
   check(!fault,"50us consumer delay fits production1ms schedule");
   if(ev && ready)begin
    if(kind==1)begin
     delay_ns=$realtime-started-position*1000000.0;
     check(position==ons && delay_ns>=0 && delay_ns<120000,"production On time stays within0.12ms of intended clock time");ons++;
    end else if(kind==0)begin check(position==offs+1,"Off at each exact millisecond");offs++;end
   end
  end
 end
 always @(play)if(play==1)started=$realtime;
 initial begin
  #100 rst=0;@(negedge clk);cmd_valid=1;wait(cmd_ready);@(posedge clk);#1;@(negedge clk);cmd_valid=0;
  wait(ons==3 && play==0);repeat(5)@(negedge clk);
  check(offs==3 && position==3,"three production timed notes finish at3ms");
  $display("PASS tb_bt_player_production checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"production scheduler timeout");end
endmodule
