## 当前界面操作

当前四主题版本：S0短按松开选正弦、长按0.8秒切页面；S1上一主题，S2下一主题；S3短按开关效果、长按0.8秒进入/退出隐藏彩蛋。音色/效果类型通过触屏或矩阵菜单选择。详见[themes.md](themes.md)。下方历史操作已由本段及硬件映射表更新。

# 板载独立按钮控制

2026-10-22效果器工作分支更新S3短按/长按操作，详见[效果器](effects.md)。以下原独立按键硬件映射保持。

2026-10-21起，使用Tang Mega 138K Pro Dock底板的四个用户按键，替代4×4矩阵键盘的对角组合手势。矩阵键盘只负责演奏，旧左上＋右下、右上＋左下组合均不再切换设置；仍受无二极管矩阵自身鬼键限制。

| 底板按钮 | FPGA引脚 | 当前功能 |
|---|---|---|
| S0 | K16 | 短按正弦；长按切页面 |
| S1 | F15 | 上一常规主题 |
| S2 | G15 | 下一常规主题 |
| S3 | G16 | 短按松开开关效果；长按约0.8秒进入/退出隐藏彩蛋 |

按板上S0～S3丝印识别，不要按其他例程中的key数组下标猜位置。官方通用CST的key[1]、key[2]恰与物理S1/S2顺序相反；本工程board_buttons_n[0..3]明确跟随S0..S3。核心板USR（U4）仍是系统复位，不是上述四键之一；RECONFIG、下载器/BOOT按钮也不在此映射内。

## 电气依据

已核对[官方Dock 4071f3原理图](https://dl.sipeed.com/fileList/TANG/Mega_138K_Pro/02_Schematic/TANG_MEGA-138K_Dock-4071f3__Schematics.pdf)第15/19页PERIPHERALS：S0/S1/S2/S3各通过1.5kΩ接3.3V，开关按下接地，网络USR_KEY.0/.1/.2/.3分别为K16/F15/G15/G16。文档证据SHA256及引脚检查见reports/board_buttons/2026-10-21/pin_check.json。原始references不修改。

新端口为board_buttons_n[3:0]，输入LVCMOS33、PULL_MODE=UP、DRIVE=OFF；现有矩阵、DAC、调试镜像、LED与USR引脚均不变。无需额外接线或新增硬件；电气文档核对不是对实物版本/电压的测量。

## 操作与边界

- 上电和USR复位：正弦、回声关闭；《小星星》仍播放一次后交给键盘。
- 四键独立于矩阵扫描。两级同步后，每个按钮独立连续稳定614400个audio_clk周期才接受状态，即61.44MHz下约10ms；按下和松开均消抖，长按只触发一次；S3轻按在稳定松开时开关效果，长按切类型并开启，长按后的松开不再开关。
- 切换音色不发音；当前按住/释放中的声部保持原音色，之后的新起音/重触发使用所选音色。
- 自动演奏期间S3也可开关回声；S0～S2设置随后手动演奏的预设，不改曲谱事件自身指定的音色。默认曲谱仍是正弦单旋律。
- 同时被确认的多个音色按钮按S0、S1、S2优先；S3独立处理，可与音色按钮同时使用。先后按下时，以之后确认的单次事件为准。
- 软件复位后一直按住的按钮在稳定约10ms后视作一次按下；松开状态不会产生事件。

## 验证与上板

原timbre_control原位改为独立按键同步/消抖/事件控制，无新增硬件工程或重复模块；synth_core、曲谱、音源及效果算法不改。BUTTON_DEBOUNCE_CYCLES为顶层参数，仿真可缩短，实际使用默认614400。

验证入口：

```powershell
python scripts/run_sim.py --test tb_timbre_control --out-dir reports/local_buttons
python scripts/run_sim.py --test tb_score_effects --behavioral-pll --out-dir reports/local_button_audio
python scripts/run_sim.py --test tb_keyboard_top --behavioral-pll --out-dir reports/local_button_keyboard
```

后两项明确用sim/pll_pair_behavioral.sv替代官方时钟包装，仅验证逻辑与音频参考，不能证明官方PLL、物理时序或电气已通过。用户在有官方Gowin仿真库时可去掉--behavioral-pll。证据见reports/board_buttons/2026-10-21/validation.json。

获取最新main后关闭并重新打开原keyboard_adsr.gprj，由用户重新综合/P&R，核对四个新增输入引脚、61.44MHz、Setup/Hold与资源，再SRAM下载。先等自动曲谱结束，用同一矩阵键依次比较S0/S1/S2，再按S3比较短促节奏的回声；按钮本身不应触发音符，原两个对角组合不应改变设置。助手未启动EDA或烧录。
