# AiP5916 触摸亮灯测试

这是 `codex/touch-led-test` 分支的独立接线测试。触摸任意琴键或 AUX 时，Dock **LED1（R26）亮**；全部松开后熄灭，按住时持续亮。

测试顶层为 `touch_led_top`，不接入根目录的音源、屏幕或主工程。请打开本目录的 [touch_led.gprj](touch_led.gprj)，而非根目录 `keyboard_adsr.gprj`。

**全部按键无响应时，先按 [分阶段排查方案](TEST_PLAN.md) 检查。** 当前单灯无法区分初始化失败与没有触摸；方案包含可直接测量的项目、波形判据、首次失败定位表及待补充诊断模式规格。

## 接线

| 键盘 J1 | 信号 | FPGA 管脚 |
|---:|---|---|
| 3 | SDA | U16 |
| 5 | SCL | V16 |
| 7 | INT | U15 |
| 1 | +3V3 | 开发板 3.3V 电源 |
| 2、4、6、8 | GND | 开发板 GND |

三根信号的顺序已由用户确认。键盘只接 3.3V 并共地，SDA/SCL 为开漏输出；不要接 5V。

其他板载管脚：P16 为 50 MHz 时钟；K16 为 Dock USER_BUTTON0，按下复位；R26 为低有效 LED1。所提供的通用 CST 将 R26 命名为 `led[0]`，与实体灯号不同；本工程统一叫 `led_n`。

## 使用

1. 断电接线，上电时手先离开电极。
2. 打开本目录的 Gowin 工程，顶层选择 `touch_led_top`。目标器件是 **GW5AST-LV138FPG676AC1/I0，Device Version C**，先核对实物型号。
3. 用户自行综合、布局布线，并使用 Programmer 将 `impl/pnr/touch_led.fs` 下载到 SRAM。
4. 初始化后触摸、松开，观察 LED1。若补接电源、重接键盘或初始化失败，按一次 USER_BUTTON0 重新初始化。

请使用英文工程路径。按仓库规则，`.fs`、实现缓存和仿真可执行文件不上传；上一轮生成的位流仍在本机 `E:/TOUCH_LED_TEST/impl/pnr/touch_led.fs`。它仅属于这份独立测试，不能用于运行完整电子琴。

[build.tcl](build.tcl) 保留给用户运行。在本目录执行的示例：

```powershell
& 'C:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build.tcl
```

## 工作流程

- 上电复位后等待约 20 ms，以 100 kHz I²C 访问 7 位地址 0x56。
- 执行 25 项配置，每项独立写入并读回核对：进入配置模式、设置多键识别与 INT 电平模式、启用全部 16 路、恢复默认灵敏度/阈值、退出配置模式。
- `MCON=0x04`，INT 有键时低、全部松开时高；两级同步后，对按下、松开分别做约 1 ms 稳定滤波，再控制 LED。
- 此版只监测 INT，不轮询 0x34/0x35，不能区分键号。I²C 无应答、超时或读回不一致会终止初始化，LED 保持灭，按复位重新尝试。
- 全部逻辑使用 50 MHz 系统时钟，I²C 使用时钟使能节拍，不生成内部逻辑分频时钟。外部触摸芯片另有扫描和基线建立时间，实际响应待上板确认。

## 验证

纯 HDL 测试覆盖初始化及校验、重复 START、末字节 NACK、INT 毛刺、按下/保持/松开、无应答、读回错误及 SCL 卡低超时。测试平台是 [tb_touch_led.v](sim/tb_touch_led.v)，记录见 [本次证据目录](../../reports/touch_led/2026-10-26)。

在仓库根目录执行纯 HDL 仿真，例如：

```powershell
iverilog -g2005-sv -grelative-include -s tb_touch_led -o tests/touch_led/sim/test.vvp tests/touch_led/rtl/touch_led_top.v tests/touch_led/rtl/i2c_register_master.v tests/touch_led/sim/tb_touch_led.v
vvp tests/touch_led/sim/test.vvp
```

完整结果与上一轮编译报告来源见 [VERIFICATION.md](VERIFICATION.md)。尚未上板实测；本次上传只复核打包并运行纯 HDL 仿真，不重新运行 EDA 或下载。

初始化依据为用户提供的《电容触摸电子琴PCB_FPGA使用说明》第 4 节及 AiP5916 原厂 2021-07-A3 手册第 8～14 页；板载引脚依据为 Tang Mega 138K Pro 的原理图和通用 CST。
