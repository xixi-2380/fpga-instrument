# 超声波全链厘米与回中范围修正

本次只在用户实板 main `7d84ac3` 的独立后续工程 `F:/FPGA_Projects/fpga-instrument-main-adjustments-20261101` 工作。没有引入暂停的 PNR/art/audio 优化，没有启动 EDA、烧录硬件或改顶层；顶层新的 `distance_cm` 接线由主代理完成。

## 原错误复现

原 `ultrasonic_range` 将回波换算为毫米；`ultrasonic_pitch` 的映射上下限又乘 10，因此音高映射按毫米计算，但屏幕把毫米 BCD 直接标成 CM。用未修改的两个原模块输入真实 **580 μs** 回波（应为 **10 cm**），实际得到：

```text
physical_cm=10 legacy_distance_mm=100 legacy_bcd=100 renderer_suffix=CM incorrect_screen=100_CM
```

这个复现使用落盘基线模块，不靠手写替身或仅检查公式。基线文件及 SHA256 见 `baseline`、`baseline_inputs.json`；日志为 `chain_final/old_unit_bug.log`。

## 修改后的含义

`ultrasonic_range.distance_cm` 和 `ultrasonic_pitch.distance_cm` 保留原 **13 位接口宽度**，单位统一为整数厘米。回波用 `floor((echo_us+29)/58)` 四舍五入；2～400 cm 为有效测量。沿用同步回波、1 μs 时钟使能和有限减法转换状态机，不引入除法器、派生时钟或乘法 DSP。首个同步高电平与 us_ce 重合时也计入测宽，避免 1 MHz 参数下将整 μs 脉冲少计 1 μs。无回波、过长/预先卡高和禁用处理保留。

音高中值历史、有效性判断、上下限比较和线性映射全部使用 cm。显示 BCD 仍为最近的有效原始测距值；音高使用最近三个有效 cm 测量的中值抑制孤立跳点。无效测量不污染历史，暂时保持原值；默认失联 250 ms 后 target_ratio 回 65536，原顶层音高平滑控制继续负责回中。超声波没有接管音量。

原公开信号名 `sensitivity` / `ultrasonic_sensitivity` 保留，避免扩大顶层控制接口变更，语义现在明确为：

- **回中范围 / DEADBAND**，可调 **1～5 cm**，默认 **1 cm**。
- 数值直接表示中心的半宽：1 表示中心 ±1 cm，5 表示中心 ±5 cm；数值更大，保持原音的区间更宽。
- 屏幕显示 `N CM`，上下限显示 `005 CM` / `040 CM`，测距显示例如 `010 CM`，不再存在无单位的响应数值。
- 配置的 minimum / maximum 仍为原来的 cm 值和步进，默认 5～40 cm，不改变原控制按钮行为。

## 映射与窄距离边界

设距离为 d，下限 L，上限 H，中心 C=(L+H)/2，半宽 B。按以下优先级决定目标音高：

1. d≤L：正 2 半音，Q16 ratio=73562。
2. d≥H：负 2 半音，Q16 ratio=58386。
3. 严格内部且 |d−C|≤B：原音，ratio=65536。
4. 其余严格内部点：从回中区边缘到相应端点连续线性映射。比例为 `(abs(d-C)-B)/((H-L)/2-B)`，正侧乘 8026，负侧乘 7150，四舍五入到 Q16。

RTL 用双倍 cm 整数表示，保留奇数跨度的半厘米中心，无需浮点。测试 oracle 独立使用实数中心和比例，不复制 RTL 的双倍整数或串行除法实现。

例如默认 L=5、H=40 时 C=22.5；B=1 的回中区是 21.5～23.5 cm，整数测量 22、23 保持原音。B=5 的区间为 17.5～27.5 cm，整数测量 18～27 保持原音。

**窄距离范围**：若 `(H-L)/2≤B`，全部严格内部点均为原音，两个端点仍优先达到最大 bend；此时内部与端点间可能跳变，这是同时保留“直接 ±B cm”和“端点最大 bend”的明确边界定义，不偷偷缩小用户设置，也不做零除。已穷尽测试每个 B=1～5、跨度 1～12 cm 的内部点和两端。

