# D2 矩阵键盘与四声部正弦复音

> 2026-10-14 行列定义已按用户澄清修正：物理行（上到下）W26/L22/Y26/AA25；物理列（左到右）W25/M24/Y25/AA24。keyboard.cst 与编译脚本期望位置已同步修正，须由用户重新综合/布局布线/烧录；已有 D2 .fs 和历史时序报告属于旧行列版本，不作为新约束实现结果。


## 分工和工程入口

用户负责综合编译、布局布线、烧录。助手仅改文件及运行 HDL 仿真，后续不再启动 EDA 编译/下载工具。
用 Gowin IDE 打开 `E:\gowin\fpga-instrument\keyboard_adsr.gprj`。
顶层 `keyboard_top`；器件 `GW5AST-LV138FPG676AC1/I0`，Device Version C。
include搜索目录为src与src/config；SystemVerilog 2017；约束为 src/keyboard.cst 和 keyboard.sdc。
过程配置在 impl/keyboard_adsr_process_config.json，确认顶层/约束后由用户自行综合及布局布线。
当前流水灯版编译输出为 impl/pnr/D2_keyboard_leds.fs，SRAM 回读保护关闭并请求包含 BSRAM 初始化。旧 D2_keyboard_adsr.fs 不含流水灯，不作为当前源码的下载文件。
启动与接口分离版已获用户实板正常反馈，当前四声部版也已获用户“测试正常”的定性实板反馈。灯号沿用[流水灯版操作说明](bringup_run_leds.md)；LED5表示至少一个已分配声部仍被按住，松开后尾音不依赖此灯保持。
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
本阶段为四声部：四个可识别按键可同时发声，各自独立Release。第五个新音符依次复用空闲或已释放声部；若四个音符都按住，替换最久未起音的声部。旧编号松开不会影响新音符，被替换且仍按住的旧键须松开再按，不自动回退。

## ADSR 和无二极管处理

按下 Note On 从当前包络值开始 Attack，10 ms 到峰值；Decay 100 ms 到约 70%；按住保持 Sustain；Note Off 后 Release 200 ms 到零。
同一音符在Release中重按，从当前包络重新起音并保持相位；声部改分配给新音符时从零相位、零包络Attack。ADSR和相位在音频帧边界更新，各声部互不释放。
每声部增益仍为1/32，四路合成最大约满幅1/8；40位求和后转16位并饱和。启动保留 PLL 资格判断、480 帧零码、功放开启和 240 帧淡入；未按键时输出零码，串行时钟持续运行。
四列扫描周期 200 us，每列 50 us，在列切换后等待 10 us；普通按下/松开须 15 次稳定扫描，约 3 ms 消抖。

用户已确认没有每键二极管。三角形三键可能与矩形四键产生相同扫描结果，无法保证任意多键无冲突。
本版对矩形歧义清除接受键状态，释放全部已接受音符并禁止由歧义产生的新音符；解除歧义并消抖后恢复。单行多键、单列多键和互不连接的组合可用于复音验证。
这是保守鬼键处理，不是 16 键无冲突键盘，也不代表最终 FPGA 声部数量。

## 用户上板顺序

1. 关闭并重新打开 keyboard_adsr.gprj，确认顶层 keyboard_top、文件列表包含synth_core.sv、key_note_events.sv、voice_allocator.sv、voice_mixer.sv与run_leds.sv、输出基名 D2_keyboard_leds；自行综合、布局布线，确认无编译错误及 setup/hold 违例，再保存报告并执行 SRAM Program and Verify。输出名仍为D2_keyboard_leds，须确认生成时间；旧文件不是当前32声部版本。
2. 不按键时应安静，BCK 仍为 1.536 MHz、WS 为 48 kHz，启动后 PA_EN 高。
3. 逐个短按 16 个位置，确认都能发声且音高按上表变化；第三行第二列应为 A4。
4. 长按一个键听起音/衰减/保持；松开听约 0.2 秒尾音。
5. 先按同一列四个键（例如左列C4/E4/G#4/C5），确认四音共存；逐个松开，每次只结束对应声部，其他键继续保持。全部松开后应有约0.2秒尾音并归零；功放不自动关闭。
6. 测三角形三键歧义，预期全部声部释放且不发出新鬼音；松开至可识别组合后应恢复。
7. 演奏中按用户复位，确认音频及扫描恢复；最后完成至少 30 分钟稳定性测试。

初始音量较低。若所有键无声，请保存编译/下载日志，并反馈 W20/DIN 是否随按键变化、U26/PA_EN 是否高及八根线的实际连接。

## 文件和复现

- 扫描：src/matrix_keypad.sv；事件：src/key_note_events.sv；包络：src/adsr_envelope.sv。
- 输入适配器：src/keyboard_core.sv；独立音源：src/synth_core.sv；板级连接：src/keyboard_top.sv。
- 扫描参数：src/config/keyboard_config.svh；音源/ADSR参数：src/config/synth_config.svh；静态频率表：src/config/keyboard_notes.svh，ROM仍为src/rom/sine4096.hex。
- 验证：reports/keyboard/validation.md、validation.json；每个新模块均有独立 TB，端到端/板级另测。

