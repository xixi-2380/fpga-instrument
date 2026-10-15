# D2 矩阵键盘 + Note On/Off + 单声部 ADSR

> 2026-10-14 行列定义已按用户澄清修正：物理行（上到下）W26/L22/Y26/AA25；物理列（左到右）W25/M24/Y25/AA24。keyboard.cst 与编译脚本期望位置已同步修正，须由用户重新综合/布局布线/烧录；已有 D2 .fs 和历史时序报告属于旧行列版本，不作为新约束实现结果。


## 分工和工程入口

用户负责综合编译、布局布线、烧录。助手仅改文件及运行 HDL 仿真，后续不再启动 EDA 编译/下载工具。
用 Gowin IDE 打开 `E:\gowin\fpga-instrument\keyboard_adsr.gprj`。
顶层 `keyboard_top`；器件 `GW5AST-LV138FPG676AC1/I0`，Device Version C。
配置路径为 src/config；SystemVerilog 2017；约束为 src/keyboard.cst 和 keyboard.sdc。
过程配置在 impl/keyboard_adsr_process_config.json，确认顶层/约束后由用户自行综合及布局布线。
当前流水灯版编译输出为 impl/pnr/D2_keyboard_leds.fs，SRAM 回读保护关闭并请求包含 BSRAM 初始化。旧 D2_keyboard_adsr.fs 不含流水灯，不作为当前源码的下载文件。
当前无声排查先按 [流水灯版操作说明](bringup_run_leds.md) 观察 LED0～3、LED4 和单按 A4 时的 LED5，再决定后续测点。
如使用 Programmer，选择 GW5AST-138C、SRAM Program and Verify，由用户执行；不需要写 Flash。

## 保持现有接线

| 数组位 | 列：从左到右 | 行：从上到下 |
|---|---|---|
| 0 | W25 | W26 |
| 1 | M24 | L22 |
| 2 | Y25 | Y26 |
| 3 | AA24 | AA25 |

所选列驱动低，其余三列高阻；行输入使用 FPGA 内部上拉并经过两级同步。
键盘是无源八线开关矩阵，现有八根信号线即可，本次无需增加供电线。
音频测量点仍为 U22/BCK、V19/WS、W20/DIN、U26/PA_EN；示波器地夹接另一个明确标为 GND 的孔。

## 音符分配

按用户定义的键盘正面方向，上到下为行、左到右为列：

| | 第 1 列 | 第 2 列 | 第 3 列 | 第 4 列 |
|---|---|---|---|---|
| 第 1 行 | C4 | C#4 | D4 | D#4 |
| 第 2 行 | E4 | F4 | F#4 | G4 |
| 第 3 行 | G#4 | A4（440 Hz） | A#4 | B4 |
| 第 4 行 | C5 | C#5 | D5 | D#5 |

先按位置测试，不凭键帽字符猜引脚；若按下位置与音高不符，记录实际对应位置以便修正映射。
本阶段为单声部：新按键优先；同一采样帧多个新增键选最高键号。松开当前键会切到仍按住的最高键号，全部松开进入 Release。

## ADSR 和无二极管处理

按下 Note On 从当前包络值开始 Attack，10 ms 到峰值；Decay 100 ms 到约 70%；按住保持 Sustain；Note Off 后 Release 200 ms 到零。
Release 过程中再次按键从当时的包络值重新起音，避免强行清零。DDS 相位连续，频率和控制事件在音频采样边界更新。
最终峰值仍限制在满幅 1/32。启动保留 PLL 资格判断、480 帧零码、功放开启和 240 帧淡入；未按键时输出零码，串行时钟持续运行。
四列扫描周期 200 us，每列 50 us，在列切换后等待 10 us；普通按下/松开须 15 次稳定扫描，约 3 ms 消抖。

用户已确认没有每键二极管。三角形三键可能与矩形四键产生相同扫描结果，无法保证任意多键无冲突。
本版对矩形歧义清除接受键状态，释放当前音符并禁止新音符；解除歧义并消抖后恢复。单行多键、单列多键和互不连接的对角组合仍可按单声部优先级使用。
这是保守鬼键处理，不是 16 键无冲突键盘，也不代表最终 FPGA 声部数量。

## 用户上板顺序

