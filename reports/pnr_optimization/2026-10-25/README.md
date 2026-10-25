# 第二轮时序／布线优化（2026-10-25）

基线main b07c0d558cecfa3005b3b47eb08b2c6f7684af94。用户实板功能测试通过，但pnr(3).zip中的18:06报告Setup违例388、Hold0，Fmax ref/audio/pixel分别44.792/53.023/32.097MHz，要求50/61.44/35MHz。P&R总耗时1h8m51s，其中布线1h4m32s，BSRAM280/340。报告摘要和ZIP身份另存input_*文件；这不是本轮实现结果。

## 对应报告路径的修改

- pixel path23：扫描hpos→renderer/background_0，31.136ns、27级。注册输入坐标/消隐，背景与面板颜色比较移到已存在的第二级；renderer由8级变9级。字形、主题、矩形、波形与操作都不变。
- audio path24/25：timing/count→32路legacy/base，约18.8ns，其中frame使能组合级驱动约2615个负载。提前一拍预测并注册frame_ce，保持原脉冲拍位；HALF_CYCLES=1保留原首沿语义。ADSR和声音算法不改。
- ref：锁定计数器按低8位预测进位分段，终值提前一拍预测，计数器本域同步释放复位。没有改PLL、锁定等待周期或输出资格时刻；逐拍对比原实现覆盖1/255/256/257/100000阈值及低字节进位。
- I/O：前21条最差路径由pixel_reset经组合消隐门到LCD，另有PCLK输出路径。连接器改为真正一级输出寄存器，pixel_reset异步清零，停钟/丢锁立即消隐；与9级renderer合计10拍，DE/HS/VS/RGB同延迟。

## 无损减少存储

原猫/卡皮巴拉各存16张128×160×4bit图。16帧往返循环实际仅9张唯一帧，透明边界也可隐含为零。新物理存储为：

| 素材 | 唯一帧 | 有效矩形 | 4bit字数 | 位数 |
|---|---:|---|---:|---:|
| 猫 | 9 | x10,y38,102×95 | 87210 | 348840 |
| 卡皮巴拉 | 9 | x17,y17,96×139 | 120096 | 480384 |

逻辑显示仍为原16帧、10fps、128×160、原色彩/透明度/坐标，未降帧/降色或替换素材。全部主题和字库的逻辑位数3,747,584→1,955,368，省1,792,216位（约47.8%）。这是数据量，不是实际BSRAM块数、LUT或耗时估计。照片、英伦、字体、调色板字节不变。config/theme_storage.svh随同HEX生成并加入GPRJ，切勿混用旧RTL和新HEX。

## LCD约束更正及真实异步入口

旧set_max_delay 6ns从pixel_clk到所有LCD端口，包含了时钟插入延迟（本报告8.594ns），不能代表注释原意的纯6ns数据布线预算。现在在物理lcd_clk端口定义35MHz反相生成时钟lcd_pclk，以其真实采样沿对数据输出设置max8.286ns/min0ns；半周期14.286ns减setup预留8.286ns约为原意6ns预算。**这是工程余量，未冒充面板tSU/tH和板级走线验收**；新Gowin解析、对象匹配和I/O setup/hold必须复查。没有降低三个内部域的工作频率。

报告另有四条负Recovery只到两组复位同步器PRESET入口。仅以明确四个引脚名设置异步入口例外，不匹配整寄存器或整域；同步链D/Q、输出到业务寄存器的复位路径和所有业务数据路径仍检查。reset_sync原结构、属性和两拍同步释放保持。需确认新网表四对象全部匹配、无额外命中。此为真实同步器入口约束，不是忽略正常数据违例。没有clock_groups全域切断或多周期例外。

语法依据高云官方SUG940 5.2.2、5.3、5.4.1、5.5，复位结构依据AMD UG906：

- https://cdn.gowinsemi.com.cn/SUG940E.pdf
- https://docs.amd.com/r/en-US/ug906-vivado-design-analysis/Asynchronous-Reset-Synchronizer

SDC追加三个域各10条域内最差路径，避免I/O占满全局前25条后看不到内部瓶颈。sdc_review.json只做源码/结构检查，不是厂商SDC解析。未安装tclsh，因此没有宣称独立Tcl或Gowin语法实测。

## 验证与复现

validation.json为汇总。包含时钟/计数逐拍等价、全655360个动画逻辑像素与旧ROM比对、八个800×480页面SHA逐一比对、完整曲谱样本级参考、三次USR重启/键盘释放及完整连接器输出/丢锁消隐。PLL集成测试明确使用行为模型，不是STA或官方PLL验证；较短曲谱节拍/启动/包络用于可行测试，生产32声部/I2S节拍保留。

使用现有scripts/run_sim.py运行各TB；tb_animation_storage需要从b07c0d5下载原theme_cat.hex/theme_capybara.hex到独立参考目录，使用--animation-reference-dir传入，该TB不参与无参数默认批量。旧ROM不复制为第二套生产工程。原文件Git blob SHA在reference_roms.json中。src/config头文件引用通过两个工作目录、无额外配置-I搜索路径的预处理检查。

开发中两次编译错误（文字拼接漏空格、测试参考模型include路径）保存在development，最终均修正；不修改历史报告或原始上传ZIP。

## 用户验收顺序

1. 关闭旧IDE，完整新包解压到新目录，重开keyboard_adsr.gprj；不覆盖拼接旧工程。
2. 用户运行Gowin综合/P&R，记录本次耗时。检查新SDC全部命令Active、lcd_pclk确在输出端且为35MHz反相、四同步器入口对象匹配、无未匹配/新增异常警告。
3. 检查三个域Fmax、Setup/Hold、Recovery/Removal、LCD输出setup/hold、资源及clk_d原警告；发回新pnr报告。若仍不满足，依据各域新关键路径继续修正。
4. 助手确认报告后，用户进行相同功能、复位和音质验收。

助手未运行Gowin/P&R/STA/下载，不保证布线缩短多少分钟或本轮一定收敛。超声波、蓝牙分支未合并/修改。
