# 2026-11-01 整合显示与触屏

本轮显示保留 main 的英伦、猫动画、卡皮巴拉动画及隐藏静态人物彩蛋素材，中英文标题/界面、2048 点 FFT 的 64 带频谱、单声道延迟 16 采样的 XY；加入 DDS 的 36 键音符显示、16 音色双页选择、箜篌/Chorus 和蓝牙/Flash 曲库界面。主题、语言、视图和彩蛋均有触屏按钮。超声波设置页用于音高控制，箜篌页只读提示“超声波控制音高”，不提供触屏滑音条。屏幕音量调节保留。

已删除显示端 PCB 诊断快照和页面、原始事件/高级十六进制诊断、录制/自定义键位入口、S0～S3 操作入口。灵敏度页只调整三板统一的 GSR/KOR，并显示应用忙、成功或失败；不显示板号、通道和诊断计数。曲库中的 Flash 保存/删除动作保留，用于现有曲库数据，和已删除的演奏录制无关。

## 文件及接口

- `src/rgb_display.sv`：保留 DDS 原有命名端口，删除 `pcb_status`、`pcb_visible`；新增 `theme_id[1:0]`、`view_mode[1:0]`、`language_zh`、`sensitivity_status[31:0]`。`visual_sample/visual_sample_valid` 应接音频末级滤波后的单声道观察采样。现有 `more_status[145:0]`、`performance_status[63:0]`、`ultrasonic_status[33:0]` 保留。
- `src/rgb_ui_renderer.sv`：像素 RGB、DE、HS、VS 同步延迟 9 拍；默认在帧边界锁存状态。原 DDS 状态低 1208 位不重新解释；新字段追加在高位。
- `src/config/ui_layout.svh`：所有普通按钮使用共同矩形定义，矩形右边/下边不属于命中区域。渲染和 `ui_touch_actions` 共用定义。
- `src/ui_touch_actions.sv`：单次按下产生一个命令，松开后重新允许触发；校准未完成、分辨率不为 800×480、错误、无效快照、多指及越界触点不触发普通按钮。新增 `harp_active`、`sensitivity_open` 输入，删除 `pcb_page` 及旧 PCB 连发参数。
- `src/ui_theme_art.sv`、`src/audio_spectrum.sv`、`src/lissajous_plot.sv`：沿用审计过的 main 版本，保留 FFT RAM 修复和原单声道延迟 XY 算法。原主题 ROM 和素材均继续使用。

1280 位显示状态高位分配：

| 位 | 内容 |
|---|---|
| 1207:0 | 原 DDS 状态 |
| 1209:1208 | theme：0 英伦，1 猫，2 卡皮巴拉，3 隐藏彩蛋 |
| 1210 | language_zh |
| 1212:1211 | view：0 波形，1 频谱，2 XY |
| 1244:1213 | sensitivity_status |
| 1279:1245 | 保留，置零 |

`sensitivity_status`：GSR `[3:0]`，KOR `[11:4]`，busy `[12]`，error `[13]`，success `[14]`，open `[15]`，online `[18:16]`，其余保留。原超声波 34 位格式不变：page `[33]`、enabled `[32]`、响应灵敏度 `[31:29]`、最小厘米 `[28:22]`、最大厘米 `[21:15]`、state `[14:12]`、距离 BCD `[11:0]`；其用途改为音高控制。

新增动作（旧 0～41、64～71 和 80 的有效用法保留）：

| 动作 | 数值 |
|---|---|
| THEME / LANGUAGE / VIEW / EGG | 81 / 82 / 83 / 84 |
| SENSITIVITY | 85 |
| GSR_DOWN / GSR_UP / KOR_DOWN / KOR_UP | 86 / 87 / 88 / 89 |
| SENS_APPLY / SENS_DEFAULT / SENS_BACK | 90 / 91 / 92 |
| HARP_OPEN / HARP_BACK | 94 / 95 |
| CHORUS / CHORUS_MIX / CHORUS_DEPTH / CHORUS_RATE / HARP_TONE | 96 / 97 / 98 / 99 / 100 |

