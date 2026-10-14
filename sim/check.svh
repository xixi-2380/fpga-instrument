`define CHECK(c,m) if ((c) !== 1'b1) begin $display("FAIL %s at %0t",m,$time); $fatal(1); end else checks=checks+1;
