`timescale 1ns/1ps
module tb_keymap_flash;
 reg clk=0;always #5 clk=~clk;reg rst=1;reg save=0;wire ready,lv;reg lr=1;wire [575:0] loaded;reg [591:0] data=0;wire [31:0] status;
 wire busy,fv,fr,fd,bw;wire [1:0] op;wire [23:0] addr;wire [8:0] len;wire [7:0] error,bi,bd,ri,rd;reg fail=0;
 reg [23:0] jedec=24'hef4018;integer checks=0;reg [575:0] first_map;
 flash_keymap d(clk,rst,1'b1,1'b1,1'b1,jedec,save,ready,data,lv,lr,loaded,status,busy,fv,fr,op,addr,len,fd,error,bw,bi,bd,ri,rd);
 buffered_nor_model #(.BYTES('h222000)) model(clk,rst,fv,fr,op,addr,len,fd,error,fail,bw,bi,bd,ri,rd);
 task check(input bit b,input [255:0] why);begin checks++;if(!b)$fatal(1,"%0s status=%h state=%d",why,status,d.state);end endtask
 task boot;begin @(negedge clk);rst=1;repeat(4)@(negedge clk);rst=0;while(!ready && !(!busy && status[29]==0))@(negedge clk);end endtask
 task start_save(input [575:0] map,input [15:0] id);begin @(negedge clk);data={id,map};save=1;while(!ready)@(negedge clk);@(negedge clk);save=0;end endtask
 task wait_job;begin while(busy)@(negedge clk);end endtask
 initial begin
  boot();check(model.programs==0 && model.erases==0,"boot read only");check(status[27:26]==0,"blank defaults");first_map=loaded;first_map[15:0]={8'd9,8'd21};
  start_save(first_map,1);wait_job();check(status[17:16]==2,"save commit");check(model.programs==2 && model.erases==1,"body then commit");
  boot();check(loaded==first_map,"reset loads config");check(model.programs==2,"reset no migration write");
  data[31:16]={8'd15,8'd108};start_save(data[575:0],2);wait(d.state==d.PROGRAM);@(negedge clk);rst=1;repeat(4)@(negedge clk);rst=0;while(busy)@(negedge clk);check(loaded==first_map,"power cut preserves old");
  start_save(first_map,3);wait(d.state==d.PROGRAM);@(negedge clk);fail=1;wait_job();check(status[17:16]==3,"write failure visible");fail=0;
  boot();check(loaded==first_map,"failure preserves saved map");
  // Inject actual body and commit power cuts at the NOR mutation boundary.
  for(integer cut=0;cut<3;cut++)begin
   start_save(first_map,16'(4+cut));
   if(cut==0)wait(model.active && model.operation==3 && model.index==200);
   else if(cut==1)wait(model.active && model.operation==2 && model.location[11:0]==0 && model.index==40);
   else wait(model.active && model.operation==2 && model.location[11:0]==84 && model.index==2);
   boot();check(loaded==first_map,"torn sector/body/commit recovery");
  end
  start_save(first_map,7);wait(d.state==d.READ && !d.boot_scan);model.memory['h221008]=0;
  wait_job();check(status[17:16]==3 && status[25:18]==9,"readback mismatch reported");
  boot();check(loaded==first_map,"readback mismatch preserves old");
  // Corrupt the committed CRC; boot must fall back without repairing Flash.
  model.memory['h220050]=model.memory['h220050]^8'h01;boot();check(status[27:26]==2,"corrupt config flagged");
  jedec=24'hef4015;boot();check(!status[29] && status[27:26]==3,"small chip RAM only");
  $display("PASS tb_keymap_flash checks=%0d (save/reboot/power cut/failure/corruption/capacity)",checks);$finish;
 end
 initial begin #50000000;$fatal(1,"timeout");end
endmodule
