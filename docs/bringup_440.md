# D1 低幅 440 Hz 正弦：用户手动烧录

## 文件与首次操作

先用 `E:\gowin\fpga-instrument\bringup\D1_stereo_440.fs`。
Gowin Programmer 选择 GW5AST-138C、SRAM Program and Verify；本次仍由用户操作，不写 Flash。
准备耳机后进行低音量监听；该文件启动后会自动发出连续的低幅 440 Hz 单音。

另外提供 `D1_left_440.fs`（仅左声道）和 `D1_right_440.fs`（仅右声道），分别烧录以验收左右对应。
三个文件都保留原有 DAC/PT8211 和功放连接，同时保留用户指定排针镜像。

## 启动与信号预期

PLL 分级锁定资格判断各 2 ms，随后发送 480 个完整零码帧（10 ms），开启 PA_EN，再经 240 帧（5 ms）淡入。
最终幅度为满幅的 1/32（约 -30.1 dBFS），DAC 码值范围 -1024..1023；ROM 为 4096x16，DDS 为 32 位相位，标称采样率 48 kHz。
这是启动延时，不代表 Note 输入到音频输出延时；此阶段没有 Note 输入。

按用户图片上排从左到右：

| 板上丝印 | 信号 | 上电/复位后预期 |
|---|---|---|
| U22 | BCK 镜像 | 锁定后 1.536 MHz |
| V19 | WS 镜像 | 锁定后 48 kHz，低右/高左 |
| W20 | DIN 镜像 | 静音期为零，淡入后出现 16 位串行数据 |
| U26 | PA_EN 镜像 | 启动静音期低，随后高；复位/失锁时低 |

下排 V22/W19/Y20/V26 不使用，图中八孔均不是地；地夹接板上明确标 GND 的孔。
DAC 采用 PT8211 Japanese/LSBJ 格式：MSB 先行，BCK 上升沿采样，WS/DIN 在下降沿更新。不是 Philips I2S 的一位延后格式。
默认双声道相同；左独响版 WS 低时右声道代码为零，右独响版 WS 高时左声道代码为零。

## 上板验收顺序

1. 用户烧录双声道文件，保存 Program/Verify 结果；若校验失败，先保存完整日志，不算验收通过。
2. 测 U22/BCK、V19/WS，记录频率及电平幅度；测 U26 由低到高，W20 出现连续串行数据。
3. 确认耳机左右均有稳定单音；音量较小为预期。
4. 分别烧录左/右独响文件，确认耳机实际左右对应；保存结果。
5. 播放中按核心板用户复位键，确认 PA_EN 和 DIN 归零、随后按同样顺序恢复；不把 RECONFIG 当 RTL 复位。
6. 连续播放至少 30 分钟，记录无断音、异常跳变、重新启动等现象。

若能测到耳机模拟输出，记录约 440 Hz 波形及幅度；使用合适的耳机转接引出 L/R/GND，避免把数字 DIN 波形当作 440 Hz 模拟波形。
报告 GPIO 波形不等同直接验证 DAC 封装脚的电气时序。功放极性与实际模拟路径仍以用户实测为准。

## 工程与验证入口

- 顶层：`boards/mega138k_pro/tone_play.sv`，复用已验证的 DDS/ROM/增益/帧缓冲/串行模块。
- 约束：`tone_play.cst`、`tone_play.sdc`，沿用经官方资料核对的 10 个端口。
- 仿真：`python scripts/run_sim.py --test tb_tone_play --vendor`。
- 构建：`python scripts/build_tone_play.py`；只构建一个版本可加 `--profile stereo|left|right`。
- 工程：`tone_play_stereo.gprj`、`tone_play_left.gprj`、`tone_play_right.gprj`。
- 结果：`reports/tone_play/`、`bringup/D1_*_status.json`；关键波形 `reports/sim/D1_boundaries.vcd`，解码样本 `reports/sim/D1_decoded.csv`。

独立接收模型按 BCK 上升沿解码并与数学 DDS/定点增益参考逐样本比较，覆盖生产 480/240 帧启动、串行连续性、GPIO 镜像、播放中复位和左/右隔离。
左/右隔离的板级 TB 加速启动帧数，双声道 TB 使用完整 480/240 帧；既有 tone_core 测试已覆盖 48000 个连续帧和两个复位/声道模式场景。
保留 PR1014 时钟路由、CK3000 综合警告；输出 0..30 ns 为实现预算，未冒充 PT8211 电气时序规格。不得将离线报告记作实板音频验收。
SRAM 回读保护关闭，仅影响生成配置文件；两个自动烧录入口继续停用，助手未烧录这些新文件。

## 下一阶段接口

保留 32 位相位、12 位波表地址、24 位内部声部、40 位后续混音和 16 位 DAC。完成实际发声后再加入 Note On/Off 与 ADSR，不在本阶段扩展 UI 或复音。

## 本次离线验证结果

新增板级仿真 375334 次检查通过；双/左/右三个版本均完成实际引脚 P&R，setup/hold 违例为 0。资源与警告分析见 `reports/tone_play/validation.md`。仿真解码双声道峰值 -1024..1023，两个阶段左右样本逐帧一致；这些数据来自仿真，并非硬件测量。
