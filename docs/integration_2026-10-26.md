# 两工程合并说明

用户要求将两个工程合并到E:\gowin下的新工程，并允许读取GitHub辅助判断。目标为 `E:\gowin\fpga-instrument-integrated`，分支 `codex/integrated-instrument`。保留两个原目录及来源分支。用户2026-10-27随后明确授权提交并推送本合并分支，不更新main。

## 来源与选择依据

- 共同提交：[8081710](https://github.com/xixi-2380/fpga-instrument/commit/8081710e107f4d32069c6f1321eefed4c422970e)，已获用户旧版通信/单声部播放定性确认。
- score检查点：[2d86834](https://github.com/xixi-2380/fpga-instrument/commit/2d86834)，16自动声部、4096条、32首曲库及App0.3。实际输入还包含本地2026-10-26的尾音/力度/Flash修正和时序优化，不只取Git提交。
- audio检查点：[a138116](https://github.com/xixi-2380/fpga-instrument/commit/a1381169c85b772aaec1f3586abf43b5404cd3ac)，24倍补偿、前瞻限幅及LAT。实际输入还包含本地时序改进和超声波控音量。
- GitHub `feature/ultrasonic-volume` 是另一条与a138116分叉的分支，还有主题/字体改动。本任务指定两个本地工程，不从第三分支引入主题改版。

score本地记录显示其2026-10-26单独工程完成综合/P&R，目标50/61.44/35MHz下Setup/Hold为0/0；LCD转发时钟仍有明确的工程估算条件。这使它适合作为时序结构基础，不能据此声称新增限幅和超声波后的合并版时序通过。audio的限幅/LAT及超声波有独立模型与联合仿真，尚无本地新版本实现报告或实板确认。

## 冲突处理

三方比较以8081710为公共基线，score当前源码为主体，逐项接入audio差异。输入哈希和初次合并列表保存于报告目录。

1. 保留score的16自动身份、32物理声部、独立尾音频率和力度，不回退audio单自动声部桥。限幅接在原效果器之后、总音量和I²S之前；LAT标签随同一PCM链路传递。
2. 普通On/Off不清全局音源或限幅队列。自然结束使用内部kind3，冻结曲谱时间，先排空限幅延迟再清零、交回手动；STOP/PAUSE/上传接管立即清零。无线协议帧不变。
3. 保留score的ADSR PRECALC、上下文选择/乘法拆拍、四级显示加连接器寄存器、复位同步、分段计数及MOSI=R21修正。全部ROM及50/61.44/35MHz时钟不变。
4. 主显示快照由1112扩至1167位，低1112位不挪动，追加21位LAT及34位超声波。146位曲库/身份信息继续独立原子快照。
5. 曲库动作21..32保留，超声波改33..41。设置页触摸入口x340..539为ULTRASONIC、550..653为more，y420..463。矩阵R1C4=超声波、R4C4=more；两子页返回主设置页，长按S0回演奏。超声波默认OFF。
6. 移除BT EN：P21=Trig、U17=Echo，RX/TX=P24/P23；Flash、MAX、屏幕、触摸、键盘引脚保持score分配。GPRJ、引脚核对脚本、IDE IncludePath一同更新。

## 打开与验收

关闭旧IDE工程，打开新目录keyboard_adsr.gprj，源码全部在本目录src。新目录没有本轮生成的.fs；先自行综合/P&R并核对所有域及IO报告，再下载实板验证。旧dist内文件仅历史归档。

本轮仅运行纯HDL、软件模型、App核心测试与静态检查。结果汇总见 `../reports/integration_2026-10-26/validation.json`；日志在同目录tests下。仿真不等于Flash硬件识别、超声波电平、音质、面板时序或长稳通过。

重跑入口为 `python scripts/run_integration_tests.py --jobs 3`，也可用 `--only tb_bt_identity` 选择单项。身份专项的29条原始测试记录已从来源报告搬到 `sim/data/bt_identity_notes.hex`，来源分组见同目录bt_identity_input.json，不再依赖被省略的历史报告文件。安卓核心测试入口为 `python android/run_core_tests.py --out-dir reports/自选目录`，需要可用JDK；本机本轮使用现有JDK8运行纯Java核心，未重建或签名APK。

实板重点：静音待机和手动演奏；手机16声部下载/播放/暂停/继续/停止；短音和同ID尾音；响度与LAT；超声波开关/无回波回落；more曲库及U7原始JEDEC。未知Flash仍遵循原白名单只读/拒写，不自动清保护或整片擦除。
