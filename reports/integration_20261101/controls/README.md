# 新控制功能独立测试

针对主线新写的timbre_control、ultrasonic_pitch、keyboard_sensitivity和performance_control进行组件/双时钟验证。测试代理未修改任何生产RTL；源及include哈希已经在每组执行前后和汇总时三次核对，四组共有输入版本一致。主线仍在整合，这些结果不是完整新main、Gowin STA或实板验收。

## 结果

- timbre：8014项。S0～S3任意变化无作用；旧auto_valid/version/target不控制主音量。第二旋钮上下只改音量，单/双击不改混响开关/强度；触屏音量可用。第一旋钮保留延音时间/强度，第三保留颤音深度/速度；完整百分比0～100独立有理数舍入对照，20～2000ms步进/BCD、音量/深度/速度边界、CFG背压稳定及主题/彩蛋/语言/视图动作。
- ultrasonic_pitch：3236项。5种灵敏度的20～450mm连续扫距、1000随机有效/无效样本；参考使用直接整数除法及独立三数中值排序，与被测串行除法实现不同。验证近73562、中65536、远58386，deadband、median3、不同距离范围、BCD999饱和、版本更新/回绕、关闭/无效配置、串行计算中取消、失效保持及超时回中。无音量输出接口，控制器测试也确认传感器旧目标不能改变音量。
- keyboard_sensitivity：1063项。audio10ns/ref14ns异步时钟；20位完整请求和16位结果通过生产CDC模块。GSR0～15/KOR1～255边界、三板132位配置且16通道KOR统一、独立ready/done延迟、busy期间禁止编辑、关闭页面后任务继续、板失败和两类超时不报成功；260连续任务随机完成延迟/错误，跨过8位epoch回绕，均无重放。
- performance_control：9979项，13对On/Off。旧屏幕滑音区域不改变pitch；只有sensor_pitch_ratio有效，逐采样最大32的平滑变化与独立状态参考逐拍一致；传感器失效回中。触屏箜篌/Chorus/Mix/Depth/Rate/Tone动作，离开页面不撤销已在途On，后续Off排空；12根弦全部完成起落。

合计22292项，均通过，详见summary.json。灵敏度板端是cfg握手行为模型，不是真实I2C或实板；超声波输入是距离/有效性报告，不是回波物理测量。

入口：python -X utf8 scripts/run_control_integration_tests.py --tool-bin <Icarus-bin> --out-dir <独立目录> [--suite timbre|ultra|sensitivity|performance|all]。

测试文件只在sim/integration/tb_controls_*.sv；脚本未启动EDA、未硬件烧录。主线后续若改动本次源或include，需要针对改动重新验证，不使用本报告冒充新版本结果。
