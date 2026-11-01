# 分支整合前功能与代码对照表：用户取舍版（2026-11-01）

> 后续实施要求已覆盖本表旧第09/18项：超声波改为滑音，删除屏幕滑音条；第二EC11改为主音量，屏幕音量保留。当前实现和验收状态以main_integration_20261101.md为准。本表保留分支整合前审查记录。

本表按用户本轮明确指示更新，作为后续main整合的功能范围。原始27项审查编号保持不变。未明确删除的功能沿用上一轮保留建议。本次仅更新取舍文档，未修改HDL/App、未合并main、未运行EDA或烧录。

用户决定：保留动画和彩蛋、现有李萨如/延迟XY；删除回声、高级原始诊断、旧矩阵/DBG生产接口、上电自动播放、全部录制与自定义键位、S0～S3全部控制；删除PCB诊断控制，改为整体GSR/KOR灵敏度界面。

## 取舍总表

| 原编号 | 功能 | 处理 | 整合后范围 |
| --- | --- | --- | --- |
| 01 | 音源基础 | 保留 | 32物理声部、48kHz、DDS/包络/混音与MAX98357A/I²S输出。 |
| 02 | 实体键盘 | 保留新键盘；删除旧接口 | 采用三块AiP5916的36个实体琴键；旧矩阵键盘生产接口不纳入。12个AUX快捷控制继续关闭。 |
| 03 | 音色与鼓组 | 保留 | 16种旋律音色＋10种鼓音，保留现有合成与MIDI音色支持。 |
| 04 | 立体声 | 保留 | 独立左右声道混音、效果与限幅。 |
| 05 | 第一效果：回声或延音 | 保留延音；删除回声 | 保留20～2000ms逐声部松键延音；舍去旧约150msPCM回声生产路径和操作入口。 |
| 06 | 混响、Tremolo及叠加 | 保留 | 混响、1～20Hz音量颤音，以及延音/混响/颤音的独立开关和叠加。 |
| 07 | 三路EC11旋钮 | 保留 | 三路EC11旋钮的转动、单击和双击功能保留，不属于被删除的板载S0～S3。 |
| 08 | 主音量调节 | 保留 | 主音量与平滑调节；原S1/S2操作移除，使用触屏等保留入口。 |
| 09 | 超声波音量 | 保留 | 超声波音量、灵敏度/距离上下限与平滑控制，继续默认关闭。 |
| 10 | 手机蓝牙MIDI与自动演奏 | 保留；裁去新扩展 | 保留手机蓝牙MIDI、导入/转换/上传、播放/暂停/继续/停止及兼容协议；采用App0.4多音色功能作为基线，不纳入0.5的键位配置与录制入口。 |
| 11 | Flash曲库 | 保留 | 32首Flash曲库、目录、歌曲保存/加载/删除和任务结果；删除键位保存不会删除歌曲曲库功能。 |
| 12 | 响度补偿、前瞻限幅和LAT | 保留 | 响度补偿、64采样前瞻限幅、平滑音量与数字LAT。 |
| 13 | PCB诊断和灵敏度设置 | 删除诊断；替换为全局灵敏度页 | 删除整套PCB诊断显示和控制；仅提供一个GSR与一个全局KOR，统一应用到三块AiP5916。无分板选择、无逐通道编辑、无原始诊断。 |
| 14 | 36键自定义音高/音色 | 删除 | 不纳入36键自定义音高/音色。采用固定C4～B6键位；手机编辑、暂存、整组应用等入口和相应逻辑移除。 |
| 15 | 自定义键位掉电保存 | 删除 | 不纳入自定义键位Flash保存、启动加载、双配置扇区和相应协议。保留歌曲Flash服务。 |
| 16 | 演奏事件录制、回传及MIDI导出 | 删除 | 不纳入演奏事件录制、录制RAM、琴端/手机启停、蓝牙回传、断点续传和录制MIDI导出。 |
| 17 | 触屏箜篌与扫弦 | 保留 | 十二弦触屏箜篌、点弦、正反扫弦、重拨及实体/触屏事件仲裁。 |
| 18 | 连续滑音条 | 保留 | 约±2半音的连续滑音，手动声部及其尾音使用，松手平滑回中。 |
| 19 | 立体声Chorus合唱 | 保留 | 立体声Chorus合唱及MIX/DEPTH/RATE、独立开关和参数保持。 |
| 20 | 主题、动画和隐藏人物彩蛋 | 保留；控制转触屏 | 保留main的英伦、小猫、卡皮巴拉和隐藏人物彩蛋，现有动画/静态素材按现状整合；主题切换和彩蛋进入/退出全部通过触屏。 |
| 21 | 中英文整套界面切换 | 保留 | 保留琴端中英文切换及对应字体/文案资源，与主题、演奏和设置页面统一。 |
| 22 | 真实FFT频谱 | 保留 | 保留2048点Hann窗、64频带真实FFT频谱，以及当前main的FFT RAM修复。 |
| 23 | 李萨如/延迟XY | 保留现有实现 | 保留main的李萨如/单声道延迟XY：X[n]与X[n-16]。本轮不擅自改成独立左右声道XY。 |
| 24 | 基础波形、电平、琴键高亮 | 保留 | 波形、电平和36键高亮，与主题/频谱/XY视图兼容。 |
| 25 | 上电与USR默认行为 | 删除自动播放；保留静音待机 | 上电及USR复位后静音待机，不自动播放小星星；示例谱文件可存档。 |
| 26 | 板载S0～S3规则 | 删除S0～S3全部控制 | S0/S1/S2/S3不再控制菜单、音色、音量、效果、主题或彩蛋；设置、选音、音量、效果、主题和彩蛋通过触屏/保留旋钮操作。USR系统复位保留。 |
| 27 | 内部结构优化（不是新增功能） | 保留有效实现；后续重测 | 采用最佳实测DDS版的共享包络、DDS预读、限幅和显示/CDC等结构优化；后续5文件候选依据新main结果再判断，不作为已完成物理验证的成果。 |