## 资源与生成文件

仅更改 range/pitch/renderer 中必要逻辑，timbre_control 只增加语义注释，默认值和 1～5 的加减控制本就正确。range 转换分子从 18 位减到 15 位，不再乘 5；pitch 去掉上下限乘 10，中值历史从 13 位减到 9 位、除数/余数从 11 位减到 8 位、比例乘法距离从 13 位减到 8 位。串行映射保持原 24 次移位除法，不增加 ROM 或流水深度。这里只说明结构变化，不声称已实测 LUT/时序或 PNR 改善。

词库 `RESPONSE|响应` 改成 `DEADBAND|回中范围`；重新生成 ui_language、theme_font 和语言 assets manifest。字体仍为 **32768×16**，169 个汉字、使用 31152 word。原 Latin/标题前 13824 word 完全相同。为避免修改冻结源，第二次复现在报告隔离目录生成，四份输出与生产文件逐字节一致。字体依赖通过原 integration 工程的 `work/ui_deps` 加入 PYTHONPATH，没有复制 Python 大环境。

## 验证结果

全部为 HDL 仿真/软件生成校验，不代表实板测量或 STA：

| 验证 | 检查数 | 报告 |
|---|---:|---|
| 独立实数 cm / 回中映射 oracle | **4472** | `control_ultra_verified/validation.json` |
| 控制与音量独立、回中范围上下界、其他保留设置 | **8046** | `control_timbre_final/validation.json` |
| 旧实际模块十倍错误复现 | 2 | `chain_final/old_unit_bug.log` |
| 测距模块完整回归 | 32 | `chain_final/range_regression.log` |
| 真实回波→cm→中值→音高→BCD、失效与禁用 | 17 | `chain_final/physical_echo_chain.log` |
| 生产 50 MHz 时钟、1 μs CE 不同相位的真实脉宽 | 10 | `chain_final/production_clock_echo.log` |
| 实际 renderer 中英词、1～5 CM、上下限及010/400 CM | 13 | `chain_final/cm_screen_labels.log` |
| 字体/词库逐字节复现、前缀/深度/标签 | 6 个条件 | `font_reproduction/validation.json` |

映射覆盖五档各输入 0～450 cm、1000 个确定种子随机序列、0/7 无效档回退为1、512/8191 高位无效输入不截断别名、中值抗孤立尖峰、invalid HOLDING、超时 LOST、禁用/启用、版本回绕、配置中途取消除法和无效范围。真实回波覆盖116/290/580/1305/1334/2320/5800/23200 μs，608/609/610 μs 的 10.5 cm 舍入边界，以及1/401 cm、缺失、卡高。

原 `control_ultra` 的覆盖没有删减以求通过：距离扫掠和窄跨度覆盖扩大了。扫掠新增的 401～450 cm 无效段每十点插入有效测量，以单独检查 HOLDING 语义；超时仍由原来独立的超时测试及真实回波链的 wall-time 测试检查。最初未分离这两种状态时的失败日志保留于 `control_ultra`，最终采用上述 verified 报告。

`scripts/run_merged_display_tests.py` 没有旧 RESPONSE/mm 的固定黄金断言，只生成包括超声波页的图片并检查延迟/可见有效性；因此没有修改其预期或减少页面覆盖。主代理负责完整顶层及组合回归。

复现命令：

```powershell
python -X utf8 scripts/run_ultrasonic_cm_tests.py --out-dir reports/ultrasonic_cm_20261101/recheck
python -X utf8 scripts/run_control_integration_tests.py --tool-bin C:/Users/10939/Documents/Codex/2026-10-30/qin-2/work/sim-tools/mingw64/bin --out-dir reports/ultrasonic_cm_20261101/recheck_control --suite ultra
```

生产源已经冻结，最终文件哈希和全部报告索引见 `handoff.json`。未启动 EDA、未烧录硬件。
