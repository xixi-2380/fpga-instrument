# CDC载荷优化检查点

仅移除rgb_status_cdc中held_data的syn_preserve属性，保留request_sync/ack_sync的syn_preserve及syn_async_reg；RTL握手、复位、接口和时钟不变，允许综合器裁剪载荷常量和未使用位。注意这是综合属性变化，仍需检查最终CDC实现，不属于物理签核。

Gowin V1.9.12.04综合8分40秒通过。LUT80672→76540，寄存器55227→52653；参考/像素/音频估算Fmax44.609/45.236/55.391MHz，相比上版部分下降，尚未达标。

本轮P&R完成布局并记录Routing Phase 0后仍长时间运行，按停止检查点主动终止。没有本轮最终未布通网络数、CLS数据或STA结果；impl/pnr旧rpt仍属前轮，禁止混用。没有可验收新位流或硬件烧录。动态回归尚未补齐。此提交仅为资源优化检查点，不代表整体优化完成。
