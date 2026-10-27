"""Compare timing optimizations with the published RTL, without invoking EDA."""
import argparse
import json
import os
from pathlib import Path
import subprocess

BASELINE = 'a1381169c85b772aaec1f3586abf43b5404cd3ac'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = (root / args.out_dir).resolve()
    out.mkdir(parents=True, exist_ok=True)
    bins = root / 'tools/mingw64/bin'
    env = os.environ.copy()
    env['PATH'] = str(bins) + os.pathsep + env['PATH']
    sources = []
    for name in ['adsr_envelope', 'audio_timing']:
        old = subprocess.check_output(
            ['git', 'show', f'{BASELINE}:src/{name}.sv'], cwd=root).decode('utf-8')
        old = old.replace(f'module {name}', f'module baseline_{name}', 1)
        # Each source keeps the same source-relative configuration include.
        old = old.replace('"config/synth_config.svh"',
                          '"' + Path(os.path.relpath(root / 'src/config/synth_config.svh', out)).as_posix() + '"')
        source = out / f'baseline_{name}.sv'
        source.write_text(old, encoding='utf-8')
        sources.extend([root / f'src/{name}.sv', source])
    bench = out / 'tb_timing_equivalence.sv'
    bench.write_text(r'''
`timescale 1ns/1ps
module envelope_equivalence #(parameter A=480,D=4800,R=9600,S=45875)(output reg done=0,output integer checks=0);
 reg clk=0,rst=1,ce=0,on=0,off=0,restart=0,seed_valid=0;
 reg [16:0] seed=0;reg [31:0] random_state=32'h12ab34cd;
 wire [16:0] actual,expected;wire aa,ea;
 always #5 clk=~clk;
 adsr_envelope #(.ATTACK(A),.DECAY(D),.RELEASE(R),.SUSTAIN(S)) dut(
  clk,rst,ce,on,off,actual,aa,restart,seed_valid,seed);
 baseline_adsr_envelope #(.ATTACK(A),.DECAY(D),.RELEASE(R),.SUSTAIN(S)) reference(
  clk,rst,ce,on,off,expected,ea,restart,seed_valid,seed);
 initial begin
  #12;rst=0;
  // Exhaust every legal seed/current level. Compare new quotient and remainder
  // nets with native integer / and %, independently of state-machine branches.
  seed_valid=1;
  for(integer n=0;n<=65536;n=n+1)begin
   @(negedge clk);seed=n;dut.level=n;#1;
   if(dut.attack_base!==(65536-n)/(A>0?A:1) ||
      dut.attack_remainder!==(65536-n)%(A>0?A:1) ||
      dut.release_base!==n/(R>0?R:1) || dut.release_remainder!==n%(R>0?R:1))
    $fatal(1,"ADSR division mismatch A=%0d R=%0d n=%0d",A,R,n);
   checks=checks+4;
  end
  rst=1;#1;@(negedge clk);rst=0;seed_valid=0;seed=0;
  // Consecutive CE pulses, sparse pulses, restart, simultaneous On/Off,
  // cross-profile seeds and long complete production release trajectories.
  for(integer n=0;n<160000;n=n+1)begin
   @(negedge clk);
   random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
   ce=n<30000 || random_state[0];
   on=n<30000 ? n==0 || n==1000 : random_state[7:0]==0;
   off=n<30000 ? n==6000 : random_state[9:2]==0;
   restart=n>=30000 && random_state[12:5]==0;
   seed_valid=random_state[15];seed={1'b0,random_state[31:16]};
   if(n%12001==0)rst=1;else rst=0;
   @(posedge clk);#1;
   if({actual,aa}!=={expected,ea})
    $fatal(1,"ADSR waveform mismatch A=%0d R=%0d cycle=%0d actual=%0d expected=%0d",A,R,n,actual,expected);
   if(dut.state!==reference.state || dut.base!==reference.base ||
      dut.remainder!==reference.remainder || dut.error!==reference.error ||
      dut.remaining!==reference.remaining || dut.length!==reference.length)
    $fatal(1,"ADSR internal segment mismatch A=%0d R=%0d cycle=%0d",A,R,n);
   checks=checks+2;
  end
  done=1;
 end
endmodule
module timing_equivalence #(parameter H=20)(output reg done=0,output integer checks=0);
 reg clk=0,rst=1;always #5 clk=~clk;
 wire ab,ar,af,at,eb,er,ef,et;wire [4:0] ai,ei;
 audio_timing #(.HALF_CYCLES(H)) dut(clk,rst,ab,ar,af,at,ai);
 baseline_audio_timing #(.HALF_CYCLES(H)) reference(clk,rst,eb,er,ef,et,ei);
 initial begin
  #12;rst=0;
  repeat(200000)begin
   @(posedge clk);#1;
   if({ab,ar,af,at,ai}!=={eb,er,ef,et,ei})$fatal(1,"CE/clock phase changed H=%0d",H);
   checks=checks+1;
  end
  // Asynchronous assertion/release at a different phase.
  #2;rst=1;#1;
  if({ab,ar,af,at,ai}!=={eb,er,ef,et,ei})$fatal(1,"async reset mismatch H=%0d",H);
  #14;rst=0;
  repeat(2000)begin
   @(posedge clk);#1;
   if({ab,ar,af,at,ai}!=={eb,er,ef,et,ei})$fatal(1,"reset restart phase changed H=%0d",H);
   checks=checks+1;
  end
  done=1;
 end
endmodule
module tb_timing_equivalence;
 wire [10:0] done;wire [31:0] c[0:10];
 envelope_equivalence e0(done[0],c[0]);
 envelope_equivalence #(.A(4),.D(3),.R(5),.S(32768)) e1(done[1],c[1]);
 envelope_equivalence #(.A(481),.D(4799),.R(9599)) e2(done[2],c[2]);
 envelope_equivalence #(.A(0),.D(0),.R(0),.S(0)) e3(done[3],c[3]);
 envelope_equivalence #(.A(1),.D(1),.R(1),.S(65536)) e4(done[4],c[4]);
 envelope_equivalence #(.A(131072),.D(0),.R(131073)) e5(done[5],c[5]);
 timing_equivalence #(.H(1)) t0(done[6],c[6]);
 timing_equivalence #(.H(2)) t1(done[7],c[7]);
 timing_equivalence #(.H(3)) t2(done[8],c[8]);
 timing_equivalence #(.H(20)) t3(done[9],c[9]);
 timing_equivalence #(.H(37)) t4(done[10],c[10]);
 integer total=0;
 initial begin
  wait(&done);for(integer i=0;i<11;i=i+1)total=total+c[i];
  $display("PASS tb_timing_equivalence checks=%0d envelope_configs=6 clock_dividers=5",total);$finish;
 end
 initial begin #5000000;$fatal(1,"equivalence timeout");end
endmodule
''', encoding='utf-8')
    executable = out / 'tb_timing_equivalence.vvp'
    command = [str(bins / 'iverilog.exe'), '-g2012', '-Wall', '-grelative-include',
               '-s', 'tb_timing_equivalence', '-o', str(executable)]
    command += [s.as_posix() for s in sources + [bench]]
    compile_run = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True)
    (out / 'compile.log').write_text(compile_run.stdout + compile_run.stderr, encoding='utf-8')
    if compile_run.returncode:
        raise RuntimeError(compile_run.stdout + compile_run.stderr)
    run = subprocess.run([str(bins / 'vvp.exe'), str(executable)], cwd=root, env=env,
                         capture_output=True, text=True, timeout=120)
    (out / 'run.log').write_text(run.stdout + run.stderr, encoding='utf-8')
    print(run.stdout + run.stderr)
    passed = run.returncode == 0 and 'PASS tb_timing_equivalence' in run.stdout
    (out / 'summary.json').write_text(json.dumps(dict(
        baseline=BASELINE, passed=passed, eda_run=False), indent=2), encoding='utf-8')
    if not passed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
