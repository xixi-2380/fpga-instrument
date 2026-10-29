// U7 uses standard 24-bit SPI NOR commands. An ID is presence information,
// not a manufacturer allowlist. Hardware locks remain untouched; writes must
// acquire WEL and every programmed page / erased sector is read back.
function automatic nor_identified(input [23:0] id);
 begin nor_identified=id[23:16]!=8'h00 && id[23:16]!=8'hff;end
endfunction
function automatic nor_write_ready(input [23:0] id,input [7:0] sr1);
 begin nor_write_ready=nor_identified(id) && !sr1[0];end
endfunction
