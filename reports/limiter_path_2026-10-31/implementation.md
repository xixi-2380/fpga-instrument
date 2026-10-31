# 2026-10-31 本机实现检查

输入为 d2c04786dafc750a7bddfd06f2927ac34cdc7903 对应限幅器修改；在 F:/FPGA_Projects/fpga-instrument-codex-performance-fx-enhancement 运行既有脚本，工具Gowin V1.9.12.04，器件GW5AST-LV138FPG676AC1/I0、Version C。未改CST/SDC/PLL，未烧录。

综合8分17秒：LUT85383、寄存器55231；ref/pixel/audio估算Fmax为48.618/45.994/56.615MHz，尚不能称时序通过。音频最差路径转移到sustain_envelope的product至current。

布局布线21分59秒后失败：PR0004，5309条未布通网络。Logic98836/138240=72%，CLS61868/69120=90%，BSRAM173/340=51%，DSP199.5/298=67%。没有有效最终位流或最终STA通过结果，旧.fs不得作为此版产物。

资源和高扇出审查发现显示renderer与pcb_controls仍为最大独立逻辑块（11925/10290 LUT），全局PRIMARY与LW资源各8/8已使用，高扇出数据/控制也被自动提升到全局网络。这是后续压缩显示数据通路、检查全局资源分配的线索，不足以认定单一根因。需继续做动态等价回归及可布通实现，当前优化未全部完成。
