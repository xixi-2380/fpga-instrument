"""Package matching functional release; report STA honestly, never program hardware."""
import argparse,gzip,hashlib,json,pathlib,re,shutil,subprocess
from inspect_timing import inspect
p=argparse.ArgumentParser();p.add_argument('--implementation',default='implementation2');a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];report=r/'reports/sustain_ui_2026-10-29';build=report/a.implementation
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
read=lambda f:json.loads(f.read_text(encoding='utf8'))
def write(f,data):f.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
def verify(path):
 m=read(path);assert all(sha(r/f)==v for f,v in m.items()),'Changed inputs: '+str(path)
 return m
result=read(build/'result.json');assert result['exit_code']==0 and result['sources_unchanged'] and not result['errors']
verify(build/'input_manifest.json');assert 'Bitstream generation completed' in (build/'build.log').read_text(encoding='utf8')
features=read(report/'features_final/latest_run.json');regression=read(report/'regression_final/validation.json');pcb=read(report/'pcb_final2/validation.json')
assert len(features)==25 and all(v['passed'] for v in features) and read(report/'features_final/source_hash_audit.json')['unchanged']
assert regression['passed'] and regression['sources_unchanged'] and len(regression['results'])==18
assert pcb['passed'] and pcb['sources_unchanged'] and len(pcb['results'])==9
for folder in ['features_final','regression_final','pcb_final2']:verify(report/folder/'source_manifest.json')
audio=read(report/'audio_ab_final/validation.json');assert audio['passed'];verify(report/'audio_ab_final/input_manifest.json')
# Production Flash files are unchanged from the already-completed 1MHz full-capacity run.
flash=r/'reports/pcb_flash_debug_2026-10-28/flash_production_1mhz_final'
assert read(flash/'result.json')['passed'];assert all(sha(r/f)==v for f,v in read(flash/'dependency_manifest.json')['files'].items())
original=read(r/'reports/pcb_flash_debug_2026-10-28/source_snapshot.json');source=pathlib.Path(original['source'])
assert all(sha(source/f)==v for f,v in original['files'].items()),'Original project changed'
write(report/'original_integrity.json',dict(source=str(source),files_checked=len(original['files']),unchanged=True))
assert (r/'src/keyboard.sdc').read_bytes()==subprocess.check_output(['git','show','6960804:src/keyboard.sdc'],cwd=r)
assert (r/'src/keyboard.cst').read_bytes()==subprocess.check_output(['git','show','6960804:src/keyboard.cst'],cwd=r)
pins=dict(re.findall(r'IO_LOC "([^"]+)" ([A-Z]+\d+);',(r/'src/keyboard.cst').read_text(encoding='utf8')))
assert len(pins)==len(set(pins.values()))==73 and pins['ec11_sw_n[2]']=='W23'
base=build/'pnr/D2_keyboard_leds';started=read(build/'process.json')['started']
products=[base.with_suffix('.fs'),base.with_suffix('.tr'),base.with_suffix('.rpt.txt'),base.with_suffix('.sdf'),build/'gwsynthesis/D2_keyboard_leds.vg']
assert all(f.is_file() and f.stat().st_mtime>=started-2 for f in products),'Stale implementation output'
assert sha(base.with_suffix('.fs'))==result['bitstream_sha256']==sha(r/'impl/pnr/D2_keyboard_leds.fs')
timing=inspect(base.with_suffix('.tr'));assert all(timing['fmax'][c]['target']==v for c,v in [('ref_clk',50),('audio_clk',61.44),('pixel_clk',35)])
physical=base.with_suffix('.rpt.txt').read_text(encoding='utf8')
for port,ball in pins.items():
 m=re.search(r'^'+re.escape(port)+r'\s*\|\s*[^|]*\|\s*([A-Z]+\d+)/\d+\s*\|\s*(Y|N)',physical,re.M)
 assert m and m[1]==ball and m[2]=='Y',(port,ball)
resources={m[1]:dict(used=float(m[2]),available=int(m[3])) for m in re.finditer(r'^\s*(Logic|Register|BSRAM|DSP|PLL)\s*\|\s*(\d+(?:\.\d+)?)/(\d+)',physical,re.M)}
assert resources['PLL']['used']==3
write(build/'timing_summary.json',timing)
curves=re.findall(r"17'd(\d+):sustain_curve=\{17'd(\d+),17'd(\d+),17'd(\d+)\}",(r/'src/config/sustain_curve.svh').read_text())
assert len(curves)==199
for key,n,q,rem in curves:
 key,n,q,rem=map(int,[key,n,q,rem]);assert key==n and q*n+rem==1<<24 and 0<=rem<n
