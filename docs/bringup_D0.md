# D0 首轮上板验证：只测数字时钟

最新 GPIO 镜像版见 `docs/bringup_GPIO.md`，应烧录 `bringup/D0_header_mirror.fs` 后按排针丝印测量。下文芯片引脚位置仅保留作资料参考。

## 当前文件

- bringup_digital.gprj：实际板级引脚约束的 C 版数字诊断工程。
- bringup/D0_muted.fs：仅供 SRAM 临时诊断，DIN 和 PA_EN 都固定为 0。
- bringup/D0_status.json：生成文件的 SHA-256、源码校验值、实际引脚和时序结果。
- reports/hardware/D0_program_sram.log、D0_program_result.json：首次下载及失败校验记录，保留作审计；并非本次修正版的烧录结果。
- reports/bringup/D0.tr：本次真实引脚布局的时序报告。

D0 不发声，DDS/ROM/增益因输出不可观察会被综合移除，这是本诊断的预期行为，不能用 D0 代替完整合成器验证。
SRAM 配置掉电丢失。未写 Flash。普通 tone_UNVERIFIED.fs 仍为自动引脚的离线产物，不能下载。

## 用户手动烧录

后续烧录由用户操作；助手只修改文件及运行离线验证，不再启动下载器。两个自动下载脚本已停用。

1. 自行打开 Gowin Programmer，选择已连接的下载器并扫描器件；器件选择 GW5AST-138C。
2. Operation 选择 **SRAM Program and Verify**，加载 `E:\gowin\fpga-instrument\bringup\D0_muted.fs`。
3. 执行并保存结果日志。本轮使用 SRAM 临时配置，不选择 Flash 或 OTP 操作。
4. 确认校验通过，再按下表测量 BCK、WS、DIN 和 PA_EN。此文件保持静音，耳机没有声音是预期现象。

首次写入已完成配置加载，但因生成文件默认开启读回保护而校验失败。修正版关闭配置文件 SecurityBit（非 OTP/eFuse 操作），用于 SRAM 回读校验；修正版尚未由助手烧录。
原始失败记录保存在 `reports/hardware/attempt1_readback_protected/`；不得将旧记录算作修正版验收。

## 探测方法

探头使用 10x、直流耦合，地夹接板上标注 GND 的排针或焊盘。不要把地夹接到信号引脚。
先确认芯片丝印为 PT8211（图纸 U6），按封装方向标记识别引脚，不依据照片上下方向猜 pin 1。

| 观察项 | 可按原理图识别的信号位置 | 预期读数 |
|---|---|---|
| BCK | PT8211 U6 pin 1 | 1.536 MHz；周期约 651.04 ns；高低各约 325.52 ns |
| WS | PT8211 U6 pin 2 | 完整周期 48 kHz / 20.833 us；高低各约 10.417 us |
| DIN | PT8211 U6 pin 3 | 持续低电平 |
| PA_EN | 图纸 H17 网络、功放 U32 EN pin 5 | 持续低电平；不要直接探测 FPGA BGA 焊球 |

BCK 可先用约 200 ns/div，WS 用约 5 us/div；电压档约 1 V/div。3.3 V 是板级资料标称值，不是已测结果。
若探测位置被遮挡或不能可靠触及，先提供附近照片定位，不要靠手持探针在密集引脚上滑动寻找。
反馈 BCK/WS 实测频率、幅度，以及 DIN 是否为低；有截图则一并保存。

## 复位和阶段切换

U4 对应核心板用户按钮，不是 RECONFIG 键。按住复位时 BCK=高、WS/DIN/PA_EN=低；释放后重新锁定，数字时钟恢复。
不要把重配置按钮造成的 Flash 重载当作本实验的 RTL 复位。
数字信号通过后，再准备零码开功放和低幅 440 Hz 正弦；左右独响和 30 分钟稳定性分别记录。
目前没有实测结果，不能声称采样率、模拟音频或 <5 ms 响应已上板验收。

## 依据与已知问题

- Dock 背面版本贴纸确认 4071f3，对应官方原理图 PDF 第 5、18 页；音频引脚 E22/F24/G24/H17。
- 已查两份 SOM 原理图 4071/4072，在本实验用到的 P16 时钟、U4 复位及电气标准上相同；核心板实际修订仍未擅自填写。
- Sipeed 官方安装表明确列出 GW5AST-LV138FPG676AC1/I0 与 C 版支持。实物激光字被遮挡，文档依据与实物观察分开记录。
- P16 为官方固定时钟连接，工具出现 PR1014 普通路由警告；保留原引脚，不凭猜测换到其他球位。当前内部路径通过，锁定和频率稳定性需实测。
- 综合 CK3000 自动时钟关系警告保留；显式 SDC 列出正确 50/32/61.44 MHz。
- 输出路径采用 0..30 ns 的实现延迟界限。RTL 在 BCK 下降沿更新 WS/DIN，上升沿距离 20 个音频周期，标称 325.52 ns；留出至少约 295 ns 的数字边沿间距，再由实测核对引脚波形。30 ns 是设计预算，不冒充 PT8211 手册的 setup/hold 规格。
- 初次的同步输出模型和将生成时钟附到 BCK 数据网上的尝试均已保留诊断；最终约束不使用音频 false-path 或多周期豁免。

官方资料：
- https://wiki.sipeed.com/hardware/zh/tang/common-doc/get_started/install-the-ide.html
- references/TANG_MEGA-138K_Dock-4071f3__Schematics.pdf
- references/TANG_MEGA-138K-Pro_4071_Schematics.pdf
- references/TANG_MEGA-138K-Pro_4072_Schematics.pdf
- references/pt8211-v1.7.pdf
