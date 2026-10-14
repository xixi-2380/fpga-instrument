# 验证结果

独立测试：23/23 通过。

| 测试 | 断言检查数 | 状态 |
|---|---:|---|
| tb_adsr_envelope | 59 | PASS |
| tb_adsr_production | 14881 | PASS |
| tb_audio_timing | 9996 | PASS |
| tb_bringup_digital | 36666 | PASS |
| tb_clock_reset | 6 | PASS |
| tb_dds_sine | 10001 | PASS |
| tb_frame_buffer | 9 | PASS |
| tb_keyboard_core | 2342532 | PASS |
| tb_keyboard_latency | 5 | PASS |
| tb_keyboard_top | 329180 | PASS |
| tb_lock_guard | 5 | PASS |
| tb_matrix_keypad | 7183 | PASS |
| tb_mono_note_control | 163 | PASS |
| tb_pll_pair | 101 | PASS |
| tb_pt8211_tx | 646 | PASS |
| tb_reset_sync | 5 | PASS |
| tb_run_leds | 111 | PASS |
| tb_sine_rom | 4097 | PASS |
| tb_startup_envelope | 726 | PASS |
| tb_tone_core | 129700002 | PASS |
| tb_tone_gain | 2001 | PASS |
| tb_tone_play | 375334 | PASS |
| tb_tone_top | 3963 | PASS |

连续顶层测试：48000 帧，另含两次复位与左右独响。
PLL 器件模型与加速启动的板级顶层集成分别验证；标称启动 480/240 帧策略由独立 TB 检查。

内部离线 P&R：setup 违例 0，hold 违例 0。
上述完整正弦可行性工程没有实板 CST，IO 自动放置；D0 GPIO 镜像静音诊断另有真实引脚 CST 和独立 reports/bringup/D0_header.tr，不等同完整音频签核。
综合阶段保留 CK3000 自动时钟关系警告；P&R 的显式 SDC 时钟表正确列出 50/32/61.44 MHz。
官方 prim_sim.v 有静态配置下 @* 空敏感列表警告；原库未修改，本配置的频率和顶层行为测试通过，其他 PLL 动态模式未验收。
异步复位、LOCK 输入、外部 IO 和源同步输出仍需专项板级 STA 核验；未整体 false-path。

资源：Logic 213, Register 141, BSRAM 4, DSP 1, PLL 2

JTAG 已扫描到 1 个器件，ID 0x0001081B。SRAM 诊断下载状态以 hardware_status.json 和 D0_program_sram.log 为准；未测模拟输出、未做实板长稳测试。

GPIO 镜像静音诊断：tb_bringup_digital PASS，新增镜像边沿/复位断言；10 个端口按官方球位约束。
D0_header.tr 的 setup/hold 违例均为 0，文件与源码哈希见 bringup/D0_header_mirror_status.json。
仅新增 GPIO 观测输出，原 DAC 连接保留；下载由用户操作，GPIO 实测尚未完成。

D1 双/左/右低幅 440Hz 已完成实际引脚 P&R，三个版本 setup/hold 违例均为 0。
新增 tb_tone_play 验证完整静音/淡入、复位恢复和声道隔离；详细结果及限制见 reports/tone_play/validation.md。
D1 文件供用户手动烧录，未由助手写入，实际音频和稳定性待测。

D2 矩阵键盘及单声部 ADSR：七个新增独立仿真通过，详见 reports/keyboard/validation.md。
后续综合编译、布局布线和烧录由用户执行，助手只改文件及运行 HDL 仿真；D2 尚未上板验收。