apk=r/'android/dist/GaoshanScore-0.3.3-pcb-flash-debug.apk'
assert sha(apk)=='7067afa864628c728c603b9ea5e4a80ba73ec537bc0e1f74b654daa305df911e'
dest=r/'dist/sustain-ui-2026-10-29';dest.mkdir(parents=True,exist_ok=True)
copies=[(base.with_suffix('.fs'),'D2_keyboard_leds.fs'),(base.with_suffix('.tr'),'D2_keyboard_leds.tr'),(base.with_suffix('.rpt.txt'),'D2_keyboard_leds.rpt.txt'),(build/'gwsynthesis/D2_keyboard_leds.vg','D2_keyboard_leds.vg'),(r/'src/keyboard.cst','keyboard.cst'),(r/'src/keyboard.sdc','keyboard.sdc'),(apk,apk.name),(r/'docs/延音与新版PCB界面_2026-10-29.md','操作说明.md')]
for src,name in copies:shutil.copy2(src,dest/name)
assert '//SecurityBit: OFF' in (dest/'D2_keyboard_leds.fs').read_text(encoding='ascii',errors='replace')[:3000]
with base.with_suffix('.sdf').open('rb') as src,gzip.open(dest/'D2_keyboard_leds.sdf.gz','wb') as out:shutil.copyfileobj(src,out)
screens=dest/'screenshots';screens.mkdir(exist_ok=True)
from PIL import Image
for f in (report/'pcb_final2/tb_pcb_renderer').glob('*.ppm'):Image.open(f).save(screens/(f.stem+'.png'))
demo=report/'ui_demo'
if (demo/'validation.json').exists():
 assert read(demo/'validation.json')['passed'];verify(demo/'input_manifest.json')
 for f in demo.glob('*.png'):shutil.copy2(f,screens/('example_'+f.name))
for name in ['before.wav','after.wav','comparison.png']:
 f=report/'audio_ab_final'/name
 if f.is_file():shutil.copy2(f,dest/name)
source_manifest={str(f.relative_to(r)):sha(f) for folder in ['src','sim','scripts','android/app/src/main','android/tests'] for f in sorted((r/folder).rglob('*')) if f.is_file() and '__pycache__' not in f.parts}
source_manifest['keyboard_adsr.gprj']=sha(r/'keyboard_adsr.gprj');write(report/'final_source_manifest.json',source_manifest)
summary=dict(functional_validation_passed=True,build_succeeded=True,build_id='26102902',implementation=a.implementation,
 configurations=52,sustain_ms=[20,2000],tremolo_hz=[1,20],physical_voices=32,automatic_ids=16,pins_unique=73,tremolo_sw='W23',
 board_button_roles_preserved=True,original_project_unchanged=True,production_flash_dependency_hashes_match=True,
 timing_convergence_requested=False,timing_passed=timing['setup_hold_pass'] and timing['all_reported_paths_nonnegative'] and timing['pulse_width_pass'],
 timing=timing,resources=resources,audio_ab=audio,hardware_programmed=False,hardware_listening_verified=False,apk_unchanged=True)
write(report/'validation.json',summary)
lines=['# 延音 / 新版PCB界面交付验收','',
 '构建标识26102902。使用D2_keyboard_leds.fs，配套工程位于仓库根目录keyboard_adsr.gprj。',
 '','- 52项配置回归全部通过，源码哈希一致。',
 '- 延音20～2000ms，颤音1～20Hz；颤音A/B/SW=T23/R25/W23。',
 '- 板载按键操作作用保留；诊断APK未改动，沿用0.3.3-pcb-flash-debug。',
 '- 原工程文件未改动；未执行硬件烧录或实板试听。',
 '','## 实际时序结果','',
 '按用户要求没有执行时序收敛，不降频、不放宽普通路径。功能仿真通过不等于时序通过。',
 '',f"Setup违例：{timing['counts']['Setup']}；Hold违例：{timing['counts']['Hold']}。",'',
 '| 时钟 | 目标MHz | 实际Fmax MHz | 内部最差Setup Slack ns |',
 '|---|---|---|---|']
for clock in ['ref_clk','audio_clk','pixel_clk']:
 lines.append(f"| {clock} | {timing['fmax'][clock]['target']} | {timing['fmax'][clock]['actual']} | {timing['internal_wns'].get(clock,'未报告')} |")
lines += ['', 'TNS原始数据：`'+str(timing['tns'])+'`。',
 '', '资源用量：`'+str(resources)+'`。','',
 '## 文件对应关系','',
 'FS、网表VG、TR时序报告、资源/引脚报告与SDF.gz属于同一次匹配构建。CST/SDC为本次约束。SDF使用gzip压缩保存。',
 '',f"位流SHA256：`{sha(dest/'D2_keyboard_leds.fs')}`。",'',
 'before.wav / after.wav是同组快速同键/和弦输入的RTL PCM对照，使用48kHz采样和加速测试时钟，不是实板录音，也不是实板延迟测量。',
 'screenshots中的example图片由已知模拟寄存器值渲染，用于说明界面，不作为实板在线/回读证据。',
 '', '操作步骤见操作说明.md。烧录后先单独开启延音测试快速松键和同键连击，再叠加混响、颤音。']
(dest/'验收与文件说明.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
summary['files']={str(f.relative_to(dest)):sha(f) for f in sorted(dest.rglob('*')) if f.is_file() and f.name!='manifest.json'}
write(dest/'manifest.json',summary)
print('PACKAGE_READY',dest,'TIMING_PASS',summary['timing_passed'],'SLACK',timing['internal_wns'])
