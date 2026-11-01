# 显示时序候选：并行按钮布局

候选目录为 `F:/FPGA_Projects/fpga-instrument-main-display-candidate-20261101`，源于冻结的 main 整合工程。**已冻结，可以独立综合**。本子任务没有启动 Gowin，未改动原生产目录。

唯一生产 RTL 改动为 `src/rgb_ui_renderer.sv`：

```text
SHA256 38c8ac0ab8504874f711cc7c3f92266d388c2562fdd4a3a6c83ac363afad7c3d
```

端口和参数声明逐字保持一致，像素管线延迟仍为 9 拍。GPRJ、约束、ROM、FFT/XY、主题素材、触屏模块及布局头文件均未变化。`frozen_manifest.json` 记录 130 项生产源/工程哈希；原生产目录的相同 130 项仍与复制时一致。

## 改动原因

首轮综合最差 pixel 路径为 `raster_y_5_s0 → tx_s1_10_s0`，36 级逻辑，报告频率 33.014 MHz，未达到原 35 MHz 目标。路径经过矩形命中、动作编码、动作标签、双语词表、文字长度及动态居中计算，最后才写文字 X 坐标。完整基线报告保存在 `baseline_synthesis_timing.txt`。

本候选将 61 个按钮展开为独立恒定矩形。标签、文字长度、宽字形标志及居中位置只由帧状态计算；像素坐标不再参与这一串译码/居中运算。命中结果在 64 叶平衡 OR 树中直接选择最终布局描述，保持原有页面/标题覆盖顺序。OR 树源级深度为 6 层，但真实网表延迟、LUT 数和布线结果必须等待本候选实际综合。

旧设置页的 Tremolo 速度按钮与 y=390 页脚存在两行重叠；已明确保留原来的页脚优先，不改变按钮矩形。状态标签函数改为显式状态参数，使独立 `always @*` 在模拟器中也能响应菜单/效果状态变化。其余组合、状态快照、动画时钟和像素寄存器过程没有改动。

## 验证

| 项目 | 结果 |
|---|---|
| 原版/候选完整逐拍比较 | 1,907,773 次布局描述、同次数 RGB/DE/HS/VS、同次数动作比较，全部通过 |
| 独立按钮边界比较 | 111,273 次布局/RGB/动作比较通过；192 组状态，检查矩形左上外侧、左上边及末行/末列，并断言每点最多一个按钮命中 |
| 原标准显示回归 | 163 项触屏 + 1,796,592 项像素/同步/帧边界检查，合计 1,796,755 项通过 |
| 页面图像 | 15/15 PPM 与原生产 `display_verified` 同编号图片 SHA256 完全一致；1 张 800×480、14 张 400×240 隔点采样 |
| 官方原语顶层编译 | 用当前候选全部顶层依赖及官方 GW5A 原语编译通过；70 个源/原语哈希已记录 |
| 接口/源一致性 | 端口、9 拍延迟不变；除 renderer 外所有生产文件与复制基线哈希一致 |

完整逐拍比较同时检查 `base/fg/text/len/tx/ty/wide_text/font_addr/font_bit/text_ink/alpha_font`，以及最终 RGB 和控制同步，不仅比较最终图片。它使用原生产渲染器副本作为参考，跑同一套 15 页刺激，并附加 192 组主题、语言、页面、音色、效果、传感器/灵敏度/Chorus 状态的矩形边缘检查。

报告分别为 `equivalence/validation.json`、`equivalence_boundaries/validation.json`、`display_verified/validation.json`、`vendor_compile/validation.json`。`display_verified/all_pages.png` 是页面总览，`images.json` 记录图像哈希及与基线相等标志。验证结束后所有报告源哈希均已复核。当前没有本子任务遗留的仿真进程。

## 复现和物理验收

- `scripts/optimize_renderer_buttons.py` 从本报告的 `reference_rgb_ui_renderer.sv` 重建候选；正常 Gowin 工程构建无需执行生成脚本。不要在综合/P&R 已开始后运行它。
- `scripts/check_renderer_candidate.py` 运行完整原版对比；`--boundaries-only` 运行独立状态/边缘对比。
- `scripts/run_merged_display_tests.py --tool-bin C:/Users/10939/Documents/Codex/2026-10-30/qin-2/work/sim-tools/mingw64/bin --out-dir reports/display_timing_candidate/display_verified` 运行原标准回归。
- `renderer.patch` 为唯一生产源码改动的统一 diff。

**不改变 35 MHz 时钟或任何约束**。本报告没有声称综合 Fmax、资源用量、STA 或布局布线已改善；这些项目由主代理在冻结候选上独立测量，结合音频候选再决定是否采用。
