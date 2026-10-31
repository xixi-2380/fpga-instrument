# 动态验证说明（2026-10-31）

本轮通过项目既有 tools/manifest.json 中的MSYS2官方仓库获取Icarus Verilog13.0及运行库，9个包的SHA256均与既有manifest一致。二进制不提交。源码/工具/命令记录在各results.json。仿真不代替Gowin综合、P&R、STA或实板验收。

## 可复现命令

将新增sim参考模块、TB及scripts/run_structural_optimization_tests.py放入项目对应目录后，运行：

    python scripts/run_structural_optimization_tests.py --tool-bin <Icarus的bin目录> --suite cdc --out-dir reports/structural_optimization/cdc

其余suite为visualizer、limiter、pcb、frame-visibility、renderer。all会运行全部，其中renderer生成13幅完整800x480图，比较慢。参考模块不加入GPRJ。

CDC参考精确冻结于94030a304e4cdce7d329904bfc80b1e7bf688a8c的rgb_status_cdc.sv，仅改模块名。18种WIDTH20/1208/2592、RESET_PAYLOAD0/1、异步频率比例组合，覆盖快速变载荷、源/像素停钟、停钟时复位、不同握手阶段复位，并与原桥逐拍比较valid/pulse及valid后数据。TB比原版延后1ps取样，避免复位刺激和监视同时间的测试竞态；不是修改DUT时序。

Visualizer参考冻结于同一基准的audio_visualizer.sv，仅改模块名；比较移位候选与原实现所有输出每拍，20完整窗口（原4+16随机）、valid空隙和3类部分窗口复位中断。

PCB测试的旧等待48/160/240拍不足以覆盖共享BCD转换（25*19=475拍）及8行发布。readable、renderer动作等待增至900拍；debug动作及遥测变化等待1400拍，覆盖可能正在进行的旧帧以及下一刷新。debug总超时相应增至10ms，断言内容未删减。renderer旧1207位status修正为当前1208位。该改变属于测试刷新延迟适配，不是生产代码修复。

## 当前冻结候选回归

27个轻量配置1121622检查通过：原CDC5302；18参数CDC159186；Visualizer63969；Limiter三配置893116（FIXED0/HOLD0、FIXED1/HOLD0、FIXED1/HOLD240，共8856逐位参考向量，最大104拍）；PCB readable6/debug27；framevisibility模式0/1各8。

framevisibility通过真实PCB源和CDC握手验证关页数据到达之后、framecommit之前不提前返回visible=0，帧提交后才返回音频域ack。首次无效resetless载荷X/全1不会误开页面。使用明确标识的behavioral PLL/IO，仅验证逻辑，不验证物理PLL/IO时序。

在前一候选菜单声明顺序兼容副本上，还完成tb_pcb_renderer3840015检查5全帧、tb_rgb_ui_renderer6144049检查8全帧。当前frame候选的完整display仿真由另一个验证任务执行，不能把前一候选结果冒充当前文件验收。

实际keyboard_top默认参数+GPRJ66 HDL+官方gw5a prim_sim.v用Icarus13编译出现既有touch_update声明后引用错误；只在work副本前移该wire声明后编译展开通过。没有修改生产顶层来规避构建冻结。不能把兼容副本编译通过写成实际未改源Icarus编译通过；实际Gowin综合结论另看构建报告。


最终补充：当前冻结frame候选两模式整帧回归、六配置frame桥共5624165检查通过，完整源哈希及结果见本轮validation.json；新增测试现位于sim/structural，参考模块仍在sim根，复现布局见docs/structural_test_layout_2026-10-31.md。