96/97 已不再用于录制。箜篌弦区域继续为 x=88～664、y=116～348，12 弦中心为 `112+48*s`；弦的连续触点由 `performance_control` 消费，不经普通按钮动作。底部原触屏滑音区域无动作。

原 2592 位 PCB 跨时钟快照桥已移除。新增频谱分析桥宽 513 位（ready+64×8），现有曲库和演奏状态桥继续使用原握手和帧边界。删除旧桥对应的约束、为新增桥审查必要的复位同步边界由顶层/SDC 整合负责；不要扩大数据路径例外。

## 字库与资源生成

`scripts/gen_ui_language.py` 是兼容原资源构建流程的入口，实际调用 `scripts/gen_merged_ui_language.py`。后者生成 `src/config/ui_language.svh`、`src/rom/theme_font.hex`、`assets/merged_ui_language.json` 及 manifest。

ROM 仍为 **32768×16**，其中 31056 字已使用；包含 167 个汉字的三个样式。保留 main 字库的前 13824 字（原拉丁字形与英文标题），复用未再使用的装饰标题空间。ASCII 32～95 保持普通字符；汉字索引 0～127 编码为 128～255，128～158 编码为 1～31，159～190 编码为 96～127。字节 0 保持空白，避免旧字符串填充位显示成汉字。

离线重生成需要 Python、Pillow 和 fontTools。脚本会优先使用 `work/ui_deps` 中的本地依赖；正常工程构建直接使用已提交 HEX，不依赖这些 Python 包。保留的三个 main 字体子集缺少部分新页面汉字，生成时使用 Windows 微软雅黑补齐，默认 `C:/Windows/Fonts/msyh.ttc`，可用 `UI_FALLBACK_FONT` 指定等效本地字体；manifest 记录实际补字。生成脚本检查缺字、空字形及 ROM 容量。`scripts/build_merged_renderer.py` 留存了从审计 main 版本构造合并渲染器的过程，日常构建无需执行它。

## 验证结果与复现

最终报告位于 `reports/integration_20261101/display_verified/`，以其中 `validation.json` 和 `vendor_compile.json` 的源码 SHA256 为准。

- 触屏：163 项检查，76 次预期动作；覆盖所有页面和主题无关的全局按钮、音色页、曲库、超声波、GSR/KOR、箜篌/Chorus、按住不连发、错误恢复、无效校准、多指，以及旧滑音区域无动作。
- 像素：1,796,592 项检查；逐拍检查 DE/HS/VS 的 9 拍延迟，并检查有效 RGB 无 X、每图有效像素数量、帧边界原子切换，回归“关闭菜单后，滞后的曲库状态不得覆盖演奏页”。RGB 与坐标的视觉对应还通过快照人工检查。
- 15 个页面/语言/主题组合均生成图片且已人工查看：第 0 张为 800×480 全分辨率；其余 14 张以坐标步长 2 采样为 400×240。`all_pages.png` 是总览；单图 PNG、PPM 和 `images.json` 记录尺寸与哈希。它们验证渲染逻辑，不代表 LCD 实板测试。
- 当前 `rgb_display` 及依赖已和 Gowin V1.9.12.04 的官方 `gw5a/prim_sim.v` 独立编译通过，命令和文件哈希在 `vendor_compile.json`。此项是语法/模块接口检查，不是 STA 或布局布线通过的证据。

合计 **1,796,755** 项行为检查通过。测试脚本可从工程根执行：

```powershell
python -X utf8 scripts/run_merged_display_tests.py --tool-bin C:/Users/10939/Documents/Codex/2026-10-30/qin-2/work/sim-tools/mingw64/bin --out-dir reports/integration_20261101/display_verified
```

仍须由完整工程执行综合、布局布线和 STA，并在 LCD、GT9110、实际输入设备上验收；本显示子任务没有启动 EDA 或烧录硬件。
