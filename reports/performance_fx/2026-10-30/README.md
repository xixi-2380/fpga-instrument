# 2026-10-30 演奏与效果器软件验证

基于86711a3，分支codex/performance-fx-enhancement。最终冻结源码的19项HDL配置全部通过，11,734,957项检查。24,000组独立合唱矢量、3,644个完整32声部链路的独立左右声道数值通过。最大新增效果交付535拍，原预算544拍；不等同于61.44MHz物理STA或动作到声音的完整延迟测量。

- summary.json包含全部结果及生产/测试输入SHA256。
- static_checks.json记录GPRJ111项依赖、两工作目录语法检查及关键未变文件核对。
- control_ui、audio、regression目录保留编译/测试日志和逐项结果。
- previews内PNG由实际RTL逐像素渲染，800×480；不是美术概念图。
- audio/tb_performance_audio/chorus_chain.txt为生产32声部数据，可用scripts/reference_chorus.py中的check_chain再次验证。
- tb_performance_top仅缩短拨弦门长至16采样，其音频时钟、32声部、限幅和I2S均为生产参数；不能当作物理触摸或I2C整链路测量。
- 行为PLL/IO明确替代。没有运行Gowin、STA、硬件烧录；没有本版本匹配.fs。

独立随机矢量由固定种子生成，不提交可重建的vectors.txt或模拟器.vvp/缓存；执行scripts/run_performance_tests.py可复现。
