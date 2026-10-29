function automatic [4:0] score_drum(input [7:0] k);begin case(k)
35,36:score_drum=16;37,38,40:score_drum=17;39:score_drum=18;42,44:score_drum=19;46:score_drum=20;41,43:score_drum=21;45,47:score_drum=22;48,50:score_drum=23;49,52,55,57:score_drum=24;51,53,59:score_drum=25;default:score_drum=31;endcase end endfunction
function automatic [15:0] score_drum_ms(input [4:0] t);begin case(t)
16:score_drum_ms=250;17:score_drum_ms=180;18:score_drum_ms=140;19:score_drum_ms=80;20:score_drum_ms=450;21:score_drum_ms=350;22:score_drum_ms=300;23:score_drum_ms=250;24:score_drum_ms=1500;default:score_drum_ms=1000;endcase end endfunction
// Included inside validators. Format 0 is the original 8-byte record.
function automatic score_record_valid(input [95:0] r,input bit extended);
 reg melodic;begin
 melodic=!extended || r[71:64]<16;
 score_record_valid=r[47:40]>=1 && r[47:40]<=127 && r[63:48]!=0 &&
 (melodic ? (r[39:32]>=NOTE_MIN && r[39:32]<=NOTE_MAX) :
  ((r[39:32]>=35 && r[39:32]<=53)||r[39:32]==55||r[39:32]==57||r[39:32]==59)) &&
 (!extended || (r[71:64]<=25 && r[79:72]<=15 && r[95:80]==0 &&
 ((r[71:64]>=16)==(r[79:72]==9)) && (melodic || (r[71:64]==score_drum(r[39:32]) && r[63:48]==score_drum_ms(r[68:64])))));
 end endfunction
