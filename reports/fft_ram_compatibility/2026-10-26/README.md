# FFT 双端口 RAM 写入模式兼容修正

用户截图报 PA2122：`lcd_on.display_driver/analyzer` 下实部和虚部 DPB 的 WRITE_MODE0/1 被推断为 `2'b10`，当前器件要求 `2'b00` 或 `2'b01`。这属于实现兼容性错误，不是可忽略的时序告警。

原 RTL 无条件同步读取，同时写入同端口，表达了 read-before-write。现在每个实部/虚部端口独立同步过程，写时只写、读寄存器保持；未写时才读，表达 normal/no-change 模式。不修改网表参数，不改约束、RAM 容量、FFT 运算、状态机、ROM、音源、引脚和 UI。原先 WR 后已有 RD 等待，算法不消费写周期的读取输出。

高云官方说明：[Gowin BSRAM & SSRAM User Guide](https://cdn.gowinsemi.com.cn/UG285E.pdf)，双端口 normal=00、write-through=01；以当前器件与用户工具的报错为兼容约束。

## 验证

仅运行 Icarus/vvp 与 NumPy；未运行任何 Gowin 工具。原模块 747539 项，修正模块 1295379 项检查通过，包含零信号、两个相邻低频、双音、32 音、负满幅直流、脉冲、750 Hz、忙时输入和计算中复位。新增两端口写入值、写周期输出保持、双写地址分离检查。

8 帧共 8704 行实部/虚部与 64 柱输出，修改前后逐字节一致；每帧计算仍为 93439 周期。独立 NumPy 16936 项通过，最大分量误差 8.003 LSB 以内。原始长向量和完整 dump 可由现有脚本与 TB 复现，SHA256 记录在 validation.json。

## 用户重新实现

下载更新后的完整 main，解压到新目录，打开 keyboard_adsr.gprj，先 Synthesize，再 Place & Route。不能仅重跑旧综合网表的 P&R；不要手工修改生成网表的 WRITE_MODE 参数。

此处只确认 RTL 的正常模式意图与数值等价。实际高云 RAM 映射、PA2122 是否消失、资源、布局布线与 STA 均待用户重新运行后确认。旧 audio_analysis 报告是 3f8efd6 的历史证据，不覆盖成当前验收。
