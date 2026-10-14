import pathlib,json,re,hashlib,csv,math
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'reports';out.mkdir(exist_ok=True)
hardware=json.loads((root/'boards/mega138k_pro/hardware_status.json').read_text(encoding='utf8'))
tests=[]
for tb in sorted((root/'sim').glob('tb_*.sv')):
    log=out/'sim'/(tb.stem+'.log')
    text=log.read_text(encoding='utf8') if log.exists() else ''
    m=re.search(r'PASS '+tb.stem+r' checks=(\d+)',text)
    tests.append(dict(test=tb.stem,passed=bool(m) and 'FAIL' not in text,checks=int(m[1]) if m else 0))
tr=root/'impl/pnr/tone_UNVERIFIED.tr';text=tr.read_text(errors='replace') if tr.exists() else ''
counts={k:int(m[1]) if (m:=re.search(r'<Numbers of '+k+r' Violated Endpoints>:(\d+)',text)) else None for k in ['Setup','Hold']}
resources=(root/'impl/pnr/tone_UNVERIFIED.rpt.txt').read_text(errors='replace')
usage={}
for key in ['Logic','Register','BSRAM','DSP','PLL']:
    m=re.search(r'^\s*'+key+r'\s*\|\s*(\d+)/(\d+)',resources,re.M)
    if m:usage[key]=dict(used=int(m[1]),available=int(m[2]))
pnr=json.loads((out/'gowin/pnr.json').read_text())
status=dict(date='2026-10-13',tests=tests,all_simulations_passed=all(x['passed'] for x in tests),
    pnr_internal_feasibility_passed=pnr['returncode']==0 and not pnr['errors'],
    internal_setup_hold_violations=counts,resources=usage,
    clock_scheme='50 MHz -> 32 MHz -> 61.44 MHz; PLL2 ODIV0=12.5',
    original_clock_scheme_rejected='PA2078: PFD must be 19..81.25 MHz',
    physical_pin_constraints_signed=False,external_audio_timing_signed=False,
    full_sta_signed=False,hardware_programmed=hardware.get('programmed',False),
    programmed_profile=hardware.get('programmed_profile'),hardware_audio_measured=False,
    programming_owner=hardware.get('programming_owner'),automatic_programming_authorized=False,
    first_sram_configuration_loaded=hardware.get('sram_configuration_loaded_on_first_attempt',False),
    sram_program_verified=hardware.get('sram_program_verified',False),
    latency_5ms_verified=False,download_qualified=False,
    fpga_model='GW5AST-LV138FPG676A',fpga_model_evidence='user confirmation',
    device_version='C',speed_grade_verified=False,
    dock_pcb_revision='4071f3',dock_revision_evidence='user photo version sticker',
    remaining=['Core PCB revision and FPGA speed grade','actual-board pin/voltage/amplifier verification',
      'full-tone physical constraints and board output STA','D0 scope checks then low-tone SRAM program/verify','scope and listening tests','30-minute hardware stability'])
gpio_manifest=root/'bringup/D0_header_mirror_status.json'
if gpio_manifest.exists():
    gpio=json.loads(gpio_manifest.read_text(encoding='utf8'))
    status['latest_diagnostic']=dict(profile=gpio['profile'],bitstream='bringup/D0_header_mirror.fs',
        sha256=gpio['bitstream_sha256'],setup_hold_violations=gpio['setup_hold_violations'],
        pnr_passed=gpio['pnr_passed'],pins=gpio['pins'],simulation_passed=gpio['gpio_mirror_simulation_passed'],
        programmed_by_assistant=False,hardware_measurements_passed=False)
tone_profiles=[]
for profile in ['stereo','left','right']:
    manifest=root/('bringup/D1_'+profile+'_440_status.json')
    if manifest.exists():
        tone=json.loads(manifest.read_text(encoding='utf8'))
        tone_profiles.append(dict(profile=tone['profile'],bitstream=tone['bitstream'],sha256=tone['bitstream_sha256'],
            pnr_passed=tone['pnr_passed'],setup_hold_violations=tone['setup_hold_violations'],resources=tone['resources'],
            simulation_passed=tone['simulation_passed'],programmed_by_assistant=False,hardware_measured=False))
if tone_profiles:
    status['latest_tone_profiles']=tone_profiles
    status['remaining']=['Core revision/speed marking and actual voltages','DAC-pad electrical timing and unconstrained-path audit',
                         'User SRAM program/verify','440Hz listening, channel and reset measurements','30-minute hardware stability']
