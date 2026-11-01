`timescale 1ns/1ps
module tb_bend_width_exhaustive;
 function automatic [17:0] old_ratio(input [15:0] x);
  if(x<=144)old_ratio=58386;
  else if(x>=656)old_ratio=73562;
  else if(x>=400)old_ratio=18'd65536+18'(((x-16'd400)*32'd8026)>>8);
  else old_ratio=18'd65536-18'(((16'd400-x)*32'd7150)>>8);
 endfunction
 function automatic [17:0] new_ratio(input [15:0] x);
  reg [7:0] up,down;reg [20:0] up_product,down_product;
  begin
   up=x[7:0]-8'd144;down=8'd144-x[7:0];up_product=up*13'd8026;down_product=down*13'd7150;
   if(x<=144)new_ratio=58386;
   else if(x>=656)new_ratio=73562;
   else if(x>=400)new_ratio=18'd65536+{5'd0,up_product[20:8]};
   else new_ratio=18'd65536-{5'd0,down_product[20:8]};
  end
 endfunction
 initial begin
  for(integer x=0;x<65536;x=x+1)if(old_ratio(x)!==new_ratio(x))$fatal(1,"ratio mismatch x=%0d old=%0d new=%0d",x,old_ratio(x),new_ratio(x));
  $display("PASS tb_bend_width_exhaustive checks=65536");$finish;
 end
endmodule
