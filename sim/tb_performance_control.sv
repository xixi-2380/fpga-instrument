`timescale 1ns/1ps
module tb_performance_control;
 reg clk=0,rst=1,frame=0,report=0,heartbeat=0,down=0,ready=1,error=0,blocked=0,menu=0,nready=1;
 reg [3:0] count=0;reg [15:0] x=0,y=0,rx=800,ry=480;
 wire valid,on,active,chorus;wire [6:0] id,pitch,velocity;wire [4:0] tone;
 wire [31:0] fcw;wire [63:0] status;wire [17:0] ratio;wire [8:0] wet;wire [1:0] depth,rate;
 integer checks=0,ons=0,offs=0,n=0;reg [11:0] seen=0;reg [6:0] order[0:255];
 always #5 clk=~clk;
 performance_control #(.GATE_FRAMES(16),.STALE_CYCLES(100000)) dut(
 .clk(clk),.rst(rst),.frame_ce(frame),.input_ready(1'b1),.blocked(blocked),.menu_mode(menu),.can_open(1'b1),
 .snapshot_valid(1'b1),.report_valid(report),.health_valid(report || heartbeat),.ready(ready),.error(error),.down(down),.count(count),
 .x(x),.y(y),.resolution_x(rx),.resolution_y(ry),.selected_timbre(5'd3),.note_ready(nready),
 .note_valid(valid),.note_on(on),.note_id(id),.note_pitch(pitch),.note_velocity(velocity),.note_fcw(fcw),.note_timbre(tone),
 .active(active),.status(status),.pitch_ratio(ratio),.chorus_enabled(chorus),.chorus_wet(wet),.chorus_depth(depth),.chorus_rate(rate));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task cycles(input integer k);repeat(k)@(negedge clk);endtask
 task touch(input bit d,input integer a,b);begin @(negedge clk);down=d;count=d?1:0;x=a;y=b;report=1;cycles(1);report=0;cycles(2);end endtask
 task tap(input integer a,b);begin touch(0,0,0);touch(1,a,b);touch(0,0,0);end endtask
 task frames(input integer k);for(integer j=0;j<k;j++)begin @(negedge clk);frame=1;cycles(1);frame=0;cycles(8);end endtask
 always @(posedge clk)if(!rst&&valid&&nready)begin
  check(id>=96&&id<108,"touch identity isolation");check(velocity==100&&fcw!=0,"complete pluck metadata");
  if(on)begin seen[id-96]=1;order[n]=id;n++;ons++;end else offs++;
 end
 initial begin
  cycles(3);rst=0;touch(0,0,0);touch(0,0,0);tap(500,40);check(active,"open harp page");
  tap(112,260);cycles(10);check(ons==1&&tone==5,"single pluck uses guitar");
  touch(1,112,260);cycles(25);check(ons==2,"new contact replucks");cycles(20);check(ons==2,"stationary finger never repeats");
  touch(1,640,260);cycles(100);check(seen==12'hfff&&ons==13,"fast sweep reconstructs eleven crossed strings");
  for(integer k=0;k<11;k++)check(order[k+2]==97+k,"forward sweep ordered");
  touch(1,112,260);cycles(100);check(ons==24,"reverse sweep");
  for(integer k=0;k<11;k++)check(order[k+13]==106-k,"reverse sweep ordered");
  touch(0,0,0);frames(20);check(dut.held==0&&offs==ons,"every pluck eventually releases");
  nready=0;tap(256,260);cycles(5);check(valid,"event offered under backpressure");
  begin reg [58:0] saved;saved={on,id,fcw,tone,pitch,velocity};
   tap(640,260);cycles(30);check({on,id,fcw,tone,pitch,velocity}==saved,"backpressured payload immutable");end
  nready=1;cycles(40);frames(20);
  tap(72,440);tap(112,260);cycles(10);check(tone==3,"selected instrument option");frames(20);
  touch(1,656,390);frames(260);check(ratio==73562,"bend +2semitones endpoint");
  repeat(12)begin cycles(10000);heartbeat=1;cycles(1);heartbeat=0;end
  check(ratio==73562&&status[31],"stationary touch stays live through healthy polls without new coordinates");
  touch(0,0,0);frames(260);check(ratio==65536,"release returns centre");
  touch(1,144,390);frames(260);check(ratio==58386,"bend -2semitones endpoint");
  error=1;cycles(2);frames(260);check(ratio==65536,"touch fault recentres bend");error=0;
  touch(1,112,260);cycles(10);begin integer old;old=ons;touch(1,160,260);cycles(10);check(ons==old,"fault recovery requires UP");end
  touch(0,0,0);tap(740,128);check(chorus,"chorus enabled");tap(740,128);check(!chorus,"chorus stays disabled");
  tap(740,196);check(wet==128,"mix cycles");tap(740,264);check(depth==2,"depth selection");tap(740,332);check(rate==2,"rate selection");
  tap(112,260);cycles(6);tap(710,40);cycles(30);check(!active&&dut.held==0,"back releases all touch owners");
  tap(500,40);check(active&&!chorus&&wet==128,"reopening retains effects state");
  tap(112,260);cycles(5);menu=1;cycles(30);check(!active&&dut.held==0,"board menu releases harp");menu=0;
  tap(500,40);touch(1,112,260);cycles(5);blocked=1;cycles(3);check(!valid&&dut.held==0,"bluetooth takeover cancels touch owners");
  blocked=0;touch(0,0,0);cycles(100010);check(!status[31],"fresh sensor watchdog expires");
  $display("PASS tb_performance_control checks=%0d ons=%0d offs=%0d",checks,ons,offs);$finish;
 end
 initial begin #20000000;$fatal(1,"performance control timeout");end
endmodule
