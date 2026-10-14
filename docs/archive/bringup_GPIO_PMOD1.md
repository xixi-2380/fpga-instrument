# D0 GPIO 镜像版：由用户手动烧录

## 本次文件及行为

使用 `E:\gowin\fpga-instrument-mega138k-pro\bringup\D0_gpio_mirror.fs`。
旧 `D0_muted.fs` 没有 GPIO 镜像，不适用本接线表。
Gowin Programmer 选择 GW5AST-138C、SRAM Program and Verify；烧录由用户自行执行，助手不访问下载器。
原有 PT8211 和功放引脚保留，新增四个 FPGA 输出复制相同内部信号，无需焊线或跳线。
仍为静音数字诊断：DIN、PA_EN 及其镜像固定低，耳机无声是预期行为。

## 接线位置

依据官方 Dock 4071f3 原理图第 16 页 J24、官方全引脚 CST 和用户正面照片交叉核对。
以用户正面照片的方向（网口/HDMI 在上方），取右侧三组 12 针接口中间的一组：位于 ADCV 标识下方、ADCT 标识上方。
直接按板上球位丝印 C24、B24、E25、D25 找孔，不依赖 PMOD 总线位序名称。

| 示波器信号 | 板上丝印 | 原理图 J24 针号 | FPGA 端口 | 标称预期 |
|---|---|---:|---|---|
| BCK | C24 | 11 | DBG_BCK | 1.536 MHz；高低各约 325.52 ns |
| WS | B24 | 12 | DBG_WS | 48 kHz；高低各约 10.417 us |
| DIN | E25 | 9 | DBG_DIN | 持续低电平 |
| PA_EN | D25 | 10 | DBG_PA_EN | 持续低电平 |
| 地夹 | GND | 3 或 4 | 地 | 接此接口标为 GND 的一排 |

按用户正面照片方向，接口由上到下：

```text
靠 ADCV 的一端
  C24 (BCK)      B24 (WS)
  E25 (DIN)      D25 (PA_EN)
  L17            L18          未使用
  H14            H15          未使用
  GND            GND          示波器地夹
  3V3            3V3          电源孔，不接地夹
靠 ADCT 的一端
```

可插杜邦线引出后探测；信号线尽量短。先接 GND，再测 C24 和 B24。
不将镜像输出孔与原 DAC 引脚用导线相连：它们已由 RTL 内部扇出，都是输出。
原理图与旧官方 CST 对 PMOD 位序的命名不同，本工程按实际球位和 J24 针号映射；选用的四个球位两份资料一致。

## 仿真、约束和限制

接口新增 DBG_BCK/DBG_WS/DBG_DIN/DBG_PA_EN，原有接口含义不变。
所有内部逻辑仍只用原音频主时钟；GPIO BCK 仅作输出，不作为内部逻辑时钟。
独立 TB 检查正常播放、BCK 双边沿、WS 字边界、演奏中复位时镜像一致，保留 1.536 MHz 与 16 位/通道检查。
构建脚本检查原有六个和新增四个输出/输入端口的实际球位、约束状态、setup/hold 违例及 SecurityBit OFF，并生成独立文件哈希。
GPIO 与 DAC 引脚会有各自的封装和走线延迟；GPIO 上测得波形用于数字诊断，不能代替 DAC 引脚电气时序或模拟音频验收。
3.3 V 是原理图标称；实际幅度、频率、复位恢复、模拟输出及长稳仍需实测。
原 SRAM 读回失败日志保留；本版尚未由助手烧录。

## 复现

```powershell
python scripts/run_sim.py --test tb_bringup_digital --vendor
python scripts/build_bringup.py
python scripts/finalize_reports.py
```

构建和打包不访问硬件。两个 program_*.py 自动烧录入口继续禁用。
结果：`reports/sim/tb_bringup_digital.log`、`reports/bringup/D0_gpio.tr`、`bringup/D0_gpio_mirror_status.json`。
官方来源：`references/TANG_MEGA-138K_Dock-4071f3__Schematics.pdf` 第 16 页、`references/tang_mega_138k-pro_pins.cst` PMOD1 段；源文件保持只读，来源与哈希见 references/manifest.json。

## 本次离线验证结果

- 独立 TB：PASS，36666 次检查，含 1409 次镜像转换检查。
- 10 个端口球位及物理约束匹配；setup/hold 违例均为 0。
- 保留原 P16 时钟路由 PR1014 和综合 CK3000 警告，实际锁定及频率待测。
- 下载文件 SHA-256：`e7130b096bce0ddb7d785be1045e1071825dd20afe36f2d2ce1a22f2adf2d968`。SecurityBit OFF；未由助手烧录。
