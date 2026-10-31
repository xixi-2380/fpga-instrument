`timescale 1ns/1ps
// Arithmetic/frame-content proof. The original line-level and100Hz tests
// independently check normal builder/driver handshake and WS2812 timing.
module tb_rgb_math_equivalence;
 `include "../src/config/rgb_led_config.svh"
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [15:0] cfg=0;reg [20:0] keys=0;
 wire [519:0] preview;wire data,busy;
 integer checks=0,frames=0;
 rgb_led_controller dut(clk,rst,1'b1,1'b1,cfg,keys,data,busy,preview);
 function automatic [23:0] reference_color(input integer mode,palette,key,offset,input [20:0] held);
  integer wheel,segment,ramp;reg [23:0] color;
  begin
   color=rgb_palette(3'(palette));
   if(mode==2)begin
    wheel=((key+offset)%21)*6;segment=wheel/21;ramp=(wheel%21)*12;
    case(segment)
     0:color={8'd252,8'(ramp),8'd0};1:color={8'(252-ramp),8'd252,8'd0};
     2:color={8'd0,8'd252,8'(ramp)};3:color={8'd0,8'(252-ramp),8'd252};
     4:color={8'(ramp),8'd0,8'd252};default:color={8'd252,8'd0,8'(252-ramp)};
    endcase
   end
   if(mode==3 && !held[key])color=0;
   reference_color=color;
  end
 endfunction
 task sample(input integer percent,phase,mode,palette,en,reverse,offset,input [20:0] held);
  integer level,key;reg [23:0] color,expected;
  begin
   @(negedge clk);
   cfg={1'b0,1'(en),2'(mode),3'(palette),7'(percent),1'(reverse),1'b0};keys=held;
   // Advance directly to an otherwise legal frame opportunity to exhaust
   // arithmetic without waiting500000 clocks and a full serial transfer.
   dut.state=dut.IDLE;dut.pending=1;dut.timer=0;
   dut.breath_phase=phase;dut.rainbow_offset=offset;
   @(posedge dut.start);#1;
   level=en ? percent*255/100:0;
   if(mode==1)level=level*(phase<=100?phase:200-phase)/100;
   if(dut.brightness!==8'(level) || preview[519:504]!==cfg)
    $fatal(1,"Frame brightness/config mismatch percent=%0d phase=%0d mode=%0d",percent,phase,mode);
   checks+=2;
   for(integer n=0;n<21;n++)begin
    key=reverse?20-n:n;color=reference_color(mode,palette,key,offset,held);
    expected={8'((integer'(color[23:16])*(level&255))/255),
              8'((integer'(color[15:8])*(level&255))/255),
              8'((integer'(color[7:0])*(level&255))/255)};
    if(dut.frame[n*24+:24]!==color || preview[n*24+:24]!==expected)
     $fatal(1,"Frame pixel mismatch frame=%0d pixel=%0d actual=%h expected=%h",frames,n,preview[n*24+:24],expected);
    checks+=2;
   end
   frames++;
  end
 endtask
 initial begin
  force dut.busy=1'b0;
  // Compare exact /255 against independent integer arithmetic for every pair.
  for(integer a=0;a<256;a++)for(integer b=0;b<256;b++)begin
   if(dut.dim(8'(a),8'(b))!==8'((a*b)/255))$fatal(1,"Dim mismatch %0d %0d",a,b);
   checks++;
  end
  repeat(3)@(negedge clk);rst=0;
  for(integer percent=0;percent<128;percent++)for(integer phase=0;phase<200;phase++)
   sample(percent,phase,1,phase%8,1,phase%2,0,21'h155555);
  for(integer reverse=0;reverse<2;reverse++)for(integer offset=0;offset<21;offset++)
   sample(37,0,2,0,1,reverse,offset,0);
  for(integer mode=0;mode<4;mode++)for(integer palette=0;palette<8;palette++)begin
   sample(100,99,mode,palette,0,0,20,21'h1fffff);
   sample(100,100,mode,palette,1,1,20,21'h155555);
  end
  for(integer n=0;n<21;n++)begin
   sample(73,0,3,n%8,1,0,0,21'd1<<n);
   sample(73,0,3,n%8,1,1,0,21'd1<<n);
  end
  $display("PASS tb_rgb_math_equivalence checks=%0d frames=%0d",checks,frames);$finish;
 end
 initial begin #30000000;$fatal(1,"RGB math proof timeout");end
endmodule
