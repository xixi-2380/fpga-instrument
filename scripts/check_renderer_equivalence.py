"""Compare every rendered pixel with the previous matching implementation source."""
import hashlib,json,os,pathlib,subprocess
r=pathlib.Path(__file__).resolve().parents[1];out=r/'reports/timing_audio_flash_2026-10-27/renderer_equivalence';out.mkdir(exist_ok=True)
baseline=r/'reports/timing_audio_flash_2026-10-27/attempt2/sources/src/rgb_ui_renderer.sv';actual=r/'src/rgb_ui_renderer.sv'
(out/'baseline_rgb_ui_renderer.sv').write_text(baseline.read_text(encoding='utf8').replace('module rgb_ui_renderer','module baseline_rgb_ui_renderer',1),encoding='utf8')
monitor=r'''
 wire [23:0] baseline_rgb;wire baseline_de,baseline_hs,baseline_vs;
 baseline_rgb_ui_renderer baseline(clk,rst,frame_start,valid,status,x,y,de,1'b1,1'b1,baseline_rgb,baseline_de,baseline_hs,baseline_vs,more_status);
 always @(posedge clk)begin #1;
  if({rgb,de_out,hs_out,vs_out}!=={baseline_rgb,baseline_de,baseline_hs,baseline_vs})
   $fatal(1,"pixel equivalence x=%0d y=%0d actual=%h baseline=%h",x,y,rgb,baseline_rgb);
  pixel_checks++;
 end
'''
bench=(r/'sim/tb_rgb_ui_renderer.sv').read_text(encoding='utf8');i=bench.rfind('endmodule');bench=bench[:i]+monitor+bench[i:]
bench=bench.replace(' rgb_ui_renderer dut',' integer pixel_checks=0;\n rgb_ui_renderer dut',1)
bench=bench.replace('$display("PASS tb_rgb_ui_renderer', '$display("PASS pixel_equivalence comparisons=%0d",pixel_checks);$display("PASS tb_rgb_ui_renderer')
(out/'tb_equivalence.sv').write_text(bench,encoding='utf8')
bins=r/'tools/mingw64/bin';env=os.environ.copy();env['PATH']=str(bins)+os.pathsep+env['PATH']
cmd=[str(bins/'iverilog.exe'),'-g2012','-grelative-include','-Isrc','-Isim','-s','tb_rgb_ui_renderer','-o',str(out/'test.vvp'),actual.as_posix(),(out/'baseline_rgb_ui_renderer.sv').as_posix(),(out/'tb_equivalence.sv').as_posix()]
c=subprocess.run(cmd,cwd=r,env=env,capture_output=True,text=True);(out/'compile.log').write_text(c.stdout+c.stderr,encoding='utf8');assert c.returncode==0,c.stderr
run=subprocess.run([str(bins/'vvp.exe'),str(out/'test.vvp'),'+SIM_OUT_DIR='+out.as_posix()],cwd=r,env=env,capture_output=True,text=True,timeout=600)
(out/'simulation.log').write_text(run.stdout+run.stderr,encoding='utf8')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
result=dict(passed=run.returncode==0 and 'PASS pixel_equivalence' in run.stdout,renderer_sha256=sha(actual),baseline_sha256=sha(baseline),output=run.stdout)
(out/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(run.stdout)
raise SystemExit(0 if result['passed'] else 1)
