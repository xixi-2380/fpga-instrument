import pathlib,subprocess,os,argparse,json,time,re
p=argparse.ArgumentParser();p.add_argument('--pnr',action='store_true');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];out=root/'reports/gowin';out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env['RUN_PNR']='1' if a.pnr else '0'
start=time.monotonic();r=subprocess.run(['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',str(root/'scripts/build.tcl')],cwd=root,env=env,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=600)
log=r.stdout+r.stderr;name='pnr' if a.pnr else 'synthesis';(out/(name+'.log')).write_text(log,encoding='utf8')
errors=[l for l in log.splitlines() if re.search(r'ERROR|Error:|invalid command|can.t (?:find|read)|does not exist',l)]
warnings=[l for l in log.splitlines() if 'WARN' in l]
status=dict(returncode=r.returncode,errors=errors,warnings=warnings,seconds=round(time.monotonic()-start,2),hardware_pin_constraints_signed=False,download_qualified=False)
(out/(name+'.json')).write_text(json.dumps(status,ensure_ascii=False,indent=2),encoding='utf8')
print('\n'.join(log.splitlines()[-55:]));print('BUILD STATUS',json.dumps(status,ensure_ascii=False))
raise SystemExit(0 if r.returncode==0 and not errors else 1)
