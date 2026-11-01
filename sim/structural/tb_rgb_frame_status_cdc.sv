`timescale 1ns/1ps
module tb_rgb_frame_status_cdc;
 parameter integer SOURCE_HALF=7,PIXEL_HALF=11,WIDTH=2592,FRAME_PERIOD=40,RESET_PAYLOAD=0;
 reg sc=0,pc=0,reset=0,source_run=1,pixel_run=1;
 always #(SOURCE_HALF)if(source_run)sc=~sc;else sc=0;
 always #(PIXEL_HALF)if(pixel_run)pc=~pc;else pc=0;
 reg [9:0] serial=0;
 wire [((WIDTH+19)/20)*20-1:0] pattern={((WIDTH+19)/20){serial,~serial}};
 wire [WIDTH-1:0] data=pattern[WIDTH-1:0];
 reg [15:0] frame_count=0;
 wire frame_start=!reset && frame_count==0;
 always @(posedge pc)if(reset)frame_count<=0;else if(frame_count==FRAME_PERIOD-1)frame_count<=0;else frame_count<=frame_count+1'b1;
 wire [WIDTH-1:0] received;wire valid,pulse;
 rgb_frame_status_cdc #(.WIDTH(WIDTH),.RESET_PAYLOAD(RESET_PAYLOAD),.FRAME_LOCKED(1)) dut(sc,pc,reset,frame_start,data,received,valid,pulse);
 reg [WIDTH-1:0] expected=0,previous=0,old_held=0;
 reg old_ack=0,was_valid=0,permitted=0;
 integer checks=0,updates=0,captures=0;
 task check(input bit ok,input string message);begin checks++;if(!ok)$fatal(1,"%s",message);end endtask
 always @(posedge sc)begin
  serial<=serial+1'b1;
  if(!reset && !dut.source_reset && !dut.acknowledge && dut.request_sync[1])begin expected=data;captures++;end
  #1;
  if(!reset && !dut.source_reset && old_ack && dut.acknowledge)check(dut.held_data===old_held,"source payload held through frame wait");
  old_ack=dut.acknowledge;old_held=dut.held_data;
 end
 always @(posedge pc)begin
  permitted=frame_start;
  #2;
  if(reset || dut.pixel_reset)begin
   check(!valid && !pulse,"reset clears control regardless of payload reset mode");
   if(RESET_PAYLOAD!=0)check(received==0,"reset-payload option keeps original zero output contract");
   was_valid=0;
  end else begin
   if(pulse)begin
    updates++;
    check(permitted,"publication only at renderer frame boundary");
    check(valid && received===expected,"complete source snapshot reaches frame output");
    check(received[9:0]==~received[19:10],"cross-domain snapshot cannot tear");
   end else if(was_valid)check(received===previous,"published payload held for complete frame");
   was_valid=valid;
  end
  previous=received;
 end
 task restart;
  begin
   #3;reset=1;#2;check(!valid && !pulse,"asynchronous validity reset");
   repeat(5)@(negedge pc);reset=0;
   repeat(FRAME_PERIOD*3)@(negedge pc);check(valid,"frame handshake restarts");
  end
 endtask
 initial begin
  restart();repeat(FRAME_PERIOD*20)@(negedge pc);
  @(negedge pc);pixel_run=0;repeat(80)@(negedge sc);pixel_run=1;
  repeat(FRAME_PERIOD*3)@(negedge pc);check(valid,"pixel stop/restart recovers");
  @(negedge sc);source_run=0;repeat(FRAME_PERIOD*3)@(negedge pc);source_run=1;
  repeat(FRAME_PERIOD*3)@(negedge pc);check(valid,"source stop/restart recovers");
  @(negedge pc);pixel_run=0;#3;reset=1;#2;
  check(!valid && !pulse,"reset clears validity while destination clock is stopped");
  repeat(12)@(negedge sc);pixel_run=1;repeat(5)@(negedge pc);reset=0;
  repeat(FRAME_PERIOD*3)@(negedge pc);check(valid,"reset and destination clock recovery restart frame handshake");
  @(negedge sc);source_run=0;#3;reset=1;#2;
  check(!valid && !pulse,"reset clears validity while source clock is stopped");
  repeat(12)@(negedge pc);source_run=1;repeat(5)@(negedge pc);reset=0;
  repeat(FRAME_PERIOD*3)@(negedge pc);check(valid,"reset and source clock recovery restart frame handshake");
  repeat(8)begin repeat(7)@(negedge pc);restart();end
  check(updates>20 && captures>=updates,"many frame snapshots published");
  $display("PASS tb_rgb_frame_status_cdc checks=%0d updates=%0d captures=%0d",checks,updates,captures);$finish;
 end
 initial begin #2000000;$fatal(1,"frame CDC timeout");end
endmodule
