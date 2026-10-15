# Tang Mega 138K Pro：键盘与 PT8211 音频工程

工作目录：`E:\gowin\fpga-instrument`。唯一工程入口：[keyboard_adsr.gprj](keyboard_adsr.gprj)，顶层 `keyboard_top`，输出 `D2_keyboard_leds`。Device Version C；实际速度等级仍待核验。

当前为4×4矩阵键盘、四声部正弦复音、独立ADSR和六颗状态/运行灯。U4内部下拉修复启动等待后，用户反馈“现在正常了”。底噪已由用户确认为耳机阻抗过低，不作软件处理；单声部分离版已实板通过，用户已选择下一阶段四声部；本次不扩展32声部、音色或UI。

## 操作

1. 先读 [AGENTS.md](AGENTS.md)，接口见 [docs/interfaces.md](docs/interfaces.md)，模块见 [docs/modules.md](docs/modules.md)。
2. 用户打开本目录 keyboard_adsr.gprj，自行综合、布局布线及烧录；预期输出 `impl/pnr/D2_keyboard_leds.fs`，本次结构重排没有生成新下载文件；现有实现结果属于此前源码。
3. 按 [流水灯排查说明](docs/bringup_run_leds.md) 依次记录 LED0～3、LED4 和单按 A4 时 LED5，检查启动、音符响应；当前启动故障已获用户反馈恢复。
4. 直接修改对应原文件，不建立重复版本；用户提示后才提交 Git，不自动推送。

## 文件职责

| 路径 | 用途 |
|---|---|
| `src/` | 当前顶层、全部可综合模块及keyboard.cst/keyboard.sdc |
| `src/config/`、`src/rom/` | 参数头文件、音符表及正弦ROM；已登记在IDE文件列表 |
| `docs/hardware/` | 原硬件状态、键位表、音符记录和完整引脚清单 |
| `sim/` | 当前模块和板级 HDL 测试 |
| `scripts/` | HDL 仿真、ROM/工具准备及用户使用的键盘构建脚本 |
| `impl/keyboard_adsr_process_config.json` | 当前 Gowin 工程配置；其余实现输出按需生成 |
| `references/`、`reports/hardware/photos/` | 官方资料和原始照片，只读保留 |
| `reports/` | 原始错误日志、历史证据及新验证记录 |
| `docs/archive/` | 原文件迁入的历史 D0/D1 说明与旧交接，不作为当前操作入口 |
| `tools/manifest.json`、`tools/mingw64/` | 模拟器来源与本机运行环境 |

## 仿真

在工程根目录执行：

```powershell
& 'D:\py\python.exe' scripts/run_sim.py
& 'D:\py\python.exe' scripts/run_sim.py --test tb_keyboard_top --vendor
& 'D:\py\python.exe' scripts/run_keyboard_pinmap.py
```

默认仿真日志和端到端 CSV 写入 `reports/sim/current/`，引脚映射结果写入 `reports/keyboard/pinmap_current/`。可用 `--out-dir` 指定另一目录，避免覆盖上次结果。器件 PLL 独立测试可使用 `--test tb_pll_pair --vendor`。

需要脚本构建时，由用户自行运行 `scripts/build_keyboard.py`；它直接读取现有主工程，不重新生成工程、不依赖旧工程。其默认读取 `reports/sim/current/` 的验证日志，可用 `--sim-dir` 指定目录；构建报告写入 `reports/keyboard/current/`，手动交付目录 `bringup/` 仅在打包时生成。助手不运行该构建脚本。

## 历史与边界

旧工程入口、旧 D0/D1 专用模块和工具脚本、历史下载 `.fs`、模拟器安装缓存及可再生 `.vvp` 已从当前工作目录移除。共享音频模块、必要原始错误日志、资料、照片和下载状态仍保留。原工程 `E:\gowin\fpga-instrument-mega138k-pro` 未修改；完整迁移基线可从 Git `3e1e93b` 查阅，历史下载文件可从原目录获取。

历史报告可能包含已移除文件的路径、哈希及旧输出名，仅用于对应历史版本。仿真通过不能代替当前工程的实现时序和实板音频验收。清理及验证记录见 `docs/change_log.md` 和 `reports/cleanup/validation.json`。

当前引脚已按用户指定 CST 核对：时钟 P16 上拉，逻辑 LED0/1 为 R26/J14；二者与 4071f3 图纸 LED0/1 名称相反。其他音频、键盘及测量球位不变；PA_EN=H17 使用板版原理图补充。准确灯号表见 docs/bringup_run_leds.md。

## 在高云 IDE 中修改

参照用户提供的fpga_project_test工程布局，当前结构为：

