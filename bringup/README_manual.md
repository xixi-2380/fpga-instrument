# D2 运行流水灯：用户自行编译及烧录

## 工程与新输出

关闭并重新打开 `E:\gowin\fpga-instrument\keyboard_adsr.gprj`，顶层仍是 keyboard_top。
项目已经加入 rtl/run_leds.sv、六个 LED 端口及 CST/SDC。配置中输出基名已改为 D2_keyboard_leds。
由用户自行综合、布局布线并检查报告，确认生成新文件 `E:\gowin\fpga-instrument\impl\pnr\D2_keyboard_leds.fs` 后再烧录。
本次助手没有运行 Gowin 编译或下载器，没有生成新的 .fs。旧 D2_keyboard_adsr.fs 不含流水灯，请勿把旧文件误认作新版本。
如果 IDE 已打开旧工程，必须重新载入新增源文件及配置；检查 File List 有 run_leds.sv、顶层 LED 端口 led_n[5:0]、输出名为 D2_keyboard_leds。

## 六颗橙色用户灯的含义

| 图纸 LED 编号 | FPGA 球位 | 运行行为 |
|---|---|---|
| LED0 | J14 | 与 LED1/2/3 依次点亮 |
| LED1 | R26 | 同上 |
| LED2 | L20 | 同上 |
| LED3 | M25 | 同上 |
| LED4 | N21 | 音频域复位解除后常亮；未就绪或复位时灭 |
| LED5 | N23 | 单声部音符门控有效时亮，全部松开/歧义释放后灭 |

LED0→LED1→LED2→LED3→LED0，每颗停留 250 ms，一圈约 1 秒。
四颗运行灯直接使用板载 50 MHz 参考时钟，不依赖音频 PLL、键盘、用户复位或 PA_EN。
因此即使音频 PLL 未锁定，流水灯也应继续；按用户复位也不会停止流水灯。重新配置/上电从第一颗开始。
LED4/5 的状态跨入参考时钟域采用各自两级同步，音频/键盘核心没有新增反向控制或派生时钟。
LED5 表示 Note 门控而非波形幅度：松开后它可以立即灭，而 200 ms Release 尾音仍继续。
这里指六颗普通用户灯，不是 POWER/DONE/READY 灯或 WS2812 彩灯。

## 依据和约束

Dock 版本依据用户照片 v4071f3。官方该版本原理图第 15 页：LED0→J14、LED1→R26、LED2→L20、LED3→M25、LED4→N21、LED5→N23；各 LED 经限流电阻接 +3V3，FPGA 低电平点亮。
旧全引脚 CST 将 LED0/LED1 的位序写成 R26/J14，与该版本原理图命名相反；本次按 4071f3 原理图编号约束，但全部球位均已在官方资料出现。
引脚设为 LVCMOS33、无上拉、DRIVE=8，未占用键盘及音频测量球位。24 个板级端口球位唯一性检查通过。
SDC 新增参考时钟到 LED 输出 0..100 ns 的可视输出实现预算；音频约束不变，没有新增音频 false-path。

## 如何判断

- 四灯按指定节奏循环：表明这版运行指示逻辑及参考时钟在运行；仍应以 Programmer 校验结果判断下载是否完整。
- 流水正常但 LED4 始终灭：优先查看复位输入和音频 PLL/复位资格判断。
- LED4 亮，但按单个键 LED5 不亮：优先排查键盘实际线序、扫描和行输入。
- LED4/5 都亮但无声：进一步查 DIN、DAC、功放及模拟输出。

流水灯不能单独证明音频链路、频率或时序已经通过实板验收；目前无声原因仍未确定。

## 仿真和参数

config/run_leds_config.svh 定义运行灯周期，默认 REF_HZ/4=12500000 个参考周期。
run_leds 用配置初始化的计数器循环，不用用户复位或 PLL 作时钟。
独立 tb_run_leds 检查上电状态、完整循环、精确间隔、STEP_CYCLES=1 边界、状态同步与 PLL 就绪撤销。
板级 tb_keyboard_top 检查音频和键盘保持正常、音频/按键状态灯点亮及用户复位期间流水继续。
物理键盘映射测试仍通过当前行 W26/L22/Y26/AA25、列 W25/M24/Y25/AA24 的 16 个位置。

```powershell
python scripts/run_sim.py --test tb_run_leds
python scripts/run_sim.py --test tb_keyboard_top --vendor
python scripts/run_keyboard_pinmap.py
```

本次结果：tb_run_leds PASS（111 次检查）；tb_keyboard_top PASS（329180 次检查）；当前/旧行列方向各 34 项映射检查通过。
当前流水灯版没有新的综合资源/时序或硬件结果；需要用户自行编译并记录。
