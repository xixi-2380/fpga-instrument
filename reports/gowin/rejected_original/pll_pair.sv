`timescale 1ns/1ps
// Explicit GW5AST-138 PLL primitive wrapper. Coefficients from UG306.
// IP legality and global routing must be checked by Gowin P&R.
module pll_pair(input wire ref_clk,rst,pll2_rst,
    output wire mid_clk,audio_clk,lock1,lock2);
    PLL #(.FCLKIN("50"),.IDIV_SEL(5),.FBDIV_SEL(1),.MDIV_SEL(96),
        .ODIV0_SEL(10),.CLKFB_SEL("INTERNAL")) pll1(
        .CLKIN(ref_clk),.CLKOUT0(mid_clk),.CLKOUT1(),.LOCK(lock1),.RESET(rst),
        .CLKFB(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .ENCLK0(1'b1),.ENCLK1(1'b0),.ENCLK2(1'b0),.ENCLK3(1'b0),
        .ENCLK4(1'b0),.ENCLK5(1'b0),.ENCLK6(1'b0),
        .FBDSEL(6'b0),.IDSEL(6'b0),.MDSEL(7'b0),.MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0),.ODSEL0_FRAC(3'b0),.ODSEL1(7'b0),.ODSEL2(7'b0),
        .ODSEL3(7'b0),.ODSEL4(7'b0),.ODSEL5(7'b0),.ODSEL6(7'b0),
        .DT0(4'b0),.DT1(4'b0),.DT2(4'b0),.DT3(4'b0),
        .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),
        .SSCON(1'b0),.SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),
        .ICPSEL(6'b0),.LPFRES(3'b0),.LPFCAP(2'b0));
    PLL #(.FCLKIN("96"),.IDIV_SEL(25),.FBDIV_SEL(5),.MDIV_SEL(64),
        .ODIV0_SEL(20),.CLKFB_SEL("INTERNAL")) pll2(
        .CLKIN(mid_clk),.CLKOUT0(audio_clk),.CLKOUT1(),.LOCK(lock2),.RESET(pll2_rst),
        .CLKFB(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .ENCLK0(1'b1),.ENCLK1(1'b0),.ENCLK2(1'b0),.ENCLK3(1'b0),
        .ENCLK4(1'b0),.ENCLK5(1'b0),.ENCLK6(1'b0),
        .FBDSEL(6'b0),.IDSEL(6'b0),.MDSEL(7'b0),.MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0),.ODSEL0_FRAC(3'b0),.ODSEL1(7'b0),.ODSEL2(7'b0),
        .ODSEL3(7'b0),.ODSEL4(7'b0),.ODSEL5(7'b0),.ODSEL6(7'b0),
        .DT0(4'b0),.DT1(4'b0),.DT2(4'b0),.DT3(4'b0),
        .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),
        .SSCON(1'b0),.SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),
        .ICPSEL(6'b0),.LPFRES(3'b0),.LPFCAP(2'b0));
endmodule
