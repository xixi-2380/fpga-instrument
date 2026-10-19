// Twinkle melody, 120 BPM by default; each phrase ends in a two-beat note.
// score_step[7] means two beats; [6:0] is the melody MIDI pitch.
function automatic [7:0] score_step(input [5:0] index);
begin case(index)
6'd0:score_step=8'h3c;
6'd1:score_step=8'h3c;
6'd2:score_step=8'h43;
6'd3:score_step=8'h43;
6'd4:score_step=8'h45;
6'd5:score_step=8'h45;
6'd6:score_step=8'hc3;
6'd7:score_step=8'h41;
6'd8:score_step=8'h41;
6'd9:score_step=8'h40;
6'd10:score_step=8'h40;
6'd11:score_step=8'h3e;
6'd12:score_step=8'h3e;
6'd13:score_step=8'hbc;
6'd14:score_step=8'h43;
6'd15:score_step=8'h43;
6'd16:score_step=8'h41;
6'd17:score_step=8'h41;
6'd18:score_step=8'h40;
6'd19:score_step=8'h40;
6'd20:score_step=8'hbe;
6'd21:score_step=8'h43;
6'd22:score_step=8'h43;
6'd23:score_step=8'h41;
6'd24:score_step=8'h41;
6'd25:score_step=8'h40;
6'd26:score_step=8'h40;
6'd27:score_step=8'hbe;
6'd28:score_step=8'h3c;
6'd29:score_step=8'h3c;
6'd30:score_step=8'h43;
6'd31:score_step=8'h43;
6'd32:score_step=8'h45;
6'd33:score_step=8'h45;
6'd34:score_step=8'hc3;
6'd35:score_step=8'h41;
6'd36:score_step=8'h41;
6'd37:score_step=8'h40;
6'd38:score_step=8'h40;
6'd39:score_step=8'h3e;
6'd40:score_step=8'h3e;
6'd41:score_step=8'hbc;
default:score_step=0;
endcase end
endfunction

// Each melody tone chooses a consonant C, F or G major chord.
function automatic [6:0] score_pitch(input [6:0] melody,input [1:0] lane);
begin
 if(lane==0)score_pitch=melody;
 else if(melody==65 || melody==69)case(lane)
  1:score_pitch=65;2:score_pitch=69;default:score_pitch=72;endcase
 else if(melody==62)case(lane)
  1:score_pitch=67;2:score_pitch=71;default:score_pitch=74;endcase
 else case(lane)
  1:score_pitch=60;2:score_pitch=64;default:score_pitch=67;endcase
end
endfunction

// Fixed 48kHz FCWs, generated offline; independent of the keyboard map.
function automatic [31:0] score_fcw(input [6:0] pitch);
begin case(pitch)
7'd60:score_fcw=32'h016534c3;
7'd62:score_fcw=32'h0190f347;
7'd64:score_fcw=32'h01c20d2f;
7'd65:score_fcw=32'h01dcd01d;
7'd67:score_fcw=32'h02173456;
7'd69:score_fcw=32'h0258bf26;
7'd71:score_fcw=32'h02a250ba;
7'd72:score_fcw=32'h02ca6987;
7'd74:score_fcw=32'h0321e68d;
default:score_fcw=0;
endcase end
endfunction
