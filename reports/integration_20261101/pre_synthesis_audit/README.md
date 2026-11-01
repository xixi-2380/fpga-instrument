# 综合前独立只读审计

审计结果：**未发现阻止当前指定 `keyboard_top` 综合的缺件或接口错误**；存在一个应在下一候选清理的孤立旧模块。生产 RTL、ROM、GPRJ、CST、SDC 均未修改；本审计没有启动 Gowin。

机器可读结果为上一级 `pre_synthesis_audit.json`。`audit.py` 可复现文件依赖、ROM、官方编译哈希及 RTL 层次检查；`elaborated_modules.json` 来自已通过的官方原语编译产物。组合逻辑的默认赋值检查另经人工审阅。

- **工程依赖**：GPRJ 的 127 个启用条目均存在、无重复；其中 69 个 Verilog 源文件。递归 include 均可从源文件目录/`src`/`src/config` 解析，字面量 `$readmemh` 路径在工程根全部存在。工程构建必须沿用工程根的相对 ROM 路径语义。
- **管脚覆盖**：从当前官方编译产物读取 38 个顶层端口，共 69 位，和 CST 的 69 条 `IO_LOC` 一一对应；没有未约束端口、已删除端口的残留约束或重复焊球。此项只检查工程一致性，不复核电路板电气连线。
- **ROM**：核对 43 个实际初始化 ROM 的字数、数据位宽、GPRJ 启用状态和哈希，全部通过。合计逻辑初始化位数 3,595,635；这不包含其他运行时 RAM，也不是物理 BSRAM 占用率。所有 16 个基础音色表均为 4096×16，对应高音表均为 1024×16；FFT 窗函数 2048×16、旋转表 1024×32、分带界限 65×11。主题 ROM 按 `theme_storage.svh` 的 CAT_WORDS=87210、CAPYBARA_WORDS=120096 及其余数组深度逐项核对。
- **字库**：保持 32768×16，使用 31056 字，剩余 1712 字；167 汉字、三样式，未扩容。字体头文件、字库 HEX 和已有显示行为测试的源码哈希一致。
- **复位例外**：SDC 仅一条 `set_false_path`，明确列出 10 个无通配符的 PRESET 端点：display 本身及 status/more/performance/analysis 四个桥，各自 `pixel_reset_sync` 的两级 `pipe`。五个逻辑实例均在当前官方顶层 elaboration 中存在；`reset_sync.sv` 明确为受保护的 2 位异步置 1 寄存器。没有 D/Q、普通数据或宽 PCB 快照的新增例外。`pipe_0_s0/pipe_1_s0/PRESET` 属于综合后命名，最终必须在本轮网表/STA 中确认 10 个实际匹配，源级审计不能代替这一项。
- **现有编译证据**：复用 `vendor_compile_final/validation.json`；所记录全部源/原语 SHA256 与当前文件匹配，无需重复编译。编译使用官方 GW5A 原语、指定 `keyboard_top`；无未解析模块。生产源码的 7 条 warning 均为 `@*` 对整个数组敏感，另外的隐式线网/空敏感列表警告均来自官方 `prim_sim.v`。这是 compile-only 证据。
- **锁存/黑盒风险**：逐一检查 15 处显式组合块的默认值或完整 case，以及新增/合并控制器。未发现输出赋值缺分支，未发现生产 `always_latch` 或 black-box 属性。Icarus 不诊断所有综合锁存情形，仍须检查 Gowin 实际 latch、blackbox 和 RAM 推断日志。

旧功能的实际连接：

- 顶层没有矩阵键盘、DBG 或 S0～S3 管脚；CST 的 S0～S3 只剩注释。`timbre_control.buttons_n` 接常量高，且控制器内不读取它。旧自动音量输入也接常量、未被控制器使用。
- 上电 score_player 的实例 **硬编码 ENABLE=0**，旧 `SCORE_ENABLE` 兼容参数不再参与实例化；不能通过覆盖该参数恢复自动播放。蓝牙/曲库经明确播放命令播放仍保留。
- 当前已 elaboration 模块中没有录制或自定义键位模块。`score_record.svh` 为蓝牙/Flash 歌曲事件记录格式的校验辅助函数，不是现场录制功能。
- 无 PCB 诊断页面或桥；AiP/I2C 可复用驱动内仍声明 health/history 输出，但顶层诊断输出悬空，综合应删除其未用逻辑。统一 GSR/KOR 控制器保留实际驱动配置与结果反馈。
- AiP 额外 12 个辅助键快捷菜单为兼容选项，当前 `KEYPAD_AUX_ENABLE=0`；它们与已删除的板载 S0～S3 不同。原 PT8211/PA 焊盘固定低电平。

**下一候选清理项**：GPRJ 仍启用未被顶层实例化的 `keyboard_core.sv`，内部引用已删除的 `matrix_keypad`。指定顶层的当前官方编译未 elaboration 它，所以没有当前黑盒；为避免自动顶层/全模块检查误选，下一候选应从启用列表移除。主代理已知悉，当前综合运行期间保持冻结。另有未实例化兼容模块 `audio_delay`、`sine_rom`，没有新增功能通路。

**物理验收与回归边界**：主代理正在重跑最终顶层行为回归；审计开始时旧 `main_top/validation.json` 包含已删除文件且音频源码已变，不能直接用作当前行为结果。显示最终行为报告哈希一致。综合后的 BSRAM/DSP/LUT 数、latch/blackbox、10 个 PRESET 匹配及 STA 必须用当前冻结候选的真实结果验收；本审计未声称已经通过布局布线。