另：旧DBG输出生产接口明确舍去，不从main恢复这组端口。保留模块的实际接线以最终顶层/CST重新核对，不能把58管脚与73管脚约束直接相加。

## 简化后的整体灵敏度界面

本表将“整体灵敏度”按以下含义落实，供用户核对：**三块琴键板统一采用一个GSR值、一个KOR值，一次应用到三板；不提供分板或逐通道调节。**

| 项目 | 取舍后的行为 |
| --- | --- |
| GSR | 全局值，沿用现有0～15范围 |
| KOR | 全局值，沿用现有1～255范围，统一用于各通道 |
| 基本操作 | 调节、应用、恢复默认；仅显示当前值及应用中/成功/失败的必要反馈 |
| 默认与持久化 | 沿用现有GSR=2、KOR=4默认值；运行时应用，不新增Flash保存 |
| 删除的界面 | 板号/通道选择、分板/逐通道KOR、OVERVIEW/I2C LINK/KEY TEST/KNOBS诊断页、十六进制/原始事件、统计冻结/清零等诊断控制 |
| 保留的底层能力 | 正常按键扫描、在线/数据有效判断、过期松键、断线恢复、配置写入/回读校验和配置失败处理 |

删除诊断界面不等于删除AiP5916驱动和异常恢复。旧2592位PCB显示快照及其宽文本格式化/渲染分支应随旧诊断页面退出生产实现，新的灵敏度页只传必要的小状态。

## 触屏与旋钮操作范围

- 主题切换、彩蛋进入/退出改为屏幕入口，保持main现有动画与素材内容；不依赖S0～S3。
- 设置页进入/返回、音色、主音量、效果开关/参数、视图和语言均保留触屏入口；三路EC11继续承担已有的效果调节。
- S0～S3的短按、长按及组合功能全部退出生产控制逻辑。USR复位不属于这四个按钮，继续保留。
- 上电静音待机，不把main的上电小星星自动播放接回来。

## 易混淆项目的最终区分

- **保留的延迟XY**是显示用的X[n]与X[n-16]；**删除的回声**是旧音频延迟重放效果。保留前者不会恢复后者。
- 保留松键延音、混响、Tremolo和Chorus；回声的生产路径和操作入口舍去。
- 自定义键位、键位Flash保存、录制及录制MIDI导出全部舍去；MIDI文件导入、蓝牙演奏和歌曲Flash曲库继续保留。
- AiP5916的GSR/KOR是触摸灵敏度，不是音高/音色键位映射；简化灵敏度页不重新引入自定义键位功能。
- 保留当前main的单声道延迟XY，不将其描述成真正L/R立体声相关图。

## 对应代码及实施范围

