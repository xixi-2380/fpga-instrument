# 当前进度（2026-11-02恢复）
用户实板main7d84ac3完整保留，不混入已暂停新组合优化。main未更新。
- 基线：F:/FPGA_Projects/main-board-tested-7d84ac3-20261101；GitHub baseline/main-board-tested-20261101。
- 本工作区：F:/FPGA_Projects/fpga-instrument-main-adjustments-20261101；远端codex/main-adjustments-20261101目前仍指向基线，待验证后推送。
- W25：新增key_input_probe模块、顶层36有效物理键输入连接、GPRJ/CST/SDC。50MHz下1ms可重触发脉冲，测量起点为扫描确认后，不包含前端扫描。单元200240检查通过；真实I2C/top740项已通过。
- 超声波：已确认旧mm数字+CM标签10倍bug。range/pitch/顶层改distance_cm；响应改回中半宽1..5cm。4472映射、8046控制、74回波/显示检查通过，字体重生成一致，生产源冻结。
- XY：display_merge独立7467237检查通过，未复现bug，生产RTL保持基线。报告xy/README.md。
- MIDI：release_bug改纯Android导入，GM35..81映射现有10鼓/保持既有22键，可选52+41模拟锣默认关。修one-shot无NoteOff导入。生产RTL/协议不改，Java/FPGA行为联合回归468711项通过，APK 0.5/versionCode8构建签名验证完成；签名与旧0.4不同，未手机安装或蓝牙实测。APK位于android/dist，另存F:/FPGA_Projects。
- 官方原语编译及综合完成，LUT65163/寄存器35653，综合输入126文件哈希一致。显示15页1796755项通过。完整PNR尚未开始（电池未接电且续航不足以安全完成一小时运行），原时钟50/61.44/35MHz不放宽。基线PNR54m11，87setup/0hold（用户实板通过不等于STA全过）。
- run_main_physical.py仅本新工程适配70 pins并检查W25，严格时序检查保留，报告存adjustments目录。
- 不自动烧录。额度中断续做本目录，勿覆盖原fs。

## 续做命令
接电后在本工程运行：
```
python -X utf8 scripts/run_power_guard.py -- python -X utf8 scripts/run_main_physical.py --name adjustments_powered_20261102
```
守护每30秒检查电量，未接电<=25%停止自身进程树并落盘状态，不代表已完成布线。PNR报告位于reports/adjustments_20261101/physical，比较基线54m11、87setup/0hold，不擅自放宽约束。main继续保留7d84ac3，未生成新fs前用户仍使用原实板fs。
