# 最后一级数字PCM滤波（2026-11-01）

`audio_output_filter.sv`位于每侧`master_volume`之后、原子双声道`frame_buffer`之前。它处理实际送往I²S的PCM；波形/频谱使用的`visual_sample`也改为该末级PCM。它是数字滤波，不替代板级模拟测量。

## 接口和时序

- `clk/rst/in_valid/in_sample/in_tag/silence`输入，`out_valid/out_sample/out_tag`输出，无背压。
- 输入于上升沿N被接受，对应输出于N+4上升沿给出：5个寄存级、4个边沿间隔；61.44MHz时约65.1ns。历史只随有效样本推进，连续valid和任意valid间隙均支持。
- `TAG_W`默认17，标签与样本经过相同寄存级。左右独立实例，输入标签沿用原`volume_output_tag`；只有滤波后的`output_tag`进入pending/serial标签链与LAT。
- `rst`接`output_reset`，包括原urgent output clear。它取消所有滤波历史、在途valid和标签；不重置原主音量设定/渐变增益。
- `synth_core.OUTPUT_FILTER_ENABLE`默认0，保留独立组件旧调用的逐拍行为；生产顶层明确设1。
- 当FILTER=1、OUTPUT_ENABLE=0时，frame_buffer同样使用`output_reset`，防止直接输出测试模式在urgent clear后留下旧pending帧；FILTER=0时保留原复位选择。

## 算法和数值范围

采样率48kHz。内部使用带16位小数的有符号状态，各级加法具有明确扩展位。系数仅由移位与加减实现，没有变量乘法。

1. 去直流：极点`R=4095/4096`，归一化系数`alpha=8191/8192`。等价线性传递函数为`alpha*(1-z^-1)/(1-R*z^-1)`，拐点约1.865Hz，Nyquist处归一化为1。
2. 温和低通：`y[n]=(5*(x[n]+x[n-1])-2*y[n-1])/8`，极点为−1/4，DC增益为1、Nyquist为零，−3dB频率约15,742.998Hz。
3. 最后对称舍入到最近整数，恰好半LSB时向远离零方向舍入，再作16位饱和。不会发生补码环绕。滤波有瞬态超调，上游限幅阈值不能直接当作末级输出峰值保证；单位测试包含满幅DC翻转和交替极值。

实测正弦稳态频响（RTL逐拍匹配的整数参考模型，另与独立浮点线性模型核对）：

| 频率 | 增益dB |
| --- | ---: |
| 1Hz | −6.529 |
| 5Hz | −0.565 |
| A0，27.5Hz | −0.020 |
| 100Hz | −0.002 |
| 1kHz | −0.007 |
| C8，4186.009Hz | −0.122 |
| 8kHz | −0.492 |
| 12kHz | −1.336 |
| 15.743kHz | −3.010 |
| 20kHz | −7.792 |
| 23.5kHz | −25.275 |

低频和最高钢琴键基频保持接近原幅度，高频逐渐衰减；没有采用截止过低的普通滑动平均。不同音色在很高的谐波处会发生预期的滤波变化。

## 零输入收敛

反馈除法显式向零截断，DC估计停止变化时的余量小于1/16 PCM LSB；末级会输出数字0，不产生持续±1LSB量化音。

8组实际长静音测试均检查最后4096个输出**逐个等于0**：正/负满幅DC阶跃、±1LSB阶跃、正/负冲激、随机和稀疏valid之后的尾部，以及最终清零。另有保守递推边界：任意32位DC初态在最多56,302个有效零样本后进入死区，再最多11个零样本使低通状态进入最终舍入到0且保持的范围；还需计入4时钟输出流水。此为数值边界分析，不是形式验证或实板测量。报告为`output_filter_mute/zero_bound.json`。

正常去直流滤波存在低频恢复过程；这不通过强制音符超时实现，也不会截断合法长音。urgent clear直接复位滤波状态，无需等待自然收敛。

## 0音量的严格静音

生产FILTER=1专用计数器统计`effective_volume=0`期间的`volume_valid`，累计260个有效输出后置`filter_silence`，覆盖原主音量最多256采样的斜坡与寄存流水。非0音量或`output_reset`会清除计数；FILTER=0完全不增加这条行为。

`silence`按对应有效样本清除DC估计和AC历史，并随流水传到低通级清除反馈状态。相应输出为严格数字0，valid/tag仍正常流动，不将滤波rst持续拉高，因而不会造成frame_buffer缺帧或丢失LAT标签。已在I²S中的旧字按原协议完整结束，不截断半字。

恢复音量时解除silence，原主音量从0平滑升起，滤波从清零历史重新开始。新单元向滤波器输入非零PCM并随机开关silence，1820个显式静音样本及其tag全部按序输出0；核心夹具另外强制左右满幅正/负DC，经音量降0、保持、新NoteOn和恢复音量，检查原子frame/I²S、无欠载、标签不丢和重新发声。报告为`filter_core_mute/validation.json`。

## 验证入口与证据

```
python -X utf8 scripts/run_output_filter_tests.py --tool-bin <Icarus目录> --out-dir <独立输出目录>
python -X utf8 scripts/run_filter_core_tests.py --tool-bin <Icarus目录> --out-dir <独立输出目录> --suite bypass
python -X utf8 scripts/run_filter_core_tests.py --tool-bin <Icarus目录> --out-dir <独立输出目录> --suite enabled
python -X utf8 scripts/run_filter_core_tests.py --tool-bin <Icarus目录> --out-dir <独立输出目录> --suite mute
```

单元测试：`reports/integration_20261101/output_filter_mute/validation.json`，1,125,558个时钟检查、1,099,926个输出；逐拍PCM/valid/tag匹配，整数与浮点参考最多相差1 PCM LSB。含标签回绕、连续valid、随机间隙、带在途数据的复位和全幅输入。

旁路兼容：`reports/integration_20261101/filter_core_bypass_mute/validation.json`，OUTPUT_ENABLE=0/1各382,744拍，共765,488拍，默认FILTER=0与冻结旧完整音源的PCM、I²S、valid及声部控制逐拍一致。

FILTER=1的完整音源测试位于`filter_core_enabled_mute`：独立旁路音源驱动参考滤波器，独立frame/tag队列和外部引脚I²S接收器检查左右原子提交、最终波形来源、标签/LAT及urgent clear。生产立体声+限幅、立体声直接输出、单声道+限幅三种配置均为32声部，合计11,344,079项，分别记录源哈希和结果。静音专项在4声部立体声/1声部单声道配置加速运行，采样时钟与计数260保持原值，共30,887,261项；每配置均覆盖40个严格零输出、恢复后的16个非零输出及2003个外部I²S字。

以上为软件/RTL证据，未执行Gowin、STA或硬件烧录。最终资源与时序由整合后的生产工程验证。