```powershell
python scripts/run_sim.py --test tb_matrix_keypad
python scripts/run_sim.py --test tb_key_note_events
python scripts/run_sim.py --test tb_adsr_envelope
python scripts/run_sim.py --test tb_adsr_production
python scripts/run_sim.py --test tb_keyboard_core
python scripts/run_sim.py --test tb_keyboard_latency
python scripts/run_sim.py --test tb_synth_core
python scripts/run_sim.py --test tb_voice_allocator
python scripts/run_sim.py --test tb_voice_mixer
python scripts/run_sim.py --test tb_keyboard_top --vendor
```

原单声部阶段的历史七项新增仿真总计2631691次检查。生产扫描参数的一次仿真中首个非零串行码延时约 3.135 ms；不把此值当作实板模拟输出延时。
此前已完成的一次 D2 离线实现保留作证据：18 端口位置匹配，setup/hold=0，Logic 916、Register 384、BSRAM 4、DSP 2、PLL 2。
用户明确分工后助手未再次启动编译或下载器；硬件验收尚未完成，保留已知时钟路由/未约束路径统计及实际电气测量限制。

## 下一阶段约束

2026-10-16当前实现32声部，保持32位相位、12位波表地址、24位声部、40位混音及16位DAC；共享ROM/增益，独立包络，仍为原主工程。
控制不得阻塞串行输出；当前32声部样本在frame_ce后第517周期交付下一帧缓冲，截止预算544周期，测试检查1280周期连续帧和欠载。

## 行列修正后的测量

输入行 W26/L22/Y26/AA25 平时由上拉保持高；按住第一行第一列时，观察 W26，应出现约 50 us 低脉冲，周期约 200 us。
W25/M24/Y25/AA24 为低/高阻列扫描输出，未选列不主动驱动高。音频测量点 U22/V19/W20/U26 不变。
新增 scripts/run_keyboard_pinmap.py 从 CST 生成真实物理焊盘连接，并用 tranif1 开关网络检查；16 个键位、松开、非零音频、三角鬼键均通过。修正前的约束也单独模拟，确认旧方向会转置键位但仍能发声，完全无声原因仍待实板测量。
此测试旁路 PLL，仅针对物理引脚到按键位置的映射；未重新运行 Gowin 综合/布局布线或烧录。

## 按用户全引脚 CST 校准

2026-10-14 按用户提供的 tang_mega_138k-pro_pins.cst 核对：参考时钟 P16 启用上拉，逻辑 LED0/1 分别使用 R26/J14；该逻辑灯号与 4071f3 图纸灯号相反，详见 bringup_run_leds.md。键盘八线及音频/测量球位保持原定义，行输入仍上拉、未选列仍高阻。PA_EN 未在参考 CST 中列出，按匹配板版原理图保留 H17。新约束需用户重新编译实现，仿真不能验证实际 IO 电气。

## 最新实板反馈与下一步

此前启动灯诊断显示USR松开时复位仍高；原U4约束启用内部下拉后，用户已反馈“现在正常了”。用户又确认底噪来自耳机阻抗过低，明确取消软件处理。接口分离版已获用户正常反馈；用户随后明确选择四声部复音，当前实现本阶段，功放、PLL和复位参数不变。灯号仍见bringup_run_leds.md。重新打开主工程加载新增synth_core后，由用户自行编译烧录验证接口分离版本。

2026-10-15用户已确认输入/音源分离版“测试正常”，不再将该版本记为待首次实板验证。没有新增频率、电压或长稳测量；随后用户明确选择四声部复音；这条实板确认仅属于先前分离版，不代表新四声部版已上板。

## 四声部第五键与旧松键验证（历史715920f）

为避免鬼键掩盖溢出策略，可按顺序保持第一行前三个键C4/C#4/D4，再按第二行第四个键G4，形成四声部；再加第三行第四个键B4。两组接线互不连通，不构成矩形歧义，第五音应替换最早的C4。随后松开旧C4，B4应继续响；其他三个音符也继续保持。若想恢复C4，须先松开再按。

此组合与同列四键、独立Release、矩形歧义及复位已在物理开关网络/板级HDL中覆盖。仿真首个非零码约3.177ms，不是实板模拟延迟。当前四声部完整回归及开发失败记录见reports/four_voice/validation.json；未由助手综合、布局布线、烧录或提交Git。

四声部后续实板反馈：用户确认“测试正常”，并明确要求提交Git；当前源码与完整回归哈希一致。上文待上板语句属于验证时的历史状态，不另填实测频率、延迟或长期稳定性结果。

## 当前32声部上板验收

请重新打开根目录keyboard_adsr.gprj并自行综合、布局布线、烧录，仍输出D2_keyboard_leds；不要使用旧.fs。先保存当前资源与时序报告，核对61.44MHz音频域、setup/hold、引脚及现有警告，实际速度等级未核验的问题继续记录。

按上面的16键逐键、同列四键、独立松键尾音、鬼键、复位与冷启动顺序验收。安全五键顺序仍为第一行前三键、第二行第四键、第三行第四键：现在五音各占独立声部，C4应继续发声；松开C4，另外四音继续。旧四声部“第五键替换C4”规则不适用于当前32声部。

32音同时输入及第33音替换已用独立事件TB验证；现有16键无二极管键盘不能实板证明32键同时输入，不增加自奏或外设功能。全部松键后约0.2秒尾音归零，PA仍高；底噪任务保持关闭。完成至少30分钟稳定性测试，无法测量的电气/延迟项目保持未测，不填写推测值。本版本尚待用户实板确认。
