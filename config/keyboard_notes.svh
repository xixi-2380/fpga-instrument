function automatic [31:0] key_fcw(input [3:0] key);
begin case(key)
4'd0:key_fcw=32'h016534C3; // MIDI 60
4'd1:key_fcw=32'h017A725A; // MIDI 61
4'd2:key_fcw=32'h0190F347; // MIDI 62
4'd3:key_fcw=32'h01A8CAC3; // MIDI 63
4'd4:key_fcw=32'h01C20D2F; // MIDI 64
4'd5:key_fcw=32'h01DCD01D; // MIDI 65
4'd6:key_fcw=32'h01F92A6D; // MIDI 66
4'd7:key_fcw=32'h02173456; // MIDI 67
4'd8:key_fcw=32'h02370783; // MIDI 68
4'd9:key_fcw=32'h0258BF26; // MIDI 69
4'd10:key_fcw=32'h027C780B; // MIDI 70
4'd11:key_fcw=32'h02A250BA; // MIDI 71
4'd12:key_fcw=32'h02CA6987; // MIDI 72
4'd13:key_fcw=32'h02F4E4B4; // MIDI 73
4'd14:key_fcw=32'h0321E68D; // MIDI 74
4'd15:key_fcw=32'h03519586; // MIDI 75
default:key_fcw=32'h016534C3;
endcase end
endfunction
