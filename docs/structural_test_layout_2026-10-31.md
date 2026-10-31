# 新增结构优化测试布局修正

7个本轮新增TB移至sim/structural/，内容逐字节不变；参考模块保留sim根目录。原有tb_pcb_*保留原路径。这样旧scripts/run_sim.py的glob('sim/tb_*.sv')不会自动发现需要专用runner及额外参考模块的新测试。旧根脚本不改。

复现结构快测试：

    python scripts/run_structural_optimization_tests.py --tool-bin <Icarus-bin> --suite cdc
    python scripts/run_structural_optimization_tests.py --tool-bin <Icarus-bin> --suite visualizer
    python scripts/run_structural_optimization_tests.py --tool-bin <Icarus-bin> --suite sustain
    python scripts/run_structural_optimization_tests.py --tool-bin <Icarus-bin> --suite frame-visibility

复现frame桥（跳过已通过的完整帧测试）：

    python scripts/run_frame_tests.py --project . --iverilog-dir <Icarus-bin> --out-dir reports/frame_relocated --skip-display

延音逐拍等价测试的手工命令（运行于工程根目录，工具bin在PATH）：

    iverilog -g2012 -grelative-include -Isim -s tb_sustain_slew_equivalence -o reports/sustain_compare.vvp src/sustain_envelope.sv sim/reference_sustain_envelope_94030a.sv sim/structural/tb_sustain_slew_equivalence.sv
    vvp reports/sustain_compare.vvp

输出目录须提前存在。此处仅调整测试文件布局与runner路径，不改变测试源内容或生产代码。
