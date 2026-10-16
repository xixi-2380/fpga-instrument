# 模块与独立测试索引

全部音频模块用 audio_clk；参考域控制模块用 ref_clk。复位高有效。位宽及握手细则见 interfaces.md。

| 模块 | 功能 | 主要接口 | 独立测试 |
|---|---|---|---|
| reset_sync | 异步置位、两拍同步释放 | clk/arst→rst | tb_reset_sync |
| lock_guard | LOCK 同步及连续稳定资格判断 | clk/rst/lock_async→qualified | tb_lock_guard |
| audio_timing | 20 周期半位时钟、1280 周期帧 | clk/rst→bck/rise_ce/fall_ce/frame_ce/bit_index | tb_audio_timing |
| sine_rom | 4096x16 单周期正弦查表 | clk/ce/addr→q | tb_sine_rom |
| dds_sine | 独立32位相位与FCW，声部重用时同步重启相位 | clk/rst/sample_ce/fcw/restart→sample/valid/phase | tb_dds_sine |
| startup_envelope | 完整 480 帧静音与 240 帧淡入 | clk/rst/frame_ce→pa_enable/level | tb_startup_envelope |
| tone_gain | 固定点增益；默认16位、四声部路径保留24位输出 | clk/rst/in_valid/in_sample/level→out_valid/out_sample | tb_tone_gain |
| frame_buffer | 成对缓冲、背压及缺样本零码 | sample_valid/ready、左右输入→frame_l/r、underrun | tb_frame_buffer |
| pt8211_tx | MSB 先行的 16 位 LSBJ | clk/rst/fall_ce/bit_index/frame_l/r→ws/din | tb_pt8211_tx |
| pll_pair | 50→32→61.44 MHz 器件 PLL | ref_clk/rst/pll2_rst→mid_clk/audio_clk/lock1/2 | tb_pll_pair，官方模型 |
| clock_reset | POR、分级锁定及多域复位 | ref_clk/external_reset/lock1/2/audio_clk→pll1/2_reset/audio_reset | tb_clock_reset |

历史结果保存在 reports/validation.md 和 reports/sim；本次清理验证见 reports/cleanup/validation.json，后续默认日志写 reports/sim/current。
当前板级集成由 tb_keyboard_top 检查，端到端音频由 tb_keyboard_core 检查；旧 D0/D1 顶层及其专用测试已从工作目录移除。
当前音符频率在采样边界更新，键盘事件、四个包络和音频位于同一音频时钟域。

## 当前 D2 键盘与运行指示模块

| 模块 | 功能 | 独立或集成测试 |
|---|---|---|
| matrix_keypad | 低/高阻列扫描、行同步、消抖和矩形歧义处理 | tb_matrix_keypad、物理引脚映射测试 |
| key_note_events | 原单音键控文件重命名修改；矩阵位图转带编号的握手事件 | tb_key_note_events |
| adsr_envelope | Attack/Decay/Sustain/Release 包络 | tb_adsr_envelope、tb_adsr_production |
| keyboard_core | 可替换矩阵输入适配器：扫描、按键策略、通用音符事件 | tb_keyboard_core、tb_keyboard_latency |
| synth_core | 独立四声部音源：事件分配、四路ADSR/DDS、混音及PT8211输出 | tb_synth_core及现有键盘/板级集成测试 |
| voice_allocator | 音符身份、独立释放、重触发与满额替换；有界年龄排序 | tb_voice_allocator |
| voice_mixer | 24位声部符号扩展后40位求和、一次截断及16位饱和 | tb_voice_mixer |
| run_leds | 参考域流水灯、未就绪超时的PLL/复位诊断和状态同步 | tb_run_leds |
| keyboard_top | 板级 PLL、复位、键盘三态列和音频镜像 | tb_keyboard_top，官方 PLL 行为模型 |

主工程 keyboard_adsr.gprj；当前输出 D2_keyboard_leds。设计接口见 interfaces.md，上板诊断见 bringup_run_leds.md。测试通过不等于实板已发声。

2026-10-15接口分离：原keyboard_core中的音频流水线提取到职责独立的synth_core，keyboard_top连接两者。新模块是用户要求的独立音源，不是重复版本；原流水线各子模块、功放及复位功能不变。

当前四声部模块20个HDL均登记于唯一GPRJ；单声部分离阶段的音符接口已由valid/ready事件接口替代，见interfaces.md的“四声部并行事件接口（历史）”一节。每声部DDS使用独立同步ROM端口；本阶段未实现32声部或共享ROM调度，不引用旧P&R资源数字验收新源码。

## 下一阶段修改分工（规划，尚未实施）

32声部计划先验证原voice_allocator的参数边界，再在原synth_core/dds_sine/voice_mixer内共享波表、增益与顺序混音；ADSR第一版保留独立实例。原TB和poly_audio_reference将按声部数参数化，现有键盘和板级路径继续回归，不创建第二套工程。详细调度、接口一致性和验收矩阵见[32声部实现规划](interfaces.md#32-声部实现规划)。当前文件列表和RTL功能仍为四声部。

2026-10-16阶段B：原dds_sine已改为多相位上下文共享ROM，原synth_core调度共享增益，原voice_mixer接收first/last串行声部样本。当前实际约定看interfaces.md的“共享调度实际接口”，上文并行说明是历史；仍为同一20文件工程，无新增功能模块。
