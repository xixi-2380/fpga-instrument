"""Cycle/edge equivalence to copy-time audio timing, including HALF_CYCLES=1."""
import hashlib,json,os,pathlib,subprocess
r=pathlib.Path(__file__).resolve().parents[1];out=r/'reports/pcb_flash_debug_2026-10-28/audio_phase';out.mkdir(exist_ok=True)
old=r/'reports/pcb_flash_debug_2026-10-28/baseline/sources/src/audio_timing.sv'
source=old.read_text().replace('module audio_timing','module baseline_audio_timing',1)
(out/'baseline_audio_timing.sv').write_text(source,encoding='utf8')
bench=r'''
`timescale 1ns/1ps
module timing_case #(parameter H=20)(output reg done=0,output integer checks=0);
 reg clk=0,rst=1;always #5 clk=~clk;
 wire ab,ar,af,at,eb,er,ef,et,pre;wire [4:0] ai,ei;reg replica;
 audio_timing #(.HALF_CYCLES(H)) actual(clk,rst,ab,ar,af,at,ai,pre);
 always @(posedge clk or posedge rst)if(rst)replica<=H==1;else replica<=pre;
 baseline_audio_timing #(.HALF_CYCLES(H)) baseline(clk,rst,eb,er,ef,et,ei);
 always @(clk)begin #1;if({ab,ar,af,at,ai}!=={eb,er,ef,et,ei} || (H==1?(!rst && replica):replica)!==at)$fatal(1,"phase/replica differs H=%0d",H);checks=checks+1;end
 initial begin #12;rst=0;#7491;rst=1;#1;
  if({ab,ar,af,at,ai}!=={eb,er,ef,et,ei})$fatal(1,"async reset phase H=%0d",H);
  #18;rst=0;repeat(500000)@(negedge clk);done=1;
 end
endmodule
module tb_phase;
 wire [4:0] done;wire [31:0] count[0:4];
 for(genvar n=0;n<5;n=n+1)begin:c
  localparam H=n==0?1:n==1?2:n==2?4:n==3?20:31;
  timing_case #(.H(H)) dut(done[n],count[n]);
 end
 initial begin wait(&done);#2;$display("PASS audio timing phase checks=%0d HALF=1,2,4,20,31",count[0]+count[1]+count[2]+count[3]+count[4]);$finish;end
endmodule
'''
(out/'tb_phase.sv').write_text(bench,encoding='utf8')
bins=r/'tools/mingw64/bin';env=os.environ.copy();env['PATH']=str(bins)+os.pathsep+env['PATH']
compile=subprocess.run([str(bins/'iverilog.exe'),'-g2012','-grelative-include','-I'+(r/'src').as_posix(),'-s','tb_phase','-o',str(out/'phase.vvp'),(r/'src/audio_timing.sv').as_posix(),(out/'baseline_audio_timing.sv').as_posix(),(out/'tb_phase.sv').as_posix()],cwd=r,env=env,capture_output=True,text=True)
(out/'compile.log').write_text(compile.stdout+compile.stderr,encoding='utf8');assert compile.returncode==0,compile.stderr
run=subprocess.run([str(bins/'vvp.exe'),str(out/'phase.vvp')],cwd=r,env=env,capture_output=True,text=True,timeout=120)
(out/'phase.log').write_text(run.stdout+run.stderr,encoding='utf8')
result=dict(passed=run.returncode==0 and 'PASS audio timing phase' in run.stdout,baseline_sha256=hashlib.sha256(old.read_bytes()).hexdigest(),actual_sha256=hashlib.sha256((r/'src/audio_timing.sv').read_bytes()).hexdigest(),output=run.stdout)
(out/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(run.stdout)
raise SystemExit(0 if result['passed'] else 1)
