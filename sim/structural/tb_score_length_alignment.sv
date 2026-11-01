`timescale 1ns/1ps
module tb_score_length_alignment;
 bluetooth_score_core #(.MAX_NOTES(1)) dut();
 reg [15:0] length_value;reg format_value;reg expected,actual;reg [5:0] expected_count,actual_count;integer checks=0,count_checks=0;
 initial begin
  for(integer fmt=0;fmt<2;fmt=fmt+1)begin
   format_value=fmt!=0;
   for(integer n=0;n<65536;n=n+1)begin
    length_value=n;
    expected=((length_value-32'd2)%(format_value?32'd12:32'd8))==0;
    actual=dut.data_length_aligned(length_value,format_value);checks=checks+1;
    if(actual!==expected)$fatal(1,"length alignment mismatch len=%0d format=%0d",n,fmt);
    // Count is consumed only after the DATA range/alignment rejection branch.
    if(n>=(format_value?14:10) && n<=254 && actual)begin
     expected_count=(length_value-32'd2)/(format_value?32'd12:32'd8);
     actual_count=dut.data_record_count(length_value[7:0],format_value);count_checks=count_checks+1;
     if(actual_count!==expected_count)$fatal(1,"count mismatch len=%0d format=%0d",n,fmt);
    end
   end
  end
  $display("PASS tb_score_length_alignment checks=%0d count_checks=%0d",checks,count_checks);$finish;
 end
endmodule
