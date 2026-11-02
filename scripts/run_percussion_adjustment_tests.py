"""Short App/unchanged-FPGA percussion checks. Run through run_power_guard.py."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time

R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--java-bin',type=Path,default=Path('D:/PyCharm 2025.2.4/jbr/bin'))
    ap.add_argument('--tool-bin',type=Path,default=Path('C:/Users/10939/Documents/Codex/2026-10-30/qin-2/work/sim-tools/mingw64/bin'))
    ap.add_argument('--out-dir',type=Path,default=R/'reports/adjustments_20261101/percussion')
    a=ap.parse_args();out=a.out_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy();env['PATH']=str(a.java_bin)+os.pathsep+str(a.tool_bin)+os.pathsep+env['PATH']
    tracked=list((R/'android/app/src/main/java').rglob('*.java'))+list((R/'android/tests').rglob('*.java'))
    tracked += [R/'src'/n for n in ['dds_sine.sv','instrument_envelope.sv','adsr_envelope.sv','envelope_precalc_bank.sv','score_validator.sv','bt_score_player.sv']]
    tracked += list((R/'src/config').glob('*.svh'))+list((R/'src/rom').glob('*.hex'))+[Path(__file__).resolve()]
    tracked += [R/'sim/integration/tb_percussion_compat.sv',R/'sim/integration/tb_percussion_audio.sv']
    hashes={p.relative_to(R).as_posix():sha(p) for p in tracked};(out/'tested_source_hashes.json').write_text(json.dumps(hashes,indent=2),encoding='utf8')
    tests=[]
    def run(name,cmd,limit=180):
        start=time.monotonic();p=subprocess.run([str(x) for x in cmd],cwd=R,env=env,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=limit)
        log=p.stdout+p.stderr;(out/(name+'.log')).write_text(log,encoding='utf8');print(name,log[-1800:],flush=True)
        if p.returncode:raise RuntimeError(name+' failed')
        return log,round(time.monotonic()-start,3)
    log,seconds=run('java_core',['python','-X','utf8',R/'android/run_core_tests.py','--out-dir',out/'java_core'])
    java=json.loads((out/'java_core/summary.json').read_text(encoding='utf8'));assert java['passed']
    tests.append(dict(name='java_core',passed=True,checks=sum(int(re.search(r': (\d+) checks',x['output'])[1]) for x in java['results']),seconds=seconds))
    log,seconds=run('percussion_java',[a.java_bin/'java.exe','-Dfile.encoding=UTF-8','-cp',out/'java_core/classes','cn.whu.gaoshan.core.PercussionTests',R/'android/examples'])
    tests.append(dict(name='percussion_java',passed=True,checks=int(re.search(r'PASS Percussion: (\d+) checks',log)[1]),seconds=seconds))
    plans=[('tb_percussion_compat',['score_validator.sv','bt_score_player.sv']),('tb_percussion_audio',['dds_sine.sv','instrument_envelope.sv','adsr_envelope.sv','envelope_precalc_bank.sv'])]
    commands={}
    for top,src in plans:
        executable=out/(top+'.vvp');cmd=[a.tool_bin/'iverilog.exe','-g2012','-grelative-include','-I',(R/'src').as_posix(),'-s',top,'-o',executable.as_posix()]+[(R/'src'/p).as_posix() for p in src]+[(R/'sim/integration'/(top+'.sv')).as_posix()]
        commands[top]=[str(x) for x in cmd];run(top+'_compile',cmd)
        log,seconds=run(top,[a.tool_bin/'vvp.exe',executable])
        tests.append(dict(name=top,passed=True,checks=int(re.search(r'PASS '+top+r' checks=(\d+)',log)[1]),seconds=seconds))
    changed=[n for n,v in hashes.items() if sha(R/n)!=v];assert not changed,changed
    baseline=Path('F:/FPGA_Projects/main-board-tested-7d84ac3-20261101')
    fpga_names=['src/dds_sine.sv','src/instrument_envelope.sv','src/config/score_record.svh','src/config/synth_config.svh','src/score_validator.sv','src/bt_score_player.sv','src/bluetooth_score_core.sv','src/bluetooth_audio_bridge.sv','src/voice_allocator.sv','src/pll_pair.sv']
    same={n:dict(current_sha256=sha(R/n),baseline_sha256=sha(baseline/n)) for n in fpga_names}
    assert all(v['current_sha256']==v['baseline_sha256'] for v in same.values())
    artifacts={p.relative_to(R).as_posix():sha(p) for p in (R/'android/examples').glob('*') if p.name.startswith(('gm1_','drums_gong_'))}
    result=dict(all_passed=True,total_checks=sum(t['checks'] for t in tests),tests=tests,hdl_compile_commands=commands,changed_during_run=changed,unchanged_production_percussion_fpga=same,example_sha256=artifacts,radio_or_hardware_tested=False,eda_started=False)
    (out/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(json.dumps(tests,indent=2),flush=True)

if __name__=='__main__':main()
