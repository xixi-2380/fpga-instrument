# D0 用户指定排针版：由用户手动烧录

## 文件与接线

本次使用 `E:\gowin\fpga-instrument\bringup\D0_header_mirror.fs`。
旧 D0_gpio_mirror.fs 输出在 PMOD1，旧 D0_muted.fs 不含镜像；均不适用本次图片。
Gowin Programmer：GW5AST-138C，SRAM Program and Verify。助手不启动下载器，烧录由用户操作。

按用户提供图片的原方向，上排从左到右分配四路输出：

```text
             BCK          WS          DIN         PA_EN
上排        U22          V19          W20          U26
下排        V22          W19          Y20          V26
           未使用        未使用        未使用        未使用
```

| 图中位置/丝印 | FPGA 端口 | 原理图 J23 针号 | 预期 |
|---|---|---:|---|
| 上排第 1 个 U22 | DBG_BCK | 39 | 1.536 MHz；周期约 651.04 ns |
| 上排第 2 个 V19 | DBG_WS | 37 | 48 kHz；完整周期约 20.833 us |
| 上排第 3 个 W20 | DBG_DIN | 35 | 持续低电平 |
| 上排第 4 个 U26 | DBG_PA_EN | 33 | 持续低电平 |

图中八个孔都不是地。示波器地夹接板上标有 GND 的孔；同一 J23 的第 12 脚为 GND，须按完整接口丝印和针序识别，不能把上面八孔中的任一孔当作地。
无需把 GPIO 与 DAC 用导线相连：RTL 已复制同一个内部信号，原 DAC/功放连接保留。DIN 和 PA_EN 保持零，本版不发声。
使用 10x 探头、直流耦合，可用短杜邦线从这四个孔引出测量。先测 U22 的 BCK，再测 V19 的 WS。
这组排针是空闲扩展接口；本版不支持在该 40 针接口同时连接外部 SDRAM 模块。

## 官方依据与验证范围

- Dock 4071f3 原理图第 16 页 J23：U22/V19/W20/U26 对应 39/37/35/33 脚；同组下排对应 40/38/36/34 脚。
- 官方 `references/tang_mega_138k-pro_pins.cst` 的 Header 段分别为 pin_header[36]/[34]/[32]/[30]，均标注 BANK_VCCIO=3.3；本工程显式使用 LVCMOS33。
- 核心板 4071/4072 原理图第 5 页：四个所选球位属 Bank 2，经板间连接引出。核心板实际修订及实测电压仍未擅自填写。
- 原理图这些网络以 SDRAM_D12/D11/D9/A0 命名，是扩展排针用途；本次将空闲排针配置为观测输出，未连接外部 SDRAM。
- 内部逻辑及串行时序未改变，新增观测输出仍是相同信号的扇出，不新增内部时钟或跨时钟域信号。
- GPIO 与 DAC 的物理路径延迟不同，排针实测不能代替 DAC 引脚电气时序和模拟音频验收。

## 复现与记录

```powershell
python scripts/run_sim.py --test tb_bringup_digital --vendor
python scripts/build_bringup.py
python scripts/finalize_reports.py
```

仿真记录 `reports/sim/tb_bringup_digital.log`；实际引脚、时序及文件哈希记录 `bringup/D0_header_mirror_status.json`；报告 `reports/bringup/D0_header.tr`。
保持 SecurityBit OFF 用于 SRAM 回读。两个自动烧录入口继续禁用，本版未由助手烧录，实测待用户反馈。
保留 PR1014 原时钟路由及 CK3000 综合警告，实际锁定/频率待实测；完整正弦及其余阶段状态不由本诊断代替。

## 本次离线结果

本次指定排针版结果：tb_bringup_digital PASS，36666 次检查，含 1409 次镜像转换；10 个端口约束位置匹配，setup=0、hold=0。新文件 D0_header_mirror.fs，SHA-256 0a03b95728c83c7b0e5179e121d66c8b618244a5771e1d5659383b8601939355。J23 针序按原理图为 U22/V19/W20/U26 对应 39/37/35/33；仅更正文档针号与 CST 注释，实际 IO_LOC/IO_PORT 均未变化，无需重跑 P&R。未由助手烧录，实测待反馈。
