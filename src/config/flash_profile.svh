// W25Q128JV EF4018 array-write policy. SRP/SRL lock STATUS REGISTER writes;
// SEC/TB select geometry when BP!=0. They do not protect an array with BP=000,
// CMP=0 and WPS=0. QE and Security Register LB bits do not protect main data.
// No status register is ever modified here. Individual-lock mode remains rejected.
function automatic w25q128_array_writable(input [7:0] sr1,sr2,sr3);
 begin w25q128_array_writable=(sr1[4:2]==0) && !sr1[0] && !sr2[6] && !sr2[7] && !sr3[2];end
endfunction
