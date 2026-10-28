// C4..B6, rounded phase increments at 48kHz.
function automatic [31:0] key_fcw(input [5:0] key);
 begin case(key)
  6'd0:key_fcw=32'd23409859;
  6'd1:key_fcw=32'd24801882;
  6'd2:key_fcw=32'd26276679;
  6'd3:key_fcw=32'd27839171;
  6'd4:key_fcw=32'd29494575;
  6'd5:key_fcw=32'd31248413;
  6'd6:key_fcw=32'd33106541;
  6'd7:key_fcw=32'd35075158;
  6'd8:key_fcw=32'd37160835;
  6'd9:key_fcw=32'd39370534;
  6'd10:key_fcw=32'd41711627;
  6'd11:key_fcw=32'd44191930;
  6'd12:key_fcw=32'd46819719;
  6'd13:key_fcw=32'd49603764;
  6'd14:key_fcw=32'd52553357;
  6'd15:key_fcw=32'd55678342;
  6'd16:key_fcw=32'd58989149;
  6'd17:key_fcw=32'd62496826;
  6'd18:key_fcw=32'd66213081;
  6'd19:key_fcw=32'd70150316;
  6'd20:key_fcw=32'd74321671;
  6'd21:key_fcw=32'd78741067;
  6'd22:key_fcw=32'd83423255;
  6'd23:key_fcw=32'd88383859;
  6'd24:key_fcw=32'd93639437;
  6'd25:key_fcw=32'd99207528;
  6'd26:key_fcw=32'd105106715;
  6'd27:key_fcw=32'd111356685;
  6'd28:key_fcw=32'd117978298;
  6'd29:key_fcw=32'd124993653;
  6'd30:key_fcw=32'd132426162;
  6'd31:key_fcw=32'd140300631;
  6'd32:key_fcw=32'd148643341;
  6'd33:key_fcw=32'd157482134;
  6'd34:key_fcw=32'd166846509;
  6'd35:key_fcw=32'd176767719;
  default:key_fcw=32'd0;
 endcase end
endfunction