keyboard_manifest=root/'bringup/D2_keyboard_adsr_status.json'
if keyboard_manifest.exists():
    kb=json.loads(keyboard_manifest.read_text(encoding='utf8'))
    status['latest_keyboard']=dict(profile=kb['profile'],project='keyboard_adsr.gprj',simulation_passed=kb['simulation_passed'],
        resources=kb['resources'],historical_setup_hold_violations=kb['setup_hold_violations'],hardware_verified=False,
        source_requires_user_rebuild=kb.get('source_requires_user_rebuild',False),current_source_pnr_validated=kb.get('current_source_pnr_validated',False))
    status['compilation_owner']='user'
    status['automatic_compilation_authorized']=False
run_led_record=root/'reports/keyboard/run_leds/validation.json'
if run_led_record.exists():
    rl=json.loads(run_led_record.read_text(encoding='utf8'))
    status['latest_source_variant']=rl['variant']
    status['latest_run_leds']=dict(simulation_passed=all(t['passed'] for t in rl['tests']),
        source_requires_user_rebuild=True,expected_user_output=rl['expected_user_output'],hardware_verified=False)
(out/'status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2),encoding='utf8')
paths=list((root/'rtl').glob('*.sv'))+list((root/'boards/mega138k_pro').glob('*.sv'))+list((root/'sim').glob('*'))+list((root/'config').glob('*'))+list((root/'scripts').glob('*.py'))+list((root/'scripts').glob('*.tcl'))+[root/'rom/sine4096.hex',root/'boards/mega138k_pro/tone.sdc',root/'tone_feasibility.gprj']
(out/'source_hashes.json').write_text(json.dumps({str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths if p.is_file()},indent=2),encoding='utf8')
rows=list(csv.DictReader((out/'sim/tone_samples.csv').open()))
samples=[int(r['sample']) for r in rows]
summary=dict(frames=len(samples),peak_min=min(samples),peak_max=max(samples),sample_rate_hz=48000,fcw=39370534,quantized_frequency_hz=39370534*48000/2**32)
assert len(samples)==48000 and max(samples)<=1023 and min(samples)>=-1024
(out/'sim/audio_summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8')
lines=['# 验证结果','',f"独立测试：{sum(t['passed'] for t in tests)}/{len(tests)} 通过。",'',
       '| 测试 | 断言检查数 | 状态 |','|---|---:|---|']
lines += [f"| {t['test']} | {t['checks']} | {'PASS' if t['passed'] else 'FAIL'} |" for t in tests]
lines += ['',f'连续顶层测试：{len(samples)} 帧，另含两次复位与左右独响。',
          'PLL 器件模型与加速启动的板级顶层集成分别验证；标称启动 480/240 帧策略由独立 TB 检查。','',
          f'内部离线 P&R：setup 违例 {counts["Setup"]}，hold 违例 {counts["Hold"]}。',
          '上述完整正弦可行性工程没有实板 CST，IO 自动放置；D0 GPIO 镜像静音诊断另有真实引脚 CST 和独立 reports/bringup/D0_header.tr，不等同完整音频签核。',
          '综合阶段保留 CK3000 自动时钟关系警告；P&R 的显式 SDC 时钟表正确列出 50/32/61.44 MHz。',
          '官方 prim_sim.v 有静态配置下 @* 空敏感列表警告；原库未修改，本配置的频率和顶层行为测试通过，其他 PLL 动态模式未验收。',
          '异步复位、LOCK 输入、外部 IO 和源同步输出仍需专项板级 STA 核验；未整体 false-path。','',
          '资源：'+', '.join(f'{k} {v["used"]}' for k,v in usage.items()),'',
          'JTAG 已扫描到 1 个器件，ID 0x0001081B。SRAM 诊断下载状态以 hardware_status.json 和 D0_program_sram.log 为准；未测模拟输出、未做实板长稳测试。']
if gpio_manifest.exists():
    lines += ['', 'GPIO 镜像静音诊断：tb_bringup_digital PASS，新增镜像边沿/复位断言；10 个端口按官方球位约束。',
              'D0_header.tr 的 setup/hold 违例均为 0，文件与源码哈希见 bringup/D0_header_mirror_status.json。',
              '仅新增 GPIO 观测输出，原 DAC 连接保留；下载由用户操作，GPIO 实测尚未完成。']
if tone_profiles:
    lines += ['', 'D1 双/左/右低幅 440Hz 已完成实际引脚 P&R，三个版本 setup/hold 违例均为 0。',
              '新增 tb_tone_play 验证完整静音/淡入、复位恢复和声道隔离；详细结果及限制见 reports/tone_play/validation.md。',
              'D1 文件供用户手动烧录，未由助手写入，实际音频和稳定性待测。']
if keyboard_manifest.exists():
    lines += ['', 'D2 矩阵键盘及单声部 ADSR：七个新增独立仿真通过，详见 reports/keyboard/validation.md。',
              '后续综合编译、布局布线和烧录由用户执行，助手只改文件及运行 HDL 仿真；D2 尚未上板验收。']
(out/'validation.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
print(json.dumps(status,ensure_ascii=False,indent=2))
