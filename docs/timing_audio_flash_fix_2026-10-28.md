# 时序、Flash 与蓝牙复音修复交付

最终实现为 **attempt5**。新工程 `E:\gowin\fpga-instrument-timing-audio-fix\keyboard_adsr.gprj`，来源 `E:\gowin\fpga-instrument-integrated` 保持只读。复制包含原有未提交、未跟踪的键盘、EC11、Flash、ROM、App与工具。本地开发分支 `codex/timing-audio-flash-fix`，依用户后续授权提交并推送至 GitHub 原分支 **codex/integrated-instrument**；不更新main、不强推、不烧录硬件。

## 最终时序与资源

Gowin V1.9.12.04，器件GW5AST-LV138FPG676AC1/I0，Device Version C。源码、综合网表、CST／SDC、STA／SDF、报告与位流属于同一次完整构建，构建输入保持冻结，未使用旧网表或增量布局布线。

| 指标 | 复制后全新基线 | 最终attempt5 |
|---|---:|---:|
| Setup／Hold违例 | 106／0 | 0／0 |
| TNS合计 | −75.801ns | 0 |
| 50MHz参考域内部最差Setup Slack | 3.050ns | 2.305ns |
| 61.44MHz音频域内部最差Setup Slack | −2.999ns | **0.059ns** |
| 35MHz像素域内部最差Setup Slack | −2.445ns | 1.395ns |
| 参考／音频／像素Fmax | 58.998／51.881／32.241MHz | 56.513／61.665／36.796MHz |

建立、保持、恢复、移除、脉宽检查均通过。**原“每个主域余量至少0.5ns”的目标尚未全部达到。** 用户在得知实际指标后确认已达到预期，因此按已认可的“零时序违例、TNS=0、回归通过、构建匹配”标准收尾，保留真实余量，不继续追加结构优化。结论限于现有约束和工具模型；真实Flash、手机与功放仍未实测。

| 资源 | 基线 | 最终 | 器件容量 |
|---|---:|---:|---:|
| Logic | 47,721 | 47,256 | 138,240 |
| Register | 24,428 | 24,716 | 139,140 |
| BSRAM | 169 | 169 | 340 |
| DSP | 122.5 | 123.5 | 298 |
| PLL | 3 | 3 | 12 |

保留73个互不重复球位、32物理声部、16自动身份、36琴键＋12 AUX、七音色、双声道和三效果叠加。50／61.44／35MHz没有降低。第三板INT仍为U22，MAX BCLK仍为V22。

## 修复内容

**Flash保存：** 将原工程已复现的写权限修正落实到新位流。驱动和服务共用`src/config/flash_profile.svh`，不再把SRP／SRL、SEC／TB等配置标志当作数据区保护，仍检查BP、CMP、WPS、BUSY、SUS和每次写入前实际读到的WEL。保持EF4018白名单、0x000000～0x21FFFF曲库范围及SPI速率；不自动解锁、不写状态寄存器、不整片擦除。App提供ID、SR1／2／3、INIT、WRITE、JOB、ERROR和CRC，分别保留“RAM已成功”和“Flash未确认”的阶段事实。

仿真覆盖RAM校验、保存请求、任务查询、WEL、擦除、跨页编程、读回CRC、目录提交和复位载入；包含4096条曲谱的128个数据页、32首满曲库替换、保护条件模型、I/O失败和不同提交阶段的中断。失败不能误报持久保存成功。板上真实ID和错误码仍未知，不能把模型中的0x21误判直接等同于实板根因。

**蓝牙复音：** 保留64采样前瞻、24倍补偿和原释放平滑，生产限幅器增加240采样（5ms）恢复保持。更高峰值立即衰减，保持期只推迟恢复，不按声部数量突然切换增益，孤立单音响度不变。受控16声部同音模型的非线性残差约从2.6832%降至0.0017%；它是相对最佳线性拟合的残差，不是所有音乐的THD，不同和弦并非每项残差都改善，也不是实板无杂音的证明。

限幅器的RAM幅值／峰值比较及滚动增益加减拆拍，最长计算104拍。每个16拍声部时隙前预取声部、频率字、重启标志和音色，DDS仍在原slot0取样。采样使能与软清零在各声部附近保留同相副本；仿真逐时钟核对相位，逐DDS边界核对预取数据。串联效果交付530拍、数学旁路经音量后532拍，低于544拍预算；外部I²S边沿的数字延迟仍为1.37ms。