| 原编号 | 功能 | 已核对的来源代码（固定提交） |
| --- | --- | --- |
| 01 | 音源基础 | [synth_config.svh:24](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/config/synth_config.svh#L24)；[synth_core.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/synth_core.sv#L4) |
| 02 | 实体键盘 | [matrix_keypad.sv:3](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/matrix_keypad.sv#L3)；[aip5916_keyboard.sv:3](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/aip5916_keyboard.sv#L3)；[touch_keyboard_router.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/touch_keyboard_router.sv#L4) |
| 03 | 音色与鼓组 | [dds_sine.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/dds_sine.sv#L4)；[dds_sine.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/dds_sine.sv#L4)；[Timbres.java:3](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/android/app/src/main/java/cn/whu/gaoshan/core/Timbres.java#L3) |
| 04 | 立体声 | [synth_core.sv:130](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/synth_core.sv#L130)；[synth_core.sv:308](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/synth_core.sv#L308) |
| 05 | 第一效果：回声或延音 | [audio_effects.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/audio_effects.sv#L4)；[sustain_envelope.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/sustain_envelope.sv#L4)；[synth_core.sv:311](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/synth_core.sv#L311) |
| 06 | 混响、Tremolo及叠加 | [audio_effects.sv:2](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/audio_effects.sv#L2)；[audio_effects.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/audio_effects.sv#L4)；[timbre_control.sv:18](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/timbre_control.sv#L18) |
| 07 | 三路EC11旋钮 | [ec11_encoder.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/ec11_encoder.sv#L4)；[timbre_control.sv:17](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/timbre_control.sv#L17) |
| 08 | 主音量调节 | [master_volume.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/master_volume.sv#L4)；[timbre_control.sv:443](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/timbre_control.sv#L443) |
| 09 | 超声波音量 | [ultrasonic_range.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/ultrasonic_range.sv#L4)；[ultrasonic_volume.sv:5](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/ultrasonic_volume.sv#L5) |
| 10 | 手机蓝牙MIDI与自动演奏 | [bluetooth_score_link.sv:3](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/bluetooth_score_link.sv#L3)；[MidiFile.java:7](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/android/app/src/main/java/cn/whu/gaoshan/core/MidiFile.java#L7)；[ProtocolClient.java:7](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/android/app/src/main/java/cn/whu/gaoshan/core/ProtocolClient.java#L7) |
| 11 | Flash曲库 | [flash_song_library.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/flash_song_library.sv#L4)；[score_services.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/score_services.sv#L4) |
| 12 | 响度补偿、前瞻限幅和LAT | [audio_limiter.sv:7](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/audio_limiter.sv#L7)；[audio_latency_meter.sv:5](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/audio_latency_meter.sv#L5) |
| 13 | PCB诊断和灵敏度设置 | [pcb_debug_ui.sv:3](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/pcb_debug_ui.sv#L3)；[aip5916_keyboard.sv:9](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/aip5916_keyboard.sv#L9) |
| 14 | 36键自定义音高/音色 | [instrument_features.sv:5](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/src/instrument_features.sv#L5)；[key_note_events.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/src/key_note_events.sv#L4)；[KeyMap.java:3](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/android/app/src/main/java/cn/whu/gaoshan/core/KeyMap.java#L3) |
| 15 | 自定义键位掉电保存 | [flash_keymap.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/src/flash_keymap.sv#L4)；[score_services.sv:43](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/src/score_services.sv#L43) |
| 16 | 演奏事件录制、回传及MIDI导出 | [instrument_features.sv:5](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/src/instrument_features.sv#L5)；[PerformanceRecording.java:5](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/android/app/src/main/java/cn/whu/gaoshan/core/PerformanceRecording.java#L5)；[MainActivity.java:75](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/android/app/src/main/java/cn/whu/gaoshan/MainActivity.java#L75) |
| 17 | 触屏箜篌与扫弦 | [performance_control.sv:5](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/performance_control.sv#L5)；[manual_event_arbiter.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/manual_event_arbiter.sv#L4) |
| 18 | 连续滑音条 | [performance_control.sv:12](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/performance_control.sv#L12)；[synth_core.sv:90](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/synth_core.sv#L90) |
| 19 | 立体声Chorus合唱 | [audio_chorus.sv:5](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/audio_chorus.sv#L5)；[audio_effects.sv:5](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/audio_effects.sv#L5) |
| 20 | 主题、动画和隐藏人物彩蛋 | [ui_theme_art.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/ui_theme_art.sv#L4)；[theme_storage.svh:2](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/config/theme_storage.svh#L2)；[rgb_ui_renderer.sv:73](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/rgb_ui_renderer.sv#L73) |
| 21 | 中英文整套界面切换 | [ui_language.svh:2](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/config/ui_language.svh#L2)；[timbre_control.sv:103](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/timbre_control.sv#L103) |
| 22 | 真实FFT频谱 | [audio_spectrum.sv:5](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/audio_spectrum.sv#L5)；[rgb_display.sv:65](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/rgb_display.sv#L65) |
| 23 | 李萨如/延迟XY | [lissajous_plot.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/lissajous_plot.sv#L4)；[rgb_ui_renderer.sv:80](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/rgb_ui_renderer.sv#L80) |
| 24 | 基础波形、电平、琴键高亮 | [audio_visualizer.sv:5](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/audio_visualizer.sv#L5)；[synth_core.sv:95](https://github.com/xixi-2380/fpga-instrument/blob/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1/src/synth_core.sv#L95)；[synth_core.sv:100](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/synth_core.sv#L100) |
| 25 | 上电与USR默认行为 | [keyboard_top.sv:9](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/keyboard_top.sv#L9)；[keyboard_top.sv:17](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/keyboard_top.sv#L17) |
| 26 | 板载S0～S3规则 | [timbre_control.sv:68](https://github.com/xixi-2380/fpga-instrument/blob/d165cdfa8bee8074dd95fbf0a57fcc83fb929274/src/timbre_control.sv#L68)；[timbre_control.sv:412](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/timbre_control.sv#L412) |
| 27 | 内部结构优化（不是新增功能） | [envelope_precalc_bank.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/envelope_precalc_bank.sv#L4)；[dds_sine.sv:4](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/dds_sine.sv#L4)；[rgb_status_cdc.sv:7](https://github.com/xixi-2380/fpga-instrument/blob/9aa48840bb9074d2f61c21e533d207cf35535780/src/rgb_status_cdc.sv#L7) |

需要特别处理的代码范围：

| 范围 | 处理方式 |
| --- | --- |
| pcb_debug_ui.sv及旧PCB显示链路 | 不纳入旧诊断控制；移除相关2592位快照、格式化和渲染入口，新增精简GSR/KOR控制界面 |
| aip5916_keyboard.sv | 保留采集、恢复和配置校验；复用配置接口统一设置三板GSR/KOR |
| instrument_features.sv、flash_keymap.sv、config/midi_frequency.svh | 不纳入录制/自定义键位专用生产链路 |
| Android KeyMap.java、PerformanceRecording.java及对应UI/协议 | 不纳入；采用保留MIDI/曲库能力的App功能基线 |
| timbre_control.sv、keyboard_top.sv | 去掉S0～S3控制，保留触屏/旋钮、音源、音量和效果控制；上电不启动ROM曲谱 |
| main主题/语言/FFT/XY及资源 | 整套保留所需模块、ROM、字体、素材及生成脚本，按新页面/状态结构接入 |
| performance_control.sv、manual_event_arbiter.sv、audio_chorus.sv | 保留箜篌、连续滑音和合唱 |
| keyboard.cst、keyboard.sdc、显示CDC/动作编号 | 按最终顶层重新统一；保留原时钟目标和必要异步入口处理，不混用不同页面的字段/动作码 |

上述代码范围是待实施计划；链接指向已审查分支原文件，不表示这些删除和改造已经完成。

## 源码基线与后续验证边界

| 分支 | 固定提交 |
| --- | --- |
| `main` | [d165cdf](https://github.com/xixi-2380/fpga-instrument/tree/d165cdfa8bee8074dd95fbf0a57fcc83fb929274) |
| `codex/integrated-instrument` | [5ef731f](https://github.com/xixi-2380/fpga-instrument/tree/5ef731f6afecf4d09646f5b9a9e8003e1ee616a1) |
| `codex/best-measured-dds-2026-11-01` | [9aa4884](https://github.com/xixi-2380/fpga-instrument/tree/9aa48840bb9074d2f61c21e533d207cf35535780) |
| `codex/performance-fx-enhancement` | [0b0d668](https://github.com/xixi-2380/fpga-instrument/tree/0b0d668b5b3f725d7bcfb6c084e12993477242e2) |

最佳实测DDS版本已完整布通，但仍有128个建立时序违例；原位流不代表新main的功能或时序验收。正式整合后应重新核对功能、资源映射、全部管脚、完整布局布线/STA及位流来源。此处不承诺新组合的耗时或时序结果。
