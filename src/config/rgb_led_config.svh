// 21 white keys C4..B6. 31 means no lamp (black/out of range).
function automatic [4:0] rgb_white_index(input [6:0] pitch);
 begin case(pitch)
 7'd60:rgb_white_index=5'd0;
 7'd62:rgb_white_index=5'd1;
 7'd64:rgb_white_index=5'd2;
 7'd65:rgb_white_index=5'd3;
 7'd67:rgb_white_index=5'd4;
 7'd69:rgb_white_index=5'd5;
 7'd71:rgb_white_index=5'd6;
 7'd72:rgb_white_index=5'd7;
 7'd74:rgb_white_index=5'd8;
 7'd76:rgb_white_index=5'd9;
 7'd77:rgb_white_index=5'd10;
 7'd79:rgb_white_index=5'd11;
 7'd81:rgb_white_index=5'd12;
 7'd83:rgb_white_index=5'd13;
 7'd84:rgb_white_index=5'd14;
 7'd86:rgb_white_index=5'd15;
 7'd88:rgb_white_index=5'd16;
 7'd89:rgb_white_index=5'd17;
 7'd91:rgb_white_index=5'd18;
 7'd93:rgb_white_index=5'd19;
 7'd95:rgb_white_index=5'd20;
 default:rgb_white_index=31;endcase end
endfunction
function automatic [23:0] rgb_palette(input [2:0] color);
 begin case(color)
 0:rgb_palette=24'hff0000;1:rgb_palette=24'hff8000;
 2:rgb_palette=24'hffff00;3:rgb_palette=24'h00ff00;
 4:rgb_palette=24'h00ffff;5:rgb_palette=24'h0000ff;
 6:rgb_palette=24'h8000ff;default:rgb_palette=24'hffffff;
 endcase end
endfunction
// Settings: page[15], on[14], mode[13:12], color[11:9], percent[8:2], reverse[1].
localparam [15:0] RGB_DEFAULTS={1'b0,1'b0,2'd0,3'd5,7'd10,1'b0,1'b0};
