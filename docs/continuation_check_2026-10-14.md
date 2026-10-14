# 2026-10-14 接续核对：等待流水灯版实板结果

本次依据根目录 AGENTS.md 与 docs/handoff_2026-10-14.md 接续。键盘版无声尚未定位；用户负责综合、布局布线和烧录，助手仅修改文件、运行纯 HDL 仿真和读取报告。当前不扩展复杂功能。

## 本次只读核对

- reports/keyboard/run_leds/validation.json 记录的 10 个文件 SHA-256 均与当前文件一致。该记录并非全部工程输入的哈希清单，不将其扩大为完整源码一致性证明。
- keyboard_adsr.gprj 启用的 21 个工程文件均存在，包含 rtl/run_leds.sv 与 boards/mega138k_pro/keyboard_top.sv。
- impl/keyboard_adsr_process_config.json 的 TopModule=keyboard_top、OUTPUT_BASE_NAME=D2_keyboard_leds；构建脚本只读取，未执行。
- 当前 keyboard.cst 的 24 个端口位球位映射与 validation.json 完全一致且球位无重复。
- 行输入为 W26/L22/Y26/AA25，均启用上拉；列为 W25/M24/Y25/AA24，顶层仅驱动低或高阻。
- 当前配置和 PLL wrapper 仍为 50 MHz → 32 MHz → 61.44 MHz，流水灯周期为 12500000 个参考时钟周期。上述为文件核对，不是实测频率。
- 读取已有仿真日志：tb_run_leds PASS，111 次检查；tb_keyboard_top PASS，329180 次检查。物理键盘映射 status.json 中 corrected/previous 均通过，且标明旁路时钟/复位、未验证硬件。
- 本次检查时 impl/pnr/D2_keyboard_leds.fs 不存在；旧 .fs 和历史实现报告不代表当前流水灯源码已实现。

## 本次修改及验证范围

修正 docs/bringup_keyboard.md 中过时的输出文件名，并链接当前流水灯诊断说明；上板第一步补充重新载入工程及版本核对。本记录为新文件，不覆盖原始交接、故障日志或验证证据。

未修改 RTL、约束、参数、工程配置或脚本；未重跑 HDL 仿真。已有仿真 PASS 是本次读取的历史结果，不能代替实板验证。没有启动综合、布局布线、EDA 构建、Programmer 或 JTAG，也没有生成新的下载文件。

## 下一步分支

待用户自行编译烧录 D2_keyboard_leds 后，依次记录：

1. LED0→1→2→3 是否每颗 250 ms 循环。无流水时先核对下载文件、校验结果、供电和参考时钟。
2. LED4 是否常亮。流水正常但 LED4 灭时先查 U4 复位、PLL 锁定及音频复位释放。
3. 单按第三行第二列 A4（Y26 行、M24 列）时 LED5 是否亮。LED4 亮而 LED5 灭时查键盘线序、扫描及行电平。
4. LED4/5 均亮却无声时测 U22/BCK=1.536 MHz、V19/WS=48 kHz、U26/PA_EN 启动后为高、W20/DIN 是否随按键出现非零数据，再查 DAC、功放与模拟输出。

键盘测量以修正行列为准：第一行输入 W26，第一列扫描输出 W25。按住第一行第一列时，观察 W26 上约 50 μs 低脉冲、约 200 μs 周期。没有新增实测结果，不将行列修正记作无声故障已解决。
