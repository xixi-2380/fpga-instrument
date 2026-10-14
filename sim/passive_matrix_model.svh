// Independent switch-network model, including propagation through other
// floating columns. This models diode-free ghost paths, not a bitmap shortcut.
module passive_matrix_model(input wire [15:0] pressed,input wire [3:0] selected,
    output reg [3:0] row_n);
 reg [3:0] low_c,low_r;
 always @*begin
  low_c=selected;low_r=0;
  for(integer iteration=0;iteration<8;iteration=iteration+1)
   for(integer r=0;r<4;r=r+1)
    for(integer c=0;c<4;c=c+1)
     if(pressed[r*4+c])begin
      if(low_c[c])low_r[r]=1;
      if(low_r[r])low_c[c]=1;
     end
  row_n=~low_r;
 end
endmodule
