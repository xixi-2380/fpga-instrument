`timescale 1ns/1ps
module tb_bluetooth_score_link;
 parameter integer CLOCK_HZ=1000000,BAUD=9600;
 localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
 reg clk=0,rst=1,rx=1;wire tx,ev,song,upload,inhibit,overflow,framing,bad,fault;
 wire [1:0] kind,play;wire [6:0] id,pitch,velocity;wire [31:0] position;wire [7:0] error_code;wire [15:0] received,total;
 always #5 clk=~clk;
 bluetooth_score_link #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) dut(clk,rst,rx,tx,ev,1'b1,kind,id,pitch,velocity,song,upload,play,position,inhibit,error_code,received,total,overflow,framing,bad,fault);
 integer checks=0,count=0,goal=0,responses=0;reg [7:0] bytes[0:63];
 function automatic [15:0] crc_byte(input [15:0] c,input [7:0] b);
 reg [15:0] x;begin x=c^{b,8'b0};for(integer k=0;k<8;k++)x=(x<<1)^(x[15]?16'h1021:0);crc_byte=x;end endfunction
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task send(input [7:0] b);begin rx=0;clocks(DIV);for(integer k=0;k<8;k++)begin rx=b[k];clocks(DIV);end rx=1;clocks(DIV);end endtask
 task request(input [7:0] cmd,input [15:0] seq);
 reg [15:0] c;reg [7:0] b;begin send(8'ha5);send(8'h5a);c=16'hffff;
 for(integer k=0;k<6;k++)begin case(k)0:b=1;1:b=cmd;2:b=seq[7:0];3:b=seq[15:8];default:b=0;endcase send(b);c=crc_byte(c,b);end send(c[7:0]);send(c[15:8]);end endtask
 // Independent UART line sampling, not the production receiver.
 initial forever begin
 reg [7:0] value;reg [15:0] c;
 @(negedge tx);clocks(DIV/2);check(tx==0,"TX start bit");
 for(integer k=0;k<8;k++)begin clocks(DIV);value[k]=tx;end
 clocks(DIV);check(tx==1,"TX stop bit");bytes[count]=value;count++;
 if(count==8)goal=10+{bytes[7],bytes[6]};
 if(goal>0&&count==goal)begin
 c=16'hffff;for(integer k=2;k<goal-2;k++)c=crc_byte(c,bytes[k]);
 check(bytes[0]==8'ha5&&bytes[1]==8'h5a&&bytes[2]==1,"wire response header");check({bytes[goal-1],bytes[goal-2]}==c,"wire response CRC");responses++;count=0;goal=0;
 end
 end
 initial begin clocks(5);rst=0;clocks(5);request(1,0);wait(responses==1);clocks(1);
 check(bytes[3]==8'h81&&bytes[8]==0&&bytes[15]==1,"wire HELLO capability");check({bytes[23],bytes[22],bytes[21],bytes[20]}==BAUD,"wire HELLO baud");
 request(8'h30,1);wait(responses==2);clocks(1);check(bytes[3]==8'hb0&&bytes[8]==0&&bytes[9]==0&&bytes[11]==0,"wire GET_STATUS");
 check(!overflow&&!framing&&!fault&&!song&&!upload&&!inhibit,"link initial state and diagnostics");
 $display("PASS tb_bluetooth_score_link checks=%0d baud=%0d",checks,BAUD);$finish;end
 initial begin #10000000000;$fatal(1,"wire watchdog");end
endmodule
