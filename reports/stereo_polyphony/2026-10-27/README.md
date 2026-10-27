# 蓝牙双声道与尾音身份修正验证

基线2d86834；仅更新codex/bluetooth-score-integration，不更新main。纯HDL/数值检查，非Gowin或实板。

最终16项配置、20,472,477次检查通过。配置和源码SHA256详见validation.json。

- baseline_tail_reuse：原RTL用自动ID0先弹C4，Off后尾音仍响，再以低力度弹G4；旧尾音频率变成G4，断言按预期失败。它是故障复现，不计入通过总数。
- final/tail_mono、tail_stereo：旧尾音原频率/力度/音高保持，新音独立声部，Off释放当前所有者，通过。
- final/numeric_stereo：独立相位、ROM、定点增益及左右混音数学参考；32物理声部、七音色、不同力度、自动ID复用释放重叠、三种效果、音量归零/恢复、清空与字中复位。2223帧、4440个外部引脚解码声道字匹配；2175组左右不同。实际交付525拍≤544拍。效果器/音量参考复用未改动RTL，用数学参考的独立左右输入验证接线隔离，不冒充独立效果算法。数值测试为17样本Echo和3/5/7/11样本Room，生产48kHz和32声部帧周期不压缩。
- stereo_echo/room/tremolo：生产50MHz/61.44MHz、1280拍/帧、默认效果延迟，真实播放器/异步事件CDC/合成器联合；16 Off+16 On最坏81.58µs，暂停、继续、停止及左右串行清空通过。
- mono_math/allocator：32声部独立算术和原手动重触发规则；allocator的1/3/4/17/32参数通过。
- bluetooth_protocol_audio/uart_top：真实协议及UART路径到双声道生产顶层；前者明确使用既有单声部/缩短逻辑毫秒夹具做控制验证，不能当生产16声部吞吐证据。
- manual_volume_release/british_ui_stereo/startup_stereo：16物理键及4键、七音色、显示平均波形、音量0/100与松键、生产启动/关断。启动SD至audio_ready仍9979.141µs；所有PLL明确行为替代，非厂商PLL/STA验证。

源码完整依赖70项、两工作目录无配置include搜索路径预处理、默认顶层展开、未改动CST/SDC/PLL/协议/App/曲库源码核对通过。

复现：`python scripts/run_stereo_tests.py --out-dir reports/stereo_local`；可通过--iverilog/--vvp/--ivl-base指定本机Icarus。单项用--test numeric_stereo、tail_mono等，完整配置在脚本中。不运行Gowin。

旧分支三域STA未通过，本轮实际RAM/DSP推断、资源、时序、电气声道选择、模拟音质和手机/Flash实物仍待用户验证。文档接线见docs/bluetooth_score/双声道与复音修正.md；不要使用dist中的旧位流验证新功能。开发TB失败在development单独解释，不计入最终通过。
