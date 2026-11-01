# 保留 FFT / 单声道延迟 XY 最终回归

本目录使用现有 `sim/tb_audio_spectrum.sv`、`sim/tb_lissajous_plot.sv`，分别最小编译实际生产模块；没有改写算法、生产 ROM 或测试阈值，也没有再次执行 15 页像素渲染。运行工具为外部完整 Icarus 目录 `C:/Users/10939/Documents/Codex/2026-10-30/qin-2/work/sim-tools/mingw64/bin`。

**结果：1,345,091 项检查全部通过。**

| 项目 | 检查数 | 结果 |
|---|---:|---|
| 2048 点 FFT RTL | 1,295,379 | 8 帧均在 93,439 个分析时钟内发布；双口 RAM 写时保持输出、同时写地址不同、busy 时输入不破坏结果、复位中断后完整覆盖旧 RAM 均通过 |
| 64×64 延迟 XY | 32,776 | 对独立 Pillow 栅格参考逐像素比较，含构建时继续读旧前台、帧边界发布、复位失效与重新构建 |
| NumPy FFT 数值检查 | 16,936 | 8 帧，最大实部/虚部分量误差 8.002360750941934 LSB，小于现有 16 LSB 阈值；64 带幅度映射逐项相符，32 声部频峰检查通过 |

参考激励由原 `scripts/reference_audio_analysis.py` 生成：静音、11/12 号 FFT bin 的正弦、双音、32 音、负满幅直流、单脉冲和另一正弦。XY 为零波形、分段波形及正负交替极限波形。`scripts/check_spectrum_fft.py` 用 NumPy FFT 和生产 `assets/spectrum_config.json` 的分带界限检查 RTL 输出；保留其既有“高频分组可合并峰值、相对 L1 幅度不是校准 dBFS”解释。

生产连线只读核查：

1. `keyboard_top.sv` 的 `sound` 输出 `visual_sample_valid/visual_sample`，原样连接 `lcd_on.display_driver` 同名输入。
2. `synth_core.sv` 的生产参数开启 `OUTPUT_FILTER_ENABLE=1`；`visual_sample_valid=output_valid`，观察采样来自末级滤波输出。立体声时先用有符号加宽求左右均值，再给这个共同的单声道分析口；XY 没有改成左右声道相关图。
3. `rgb_display.sv` 的波形观察器和 `audio_spectrum` 均直接接该共同分析口，无反压回音频路径。频谱 `{spectrum_ready,spectrum}` 经 513 位 `analysis_bridge` 进入渲染器，ready 有效后显示。
4. 波形观察器每 4 个有效采样取一个高 8 位点，128 点完整快照占原状态 `[1111:88]`；`lissajous_plot` 接此字段。其 `source_y` 索引比 `source_x` 早 4 个波形点，所以对应原音频 16 个采样延迟。
5. XY 的构建由帧边界和视图 2 触发，菜单/箜篌/灵敏度页不启动；像素读取仍有独立显示区域门控。模块双缓冲发布行为由上述独立测试验证，页面和状态字段对应由此前 `display_verified` 回归验证。

`validation.json` 记录每次编译/执行命令、持续时间、源码/FFT ROM/测试/参考脚本哈希以及输入输出哈希。`wiring_review.json` 另记录连线审查文件哈希。`fft_numeric_check.json` 是原数值脚本输出。所有测试均为模块行为/数值证据；完整顶层功能、综合资源、真实 STA、LCD 和音频电气验收属于主任务。

复现：在工程根运行 `python -X utf8 reports/integration_20261101/analysis_final/run_analysis.py`。需要 NumPy、Pillow；本机脚本给子进程加入已有 `work/ui_deps` 的 Pillow，不更改全局 Python 安装。运行只写本报告目录。
