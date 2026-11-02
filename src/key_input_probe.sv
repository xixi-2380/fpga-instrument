`timescale 1ns/1ps
// Measurement marker at the reference-domain, qualified keyboard bitmap.
// Does not wait for audio admission; the pulse also operates in menus/mute.
module key_input_probe #(parameter integer PULSE_CYCLES=50000)(
 input wire clk,rst,input wire [35:0] keys,input wire [2:0] valid,
 output reg pulse);
 localparam integer CW=PULSE_CYCLES>1?$clog2(PULSE_CYCLES):1;
 reg [35:0] previous;
 reg [CW-1:0] remaining;
 wire [35:0] qualified=keys & {{12{valid[2]}},{12{valid[1]}},{12{valid[0]}}};
 wire pressed=|(qualified & ~previous);
 always @(posedge clk or posedge rst)begin
  if(rst)begin previous<=0;remaining<=0;pulse<=0;end
  else begin
   previous<=qualified;
   if(pressed)begin pulse<=1;remaining<=PULSE_CYCLES-1;end
   else if(remaining!=0)remaining<=remaining-1'b1;
   else pulse<=0;
  end
 end
 // synthesis translate_off
 initial if(PULSE_CYCLES<1)$fatal(1,"Invalid key input probe pulse width");
 // synthesis translate_on
endmodule