1. 关闭并重新打开 keyboard_adsr.gprj，确认顶层 keyboard_top、文件列表包含 run_leds.sv、输出基名 D2_keyboard_leds；自行综合、布局布线，确认无编译错误及 setup/hold 违例，再保存报告并执行 SRAM Program and Verify。先按 bringup_run_leds.md 记录流水灯和 LED4/5 状态；无声未定位时先完成该诊断。
2. 不按键时应安静，BCK 仍为 1.536 MHz、WS 为 48 kHz，启动后 PA_EN 高。
3. 逐个短按 16 个位置，确认都能发声且音高按上表变化；第三行第二列应为 A4。
4. 长按一个键听起音/衰减/保持；松开听约 0.2 秒尾音。
5. 快速连按、Release 中重按；按住一键再按另一键，确认新键优先及松开回退。
6. 测三角形三键歧义，预期当前声部释放且不发出新鬼音；松开至可识别组合后应恢复。
7. 演奏中按用户复位，确认音频及扫描恢复；最后完成至少 30 分钟稳定性测试。

初始音量较低。若所有键无声，请保存编译/下载日志，并反馈 W20/DIN 是否随按键变化、U26/PA_EN 是否高及八根线的实际连接。

## 文件和复现

- 扫描：src/matrix_keypad.sv；事件：src/mono_note_control.sv；包络：src/adsr_envelope.sv。
- 集成：src/keyboard_core.sv、src/keyboard_top.sv。
- 参数：src/config/keyboard_config.svh；静态频率表：src/config/keyboard_notes.svh，ROM 仍为 src/rom/sine4096.hex。
- 验证：reports/keyboard/validation.md、validation.json；每个新模块均有独立 TB，端到端/板级另测。

```powershell
python scripts/run_sim.py --test tb_matrix_keypad
python scripts/run_sim.py --test tb_mono_note_control
python scripts/run_sim.py --test tb_adsr_envelope
python scripts/run_sim.py --test tb_adsr_production
python scripts/run_sim.py --test tb_keyboard_core
python scripts/run_sim.py --test tb_keyboard_latency
python scripts/run_sim.py --test tb_keyboard_top --vendor
```

七个新增仿真通过，总计 2631691 次检查。生产扫描参数的一次仿真中首个非零串行码延时约 3.135 ms；不把此值当作实板模拟输出延时。
此前已完成的一次 D2 离线实现保留作证据：18 端口位置匹配，setup/hold=0，Logic 916、Register 384、BSRAM 4、DSP 2、PLL 2。
用户明确分工后助手未再次启动编译或下载器；硬件验收尚未完成，保留已知时钟路由/未约束路径统计及实际电气测量限制。

## 下一阶段约束

保持 32 位相位、12 位波表地址、24 位声部、40 位混音及 16 位 DAC。后续把 16 位稳定按键状态和 Note 事件接入四声部，再扩展 32 声部。
控制不得阻塞串行输出；当前样本在 frame_ce 后固定三周期写入下一帧缓冲，测试检查 1280 周期截止时间和欠载。

## 行列修正后的测量

输入行 W26/L22/Y26/AA25 平时由上拉保持高；按住第一行第一列时，观察 W26，应出现约 50 us 低脉冲，周期约 200 us。
W25/M24/Y25/AA24 为低/高阻列扫描输出，未选列不主动驱动高。音频测量点 U22/V19/W20/U26 不变。
新增 scripts/run_keyboard_pinmap.py 从 CST 生成真实物理焊盘连接，并用 tranif1 开关网络检查；16 个键位、松开、非零音频、三角鬼键均通过。修正前的约束也单独模拟，确认旧方向会转置键位但仍能发声，完全无声原因仍待实板测量。
此测试旁路 PLL，仅针对物理引脚到按键位置的映射；未重新运行 Gowin 综合/布局布线或烧录。

## 按用户全引脚 CST 校准

2026-10-14 按用户提供的 tang_mega_138k-pro_pins.cst 核对：参考时钟 P16 启用上拉，逻辑 LED0/1 分别使用 R26/J14；该逻辑灯号与 4071f3 图纸灯号相反，详见 bringup_run_leds.md。键盘八线及音频/测量球位保持原定义，行输入仍上拉、未选列仍高阻。PA_EN 未在参考 CST 中列出，按匹配板版原理图保留 H17。新约束需用户重新编译实现，仿真不能验证实际 IO 电气。

## 最新实板反馈与下一步

用户反馈数分钟后键盘能正常发声，但冷启动LED4/5不响应，短按核心板USR无改善；恢复后LED4稳定、松键LED5灭，持续低频嘶声。当前不是完全无声，冷启动与底噪仍未解决。原工程新增只读启动灯诊断，未就绪约1秒后LED0心跳、LED1/2显示原始PLL LOCK、LED3显示复位，LED4/5含义不变；恢复后再流水。详见bringup_run_leds.md，需用户重新编译烧录后观察。
