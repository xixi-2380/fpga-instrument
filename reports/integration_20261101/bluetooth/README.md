# 整合 main 的蓝牙 / MIDI / Flash 保留验证

10 组共 **5152 项全部通过**，其中实际 `BT_ENABLE=1` 生产顶层为 4280 项、基础回归为 872 项。本任务只新增测试、执行脚本和报告，没有修改生产 RTL，也没有启动 EDA、推送 GitHub 或烧录硬件。

收尾时逐一重新计算了每组 130～131 个已登记输入、源哈希清单和运行日志的 SHA-256：均与测试记录一致；执行期间输入也没有变化。机器可读结果见 `summary.json`，每组原始编译命令、参数、编译日志、运行日志及输入哈希在对应子目录。

## 实际生产顶层：4280 项

`sim/integration/tb_bluetooth_integration_uart.sv` 使用项目生产源文件，真实 50 MHz 参考时钟、61.44 MHz 音频时钟；从 `bt_rx` 输入 8N1 串口波形，在 `bt_tx` 上用独立解码器核验每个起始位、停止位、帧前缀、序号、状态及 CRC。没有强制任何 BT 事件、接管标志、flush、播放器、分配器或曲库内部状态。

完整经过 UART 链路 → 协议/调度 → 生产事件 CDC → 音频桥 → 实际顶层仲裁 → 32 声部合成器/末级滤波，并连接三板 AiP5916 I2C 模型及 SPI NOR 线级模型。覆盖：

- 上电静音、无 ROM 自动播放、无 Flash 自动擦除；HELLO 的 16 个自动声部及 4096 音符容量，JEDEC 查询。
- 手动键已发声时，由 UART 上传接管并清音；上传完整性校验后不自动播放，持续按住的物理键不重新起音。
- 三音和弦 PLAY / PAUSE / RESUME / STOP；各音的身份、音高及力度经过 CDC 后正确，暂停保留自动控制权，STOP 清除所有声音与控制权。
- 自然曲终发送 Off 并走清音流程，随后恢复手动按下/松开；每轮返回均检查手动记账与合成器一致、松手后声部结束。
- UART SAVE、重复 SAVE 幂等、存储忙时拒绝播放器命令、异步保存完成后才报告持久化成功；目录元数据正确。
- FPGA 复位后 Flash 曲目保留、RAM 曲目无效、不上电自动播放；现行触屏入口打开曲库，PLAY 通过本地控制 CDC 从 Flash 加载并播放，STOP 清音，两次 DELETE 确认后原子删除，返回手动屏幕继续演奏。
- 全程无 UART 溢出、帧错误、调度故障或生产滤波立体声欠载。

结果：12 次自动 On、3 次自然 Off、4 次手动 On、3 次手动 Off、12 次真实引擎 flush，NOR 13 次 program / 3 次 erase；仿真到约 75.28 ms，墙钟 678.71 秒。首次手动 On 在上传接管时由 flush 终止，所以手动 Off 比 On 少一次；暂停/STOP 等强制清音也不需要逐音 Off。

## 基础回归：872 项

| 测试 | 项数 | 验证内容 |
|---|---:|---|
| MIDI 协议，4 自动声部 | 144 | 12 字节 MIDI 记录、旋律音色/鼓、边界音高、原子校验、重复上传、事件及回复背压、暂停恢复停止 |
| MIDI 协议，16 自动声部 | 144 | 同上，使用生产自动声部容量 |
| 异步事件 CDC | 131 | 随机相位双时钟、持续背压、完整载荷、一次交付、在途事件共同复位不重放 |
| 真实串口 9600 | 114 | 8N1、HELLO / STATUS、线级回复 CRC、能力与波特率声明 |
| 真实串口 115200 | 114 | 同上，另一支持速率 |
| 新旧 MIDI Flash 格式 | 95 | 混合版本目录、跨页 12 字节记录、五种掉电切点、重启加载、损坏 CRC 拒绝 |
| 32 槽曲库事务 | 90 | 全 32 槽占满、4096 音符跨页、满库替换、多个掉电切点、损坏目录/载荷不误报成功或自动格式化 |
| 生产 1 MHz SPI | 32 | 24 个 12 字节音符经真实 NOR 线级 SAVE、重启 LOAD、每条记录和目录读回验证，无解锁/状态寄存器写或整片擦除 |
| 立体声身份复用尾音 | 8 | 同一调度身份复用时旧尾音保留原音高/力度，新音独立分配，Off 只结束新音 |

## 范围与复现

这是 RTL 行为回归，不是 Gowin STA、官方 PLL 仿真或实板验收。顶层使用显式行为 PLL/IO 模型；触屏在解码快照接口注入，AiP/NOR 使用独立行为外设模型。顶层测试把串口速率设为受支持的 115200；生产默认速率仍是 9600，另有 9600 链路单元回归。顶层为节省仿真时间缩短了 AiP 轮询和 SPI 时序，生产 1 MHz SPI 则由单独测试覆盖。Flash 忙等待为行为模型，不代表特定实物芯片的最坏延迟。

首次测试夹具尝试 1 Mbaud，被生产 core 的参数检查在时间 0 明确拒绝；随后只把夹具改为受支持的 115200，完整重跑通过。诊断保存在 `top_uart/fixture_unsupported_baud.log`，未改动生产参数约束。

`current_input_hashes.json` 汇总所有原测试执行前后已核对的输入。历史夹具间接读取的 `sim/check.svh`、`sim/data/midi_golden.hex` 及项目 GPRJ 补记在 `supplemental_input_hashes.json`；它们是收尾时的当前哈希，不冒充执行前冻结记录。GPRJ 解析出的实际源路径保存在每组 `commands.json`，MIDI 黄金文件内容在测试内另有已知 CRC 校验。

```powershell
python -X utf8 scripts/run_bluetooth_integration_tests.py --suite all
python -X utf8 scripts/run_bluetooth_integration_tests.py --suite top
python -X utf8 scripts/run_bluetooth_integration_tests.py --suite unit --case midi_protocol_16
```

可用 `--tool-bin` 指定 Icarus 目录，`--out-dir` 指定独立结果目录。默认工具为本机会话已有 MinGW Icarus，脚本给子进程 PATH 加入该目录。源、测试或 include 以后有改动时，需针对改动重新验证；本报告不适用于未知后续版本。
