# 2026-10-31 结构优化窗口

本轮起点94030a；用户授权约75分钟持续优化、命令行/电脑操作、综合及布局布线与功能分支发布。不更新main、不下载硬件。工具Gowin V1.9.12.04，GW5AST-LV138FPG676AC1/I0、Version C。73球位、CST、SDC、PLL及50/61.44/35MHz目标保持。

## 改动

- rgb_status_cdc增加默认开启的RESET_PAYLOAD选项；仅显示主状态和PCB快照使用无载荷复位方式，控制同步器、valid和复位同步保留。消费者必须在valid前忽略载荷，PCB可见位独立用pcb_valid和主status_valid门控。
- 显示专用rgb_frame_status_cdc等待原render_frame_start才将完整源保持数据提交，并完成四相握手。rgb_display默认FRAME_LOCKED_SNAPSHOTS=0兼容旧组件接口；生产keyboard_top显式启用1。renderer此时直接读取帧保持数据，删除第二份帧快照。其余CDC使用者保持原行为。
- 此显示结构不是旧版逐帧采样年龄等价：正常运行时源快照最多额外老一帧，默认约18.15ms；开/闭诊断与其可见确认也可能多等一帧，闭页等待保守延长。音频事件、采样数值、GPIO和时钟不改。每个桥内部完整原子，多个独立桥不是一个共同事务。
- audio_visualizer改用统一移位写入128点窗口，保持点顺序、四倍抽取及整窗发布，减少128个字选择写使能。
- sustain_envelope用单个signed18位误差替代双向减法，保持原幅度变化规则，未增加音频拍数。
- build_keyboard新增显式--pnr-profile routability，默认行为不改；该模式Place1/Route2/route_maxfan60，优先布通而非降低频率/放宽SDC。

## 官方工具依据

本机IDE/doc/EN/SUG100-4.4.7E_Gowin Software User Guide.pdf，PDF51–52页：Place1优先routability；route_maxfan较小可能导致route failure，默认23，范围1..100。SUG1220-2.1E_Gowin Software Tcl Commands User Guide.pdf，PDF44/49页给出place_option1和route_maxfan60示例。UG303-1.0E_Arora Ⅴ Configurable Function Unit (CFU) User Guide.pdf，PDF34–35页说明同CLS寄存器的控制输入网络匹配要求。工具参数试验不能代替功能或时序验收。

## 验证与状态

动态测试、形式等价证明和实际综合/实现结果由本轮validation与构建输入manifest记录。所有“失败/主动停止/兼容镜像”应与成功分开记录。Icarus13对原keyboard_top中的touch_update先用后声明报错，工作副本只前移声明后官方库顶层编译通过；生产Gowin综合为实际顶层语法/展开检查。不能把该兼容镜像称为原顶层Icarus通过。

本轮最终状态见下表及对应JSON；没有新的合格位流，不得使用旧impl/pnr中的.fs作为本轮结果。

## 本轮最终检查点

代码检查点c22170c；组合综合LUT78932、寄存器49398、ALU11082；ref/pixel/audio估算Fmax50.632/45.078/55.626MHz。相对94030a减少3255FF，LUT反增2392。渲染器FF4060→805；波形采集控制集131→4；宽载荷移除6189个FF异步复位负载。不能把资源下降等同布通成功。

- Place1/Route2/maxfan60：18分58秒，PR0004，6488条未布通，CLS60379/69120（88%）。不推荐将此试验profile当作已成功的默认值。
- 同网表Place3/Route2/maxfan23：stopped_at_time_budget；未布通数None；耗时秒None。完整数据见reports/structural_optimization/window_2026-10-31/default_result.json。

已完成当前候选约709万项动态检查（包含两个显示模式）、完整slew输入域2^34数学等价证明。测试夹具移入sim/structural，避免旧run_sim.py自动发现不适用的顶层/缺少reference；专用runner路径回归29配置612316检查通过，属于重布局验证，不重复计入上述709万。

发现gw_sh会持久化process选项，最终脚本对所有将运行pnr的阶段先显式恢复3/2/23，再允许显式routability覆盖；6组Tcl mock参数路径通过。引脚验证期望由过时W25修正为真实CST的W23，没有改CST。实际物理实验使用的脚本副本分别保存在本机对应构建目录；脚本验收修正未改变已经冻结的HDL或网表。

正常构建命令：

    python scripts/build_keyboard.py --stage syn --out-dir reports/new_syn
    python scripts/build_keyboard.py --stage pnr --synthesis-inputs reports/new_syn/netlist_manifest.json --out-dir reports/new_pnr

本轮仍未达到整体优化完成/可烧录验收。保留下一轮滑音缩位与删除内部宽valid mask候选，二者已动态验证但未综合，未应用到生产，不能与本次物理结果混用。若继续，需要先评估其实际映射，再考虑更大的共享包络调度重构；不能仅凭计数承诺两小时内成功。