```text
fpga-instrument/
├─ keyboard_adsr.gprj          唯一主工程入口
├─ src/
│  ├─ keyboard_top.sv         顶层
│  ├─ clock_reset.sv、pll_pair.sv
│  ├─ 其他功能模块.sv
│  ├─ keyboard.cst、keyboard.sdc
│  ├─ config/                四个参数头文件
│  └─ rom/                   sine4096.hex及原manifest
├─ impl/                     IDE配置与用户生成的实现结果
├─ sim/、scripts/            HDL测试及脚本
└─ docs/、reports/、references/、tools/
```

关闭并重新打开 `E:\gowin\fpga-instrument\keyboard_adsr.gprj`。在IDE文件列表中双击 `src/keyboard_top.sv` 修改顶层，双击功能模块修改RTL，双击CST/SDC编辑约束；参数头文件和正弦HEX也已作为辅助文件登记，避免另找一份源码。

顶层仍为keyboard_top，器件仍为GW5AST-LV138FPG676AC1/I0（C版），SystemVerilog 2017，include路径为src与src/config，HDL使用相对于原文件的config/*.svh引用。辅助头文件不作为独立模块综合。旧IDE流程状态已清空，UI布局保留；由用户重新实现确认。C:\Gowin下参考工程未修改。

src布局调整时的历史验证见reports/ide_layout/validation.json；当时的PLL/复位诊断功能保留。后续U4下拉已获用户启动恢复反馈，底噪按耳机阻抗结论关闭；历史报告中的旧路径保持原样。

2026-10-14头文件报错修复：实际失败配置仍指向已移走的根目录config，导致EX5985/EX3755及后续未定义宏、语法连锁错误。已修正原过程配置和源文件引用，并去掉仿真的配置头文件搜索路径，改用源文件相对解析。关闭IDE中的当前工程，再重新打开根目录keyboard_adsr.gprj以加载磁盘配置；若IDE保留旧设置，在综合配置的Include Path中删除不存在的旧config路径，确认E:/gowin/fpga-instrument/src及E:/gowin/fpga-instrument/src/config。无需另建工程或复制头文件。证据与验证见reports/include_fix/validation.json；综合、布局布线和烧录仍由用户执行。

最新复位排查：用户确认USR松开时复位诊断灯仍常亮。在原src/keyboard.cst给U4启用内部弱下拉，保留正常复位功能和音频逻辑；用户已反馈启动恢复，电气原因仍未测量。重新编译烧录后应观察LED4是否亮、前四灯是否恢复流水，详见docs/bringup_run_leds.md末段和reports/reset_input/validation.json。

用户最新确认：U4启用内部下拉后“现在正常了”。当前启动修复作为Git基线保存；底噪已取消软件处理，当前修改仅继续键盘输入与音频模块分离。

2026-10-15：启动修复与工程整理已提交为f48aeca。用户确认底噪是耳机阻抗过低，取消底噪软件修改；功放、静音、增益与PLL参数不变。

键盘更换边界：src/keyboard_core.sv负责当前矩阵扫描与音符映射；src/synth_core.sv是独立音源，只接收note_on/note_off/fcw；src/keyboard_top.sv连接两者。更换键盘时替换输入适配器并遵循docs/interfaces.md中的同域帧事件接口即可，音源无需依赖新键盘的物理结构。USR复位由原clock_reset独立处理。主工程新增一个独立音源文件，重新打开根目录keyboard_adsr.gprj载入；编译烧录仍由用户负责。本次分离验证见reports/input_separation/validation.json，源文件修改尚未自动再次提交。

用户后续确认：接口分离版“测试正常”，实板通过为用户定性反馈；原音频采样及仿真延迟保持。用户已明确选择四声部复音，Git仍以f48aeca为已提交基线。

2026-10-15四声部阶段：主工程保持keyboard_adsr.gprj、keyboard_top和D2_keyboard_leds输出名。原mono_note_control及其TB重命名修改为key_note_events，新增独立voice_allocator、voice_mixer；当前20个HDL均在同一GPRJ中。键盘通过带note_id的valid/ready事件控制音源，四路独立包络与24位样本经40位混音送16位DAC。

关闭并重新打开主工程加载新文件，再由用户综合/P&R/烧录；原引脚、U4下拉、PLL和功放策略不变。首次用同一列四键验证复音、逐个松键验证独立尾音。第五音在无空闲/释放声部时替换最久未起音的声部，旧松键不会误关新音；无二极管鬼键保护保留。验收步骤和安全五键组合见docs/bringup_keyboard.md，HDL证据见reports/four_voice/validation.json。四声部已获用户“测试正常”的定性实板确认，本轮按明确指令提交；此前“未提交”属于历史状态。

最新确认：用户已测试四声部版正常并要求Git提交；源码与7051357项HDL回归记录一致。没有新增频率、电压或长稳测量，历史开发失败日志保留。