**键盘／EC11／显示：** 键盘先冻结变化集合，再做有界优先选择与FCW读取，松键优先，背压期间事件稳定。EC11毫秒译码提前准备并在各控制器附近寄存，脉冲与旧译码同相。显示坐标与DE／HS／VS／帧开始同步暂存，字符定位采用有界运算；琴键先选行列再一次着色，波形Y运算限定在真实171～298范围。七幅完整画面与优化前逐输出一致。

LCD通过同源ODDR转发时钟。独立STA慢／快角插入延迟8.362／3.719ns满足6ns参考界限；同次SDF的CLK→Q0→OBUF→引脚最大2.737ns，低于5ns分配。保留20ns转发路由上限。这是经过检查的工程预算，不是面板数据手册或板级测量；未执行整机SDF回标仿真。没有对普通数据路径增加整域false path或降低主时钟频率。

## 最终验证

- 25项功能配置＋33项专项配置全部通过，**75,350,315次显式HDL检查**，涵盖键盘、EC11、七音色、效果、蓝牙身份与尾音、Flash、启动静音、超声波和UI。
- 左右独立限幅／音量模型**18,376项**逐采样比对通过，包含最终I²S；串联效果独立模型**112,372个向量**通过。
- 定时模块五种设置下通过**5,007,520次逐边沿对照**；七幅完整UI通过**2,688,186次逐输出比较**。
- 正弦和大提琴链路分别记录61个SRC、58个NOTE、1,889个I²S字及物理声部、混音、效果、增益和PCM；最终CSV与前面功能一致版本逐字节相同。
- Java协议／连接生命周期／曲库测试**36,114项**通过。诊断APK重新构建，保留原开发证书，versionCode4、版本0.3.1-flashdiag。未安装手机或实测无线链路。
- 原工程229项源码／配置复制前后SHA256一致，见`original_source_integrity.json`。中间未通过、超时或中断记录仅作历史，不计入最终通过数。

报告根目录`reports/timing_audio_flash_2026-10-27`沿用任务开始日期。最终依据为`validation.json`、`timing_resource_comparison.json`、`final_source_manifest.json`与`attempt5`，而非历史位流或早期报告。

## 文件与重现

- 主工程：`keyboard_adsr.gprj`；可烧录文件：`dist/timing-audio-fix/D2_keyboard_leds.fs`，核对同目录`manifest.json`中的SHA256。
- 诊断APK：`android/dist/GaoshanScore-0.3.1-flashdiag.apk`；交付目录含同一APK、综合网表`.vg`、CST／SDC、STA`.tr`、SDF和资源报告。
- `scripts/run_implementation.py --name <新名称>`：完整构建并存档输入。需要本机Gowin，构建期间不要编辑输入。
- `scripts/run_touch_ec11_tests.py --out-dir reports/timing_audio_flash_2026-10-27/regression_features`和`scripts/run_fix_regression.py`：两组回归。本地Icarus、SDK和签名私钥不推送。
- `scripts/check_audio_timing_phase.py`、`scripts/check_renderer_equivalence.py`和`scripts/capture_bt_audio_trace.py --timbre 0`（或3）：相位、逐像素和完整链路记录。
- `scripts/package_timing_audio_fix.py --implementation attempt5 --accept-zero-violation`：本次收尾校验；不会放过任何时序违例或负TNS，并记录原0.5ns目标是否达到。

本地`midi_audition`保留七对前后WAV、逐采样NPZ和峰值／增益摘要，由同一工程MIDI的0～4、25.9～29.9、51.9～55.9、77.9～81.9秒片段拼接，对应1／4／8／16声部。它们是采样域模型，不是实板或完整RTL录音，可用`scripts/render_midi_audition.py`重现。真实HDL短链路记录为`bt_trace_timbre_*/audio_trace.csv`。

## 实板操作与试听

1. 核对SHA256，用Gowin Programmer手动下载当前`.fs`；助手未执行。先确认上电静音、三板琴键与三只EC11，保持既有双功放左右选择接线。
2. 安装诊断APK，读取并复制Flash诊断，记录ID、SR1／2／3、INIT、WRITE、JOB和ERROR。未知型号或真正保护状态不要套用EF4018假设。
3. 下载短曲，确认RAM校验，再保存曲库并等待任务完成。持久保存确认后再断电重启、载入播放；RAM成功而Flash未确认不能视为已保存。
4. 用`android/examples/twinkle_capability_demo.mid`试听七音色、1／4／8／16声部、换和弦、重复同音、短音及效果旁路／叠加，检查停止和暂停静音，保持相同App音量与功放设置。
5. 若数字回归正确而大和弦仍失真，再测功放输入、供电压降、共地、扬声器负载和MAX98357A左右选择。没有实板诊断和试听，不判定这些因素为已知故障，也不宣称所有实板杂音已经消除。
