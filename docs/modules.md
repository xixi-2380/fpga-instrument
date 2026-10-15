# 模块与独立测试索引

全部音频模块用 audio_clk；参考域控制模块用 ref_clk。复位高有效。位宽及握手细则见 interfaces.md。

| 模块 | 功能 | 主要接口 | 独立测试 |
|---|---|---|---|
| reset_sync | 异步置位、两拍同步释放 | clk/arst→rst | tb_reset_sync |
| lock_guard | LOCK 同步及连续稳定资格判断 | clk/rst/lock_async→qualified | tb_lock_guard |
| audio_timing | 20 周期半位时钟、1280 周期帧 | clk/rst→bck/rise_ce/fall_ce/frame_ce/bit_index | tb_audio_timing |
| sine_rom | 4096x16 单周期正弦查表 | clk/ce/addr→q | tb_sine_rom |
| dds_sine | 独立 32 位相位与 FCW | clk/rst/sample_ce/fcw→sample/valid/phase | tb_dds_sine |
| startup_envelope | 完整 480 帧静音与 240 帧淡入 | clk/rst/frame_ce→pa_enable/level | tb_startup_envelope |
| tone_gain | Q1.15→Q1.23、增益、截断和饱和 | clk/rst/in_valid/in_sample/level→out_valid/out_sample | tb_tone_gain |
| frame_buffer | 成对缓冲、背压及缺样本零码 | sample_valid/ready、左右输入→frame_l/r、underrun | tb_frame_buffer |
| pt8211_tx | MSB 先行的 16 位 LSBJ | clk/rst/fall_ce/bit_index/frame_l/r→ws/din | tb_pt8211_tx |
| pll_pair | 50→32→61.44 MHz 器件 PLL | ref_clk/rst/pll2_rst→mid_clk/audio_clk/lock1/2 | tb_pll_pair，官方模型 |
| clock_reset | POR、分级锁定及多域复位 | ref_clk/external_reset/lock1/2/audio_clk→pll1/2_reset/audio_reset | tb_clock_reset |

历史结果保存在 reports/validation.md 和 reports/sim；本次清理验证见 reports/cleanup/validation.json，后续默认日志写 reports/sim/current。
当前板级集成由 tb_keyboard_top 检查，端到端音频由 tb_keyboard_core 检查；旧 D0/D1 顶层及其专用测试已从工作目录移除。
当前音符频率在采样边界更新，单声部键盘和包络控制与音频位于同一音频时钟域。

## 当前 D2 键盘与运行指示模块

| 模块 | 功能 | 独立或集成测试 |
|---|---|---|
| matrix_keypad | 低/高阻列扫描、行同步、消抖和矩形歧义处理 | tb_matrix_keypad、物理引脚映射测试 |
| mono_note_control | 单声部新键优先、松开回退和 Note 事件 | tb_mono_note_control |
| adsr_envelope | Attack/Decay/Sustain/Release 包络 | tb_adsr_envelope、tb_adsr_production |
| keyboard_core | 扫描到单声部音频流水线 | tb_keyboard_core、tb_keyboard_latency |
| run_leds | 参考域流水灯、未就绪超时的PLL/复位诊断和状态同步 | tb_run_leds |
| keyboard_top | 板级 PLL、复位、键盘三态列和音频镜像 | tb_keyboard_top，官方 PLL 行为模型 |

主工程 keyboard_adsr.gprj；当前输出 D2_keyboard_leds。设计接口见 interfaces.md，上板诊断见 bringup_run_leds.md。测试通过不等于实板已发声。
