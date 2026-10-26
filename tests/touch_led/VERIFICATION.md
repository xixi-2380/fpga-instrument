# 验证记录

日期：2026-10-26。

## 行为仿真

Icarus Verilog 13.0：全部测试通过。上一轮独立目录的记录见 [original_sim.txt](../../reports/touch_led/2026-10-26/original_sim.txt)，本次上传打包后的复核见 [packaged_sim.txt](../../reports/touch_led/2026-10-26/packaged_sim.txt)。

覆盖：25 项配置逐项写入与读回核对、I²C 重复起始与末字节 NACK、INT 毛刺过滤、按下/保持/松开、地址无应答、配置读回错误，以及 SCL 持续低电平时的有界超时。仿真缩短等待参数，以加快验证；综合使用顶层默认 50 MHz/100 kHz 参数。

## 上一轮独立工程的已有 Gowin 编译记录

以下结果来自本次上传前已存在的 `E:/TOUCH_LED_TEST`。本次只复制、读取并归档已有报告，没有重新运行综合、布局布线或下载；纯 HDL 源码、CST/SDC、GPRJ 和编译脚本均与该独立目录逐文件比对一致。这些结果不覆盖根目录的完整电子琴工程。

- 工具：Gowin V1.9.12.04 x64。
- 器件：GW5AST-LV138FPG676AC1/I0，C 版本。
- 顶层：touch_led_top。
- 最终布局布线完成时间：2026-10-26 19:32:36。
- 综合通过，布局布线通过，位流生成通过。
- 结果：`impl/pnr/touch_led.fs`。
- 时钟约束：50 MHz；本次报告估算 Fmax 为 164.366 MHz。
- 时序报告检查：setup 违例端点 0，hold 违例端点 0；对应 TNS 均为 0。
- 本次日志没有 PR0004 错误。

仍有一条 PR1014：板载 P16 时钟输入的 `clk_d` 使用了普通布线资源。警告未被隐藏或禁用，本次实现仍完成了布局布线与位流生成。时序数字仅反映该报告分析到的路径，不代表已验证外部总线波形或实板行为。

引脚报告回读：SDA=U16、SCL=V16、INT=U15；clk=P16、rst_n=K16、led_n=R26，均与本工程 CST 一致。

归档记录：[PnR 日志](../../reports/touch_led/2026-10-26/original_pnr.log)、[时序报告](../../reports/touch_led/2026-10-26/original_timing.tr)、[引脚报告](../../reports/touch_led/2026-10-26/original_pin.html)。原报告内的绝对路径保留来源，不代表仓库路径。

`.fs` 和实现缓存按仓库忽略规则不提交。本机原下载文件仍在 `E:/TOUCH_LED_TEST/impl/pnr/touch_led.fs`。

没有连接或操作下载器，尚未上板实测。
