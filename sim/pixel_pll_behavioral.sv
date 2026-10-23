`timescale 1ns/1ps
// Test-only fixed 35MHz pixel clock. NOT a vendor PLL/lock/STA model.
module PLL #(parameter FCLKIN="50",IDIV_SEL=1,FBDIV_SEL=1,MDIV_SEL=21,
 ODIV0_SEL=30,CLKFB_SEL="INTERNAL")(
 input wire CLKIN,
 output reg CLKOUT0,
 output wire CLKOUT1,
 output wire CLKOUT2,
 output wire CLKOUT3,
 output wire CLKOUT4,
 output wire CLKOUT5,
 output wire CLKOUT6,
 output wire CLKFBOUT,
 output wire LOCK,
 input wire RESET,
 input wire CLKFB,
 input wire PLLPWD,
 input wire RESET_I,
 input wire RESET_O,
 input wire ENCLK0,
 input wire ENCLK1,
 input wire ENCLK2,
 input wire ENCLK3,
 input wire ENCLK4,
 input wire ENCLK5,
 input wire ENCLK6,
 input wire [5:0] FBDSEL,
 input wire [5:0] IDSEL,
 input wire [6:0] MDSEL,
 input wire [2:0] MDSEL_FRAC,
 input wire [6:0] ODSEL0,
 input wire [2:0] ODSEL0_FRAC,
 input wire [6:0] ODSEL1,
 input wire [6:0] ODSEL2,
 input wire [6:0] ODSEL3,
 input wire [6:0] ODSEL4,
 input wire [6:0] ODSEL5,
 input wire [6:0] ODSEL6,
 input wire [3:0] DT0,
 input wire [3:0] DT1,
 input wire [3:0] DT2,
 input wire [3:0] DT3,
 input wire [2:0] PSSEL,
 input wire PSDIR,
 input wire PSPULSE,
 input wire SSCPOL,
 input wire SSCON,
 input wire [6:0] SSCMDSEL,
 input wire [2:0] SSCMDSEL_FRAC,
 input wire [5:0] ICPSEL,
 input wire [2:0] LPFRES,
 input wire [1:0] LPFCAP);
 initial CLKOUT0=0;
 always #14.285714286 CLKOUT0=~CLKOUT0;
 reg [3:0] qualification=0;
 always @(posedge CLKIN or posedge RESET)begin
  if(RESET)qualification<=0;else if(qualification<8)qualification<=qualification+1'b1;
 end
 assign LOCK=!RESET && qualification==8;
 assign CLKOUT1=1'b0;
 assign CLKOUT2=1'b0;
 assign CLKOUT3=1'b0;
 assign CLKOUT4=1'b0;
 assign CLKOUT5=1'b0;
 assign CLKOUT6=1'b0;
 assign CLKFBOUT=1'b0;
endmodule
