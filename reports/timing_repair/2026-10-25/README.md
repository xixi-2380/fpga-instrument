# FX开关及首轮时序结构修正（2026-10-25）

基线main：14a693ce48a1d60197f4423cf306e8bd43b8adfc。用户确认雨姐静态图正常，但同一.fs在重复下载/USR后出现不同程度的缺音、电音、持续音。

## 输入证据

原始pnr.zip是用户12:20生成的旧实现，不是本轮实现结果。身份/SHA256和数值见input_report_identity.json；时序、P&R摘要及原警告见两个input_*_excerpt.txt。保留用户原文件，不重新运行EDA、不覆盖历史报告。报告要求50/61.44/35MHz，但Fmax43.874/33.308/13.645MHz，Setup3882、Hold0。最差像素路径从扫描y到字库地址，约73.416ns；全局前25条Setup路径均为像素域，**不足以单凭这份前25条给音频域或ref域认定具体最差组合路径**。

## 实际改动

- FX类型选择保持全局旁路状态；显式FX触屏/矩阵按钮、S3短按以及恢复默认仍控制开关。
- 显示从2级改8级流水，将布局、坐标、格号、字符、ROM地址、ROM读取、背景、文字混色分级。删除逐像素32位常数除法式音符卡片/测试条索引；正文格号除法限定12位，颜色混合限定10位；数值排版缓存到独立寄存器。字库仍为无复位的同步ROM读，避免妨碍块RAM推断。
- 所有像素的RGB/DE/HS/VS和主题背景同延迟；四主题、图片/动画ROM、字库、字体、触摸区域和35MHz扫描参数保持。与基线八个800×480完整页面逐像素比较。
- audio_visualizer将1024位动态写片选改成128个常数8位片选。synth_core只把持音监视器的声部读/位图译码拆成两拍，不更改发声处理的517周期交付、音符握手或PCM算法。
- 1112位显示和71位触摸快照的各域寄存器改用本域reset_sync输出；异步立即断言、各时钟域同步释放，四相握手和数据原子性保留。

## 验证边界与复现

见validation.json、pixel_equivalence.json及各tb_*_result.json。PLL集成测试使用sim中的明确行为替代模型，不是官方PLL或带布线延迟仿真。tb_audio_restart保留32声部与生产I2S节拍，但缩短启动、包络和曲谱节拍，重复三次完整谱/键盘释放检查；不是实物复位验收。全谱tb_score_audio另有样本级参考检查。

现有scripts/run_sim.py可运行独立测试，例如：

```
python scripts/run_sim.py --test tb_theme_controls --out-dir reports/sim/fx
python scripts/run_sim.py --test tb_audio_restart --behavioral-pll --out-dir reports/sim/restart
python scripts/run_sim.py --test tb_rgb_status_cdc --param WIDTH=1112 --out-dir reports/sim/cdc
python scripts/run_sim.py --test tb_theme_pixels --out-dir reports/sim/theme
```

保留脚本原Windows Icarus位置约定；该脚本是纯HDL验证，不运行Gowin。baseline/仅记录原14a693c画面回归日志，逐像素对比的各图SHA及差异数另存JSON；中间PPM、VVP与预处理展开文件不提交。

## 用户下一步

关闭旧Gowin工程，在新解压目录打开keyboard_adsr.gprj，清理旧实现缓存后由用户重新综合/P&R。**先上传新pnr报告**，确认所有时钟要求和Setup/Hold、Recovery/Removal及clk_d通用布线警告；如仍失败，继续根据新域内关键路径修正。不得把Fmax估算值当成实际工作频率，也不得在失败时仅放宽时钟约束/加虚假路径或反复下载碰运气。

此提交不包含新STA、BRAM占用、布线耗时或实板音质结论，不宣称持续音/噪声已修复。保留七音色、32声部、三效果、小星星、静态雨姐及另两动画主题；不合并蓝牙、不添加语言/音量/超声波，不修改CST/SDC/PLL或矩阵扫描。
