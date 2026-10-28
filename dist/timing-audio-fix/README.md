# 最终编译交付：attempt5

- 烧录文件：`D2_keyboard_leds.fs`。器件GW5AST-LV138FPG676AC1/I0，Device Version C，Gowin V1.9.12.04。
- 位流SHA256：`deacd807ffec7f936b3af28a0ecf95f64f32ef1046e38bc9a6720751a783aaf3`，其余文件以`manifest.json`为准。
- 主工程位于仓库根目录`keyboard_adsr.gprj`；网表、约束、报告、SDF和位流属于同一次匹配构建。
- STA全部报告检查通过、TNS=0。50／61.44／35MHz不变；内部最差Setup Slack分别为2.305／0.059／1.395ns。原音频0.5ns目标尚未达到，按用户认可的零违例结果交付。
- `D2_keyboard_leds.vg`为综合网表；`D2_keyboard_leds.sdf`用于本轮物理时钟界限检查，未执行整机SDF回标仿真。
- `GaoshanScore-0.3.1-flashdiag.apk`为同签名诊断版。完整说明在`docs/timing_audio_flash_fix_2026-10-28.md`。
- 未烧录实板、未手机连接、未实板试听。不要用历史构建或仿真Flash镜像替代本目录的`.fs`。
