# Tang Mega 138K Pro：矩阵键盘与 PT8211 音频工程

当前工作根目录：`E:\gowin\fpga-instrument`。主工程为 `keyboard_adsr.gprj`，顶层 `keyboard_top`，输出基名 `D2_keyboard_leds`。设备 Device Version C；实际速度等级仍待核验。

当前仅实现矩阵键盘、单声部正弦、ADSR、四颗运行流水灯和两颗状态灯。D1 固定 440 Hz 已由用户反馈正常发声；D2 键盘版无声尚未定位，最新流水灯版等待用户编译烧录及反馈。配置中的 VOICE_COUNT=32 是后续目标，不代表已实现复音。

## 当前工作流程

- 先读 `AGENTS.md`，设计接口和定点约定见 `docs/interfaces.md`，模块索引见 `docs/modules.md`。
- 用户负责综合、布局布线与烧录；助手仅修改文件、运行纯 HDL 仿真和读取报告。
- 用户打开本目录的 `keyboard_adsr.gprj`，确认顶层和输出名；预期新输出为 `impl/pnr/D2_keyboard_leds.fs`。迁移没有生成该文件。
- 按 `docs/bringup_run_leds.md` 先观察 LED0～3 循环、LED4 就绪、单按 A4 时 LED5 门控，再定位无声；当前不扩展复杂功能。
- 在现有对应文件上修改，不通过复制另一个版本文件或目录维护同一模块；用户明确提示后再提交 Git，不自动提交或推送。

## 目录职责

| 路径 | 内容 |
|---|---|
| `rtl/` | 可综合功能模块 |
| `boards/mega138k_pro/` | 板级顶层、时钟复位、CST/SDC 和硬件状态 |
| `config/`、`rom/` | 统一参数、音符表和正弦 ROM |
| `sim/` | HDL 测试平台与无源键盘模型 |
| `scripts/` | 仿真及用户可用的构建脚本；助手不执行构建或下载 |
| `impl/*_process_config.json` | Gowin 工程配置，Git 纳入管理；其余实现输出不纳入 Git |
| `docs/` | 操作步骤、设计接口、变更记录与历史交接 |
| `references/`、`reports/hardware/photos/` | 原始资料与照片，只读保存 |
| `reports/` | 历史证据与后续验证结果，迁移验证位于 `reports/migration/` |
| `tools/` | 本机 Icarus 环境，保留但不纳入 Git；`tools/manifest.json` 记录来源 |
| `bringup/` | 手动操作说明及历史下载产物；旧 `.fs` 不代表当前源码 |
| `fpga-instrument/` | 迁移前已存在的嵌套旧参考工程，未修改，不作为当前入口且不纳入本仓库 |

## HDL 仿真

在本工程根目录执行，仿真不会启动综合或访问开发板：

```powershell
& 'D:\py\python.exe' scripts/run_sim.py --test tb_run_leds --out-dir reports/sim/current
& 'D:\py\python.exe' scripts/run_sim.py --test tb_keyboard_top --vendor --out-dir reports/sim/current
& 'D:\py\python.exe' scripts/run_keyboard_pinmap.py --out-dir reports/keyboard/pinmap_current
```

`--out-dir` 相对工程根目录解析，可使用新的目录保存每次验证，避免覆盖原始日志。迁移后验证日志保存在 `reports/migration/sim/` 和 `reports/migration/pinmap/`。

## 备用工程与历史证据

主入口始终为 `keyboard_adsr.gprj`。`tone_play_stereo.gprj`、`tone_play_left.gprj`、`tone_play_right.gprj` 保留 D1 固定音验证；`bringup_digital.gprj` 为 D0 静音数字诊断；`tone_feasibility.gprj` 为历史可行性工程，其自动 IO 产物禁止下载。

原工程 `E:\gowin\fpga-instrument-mega138k-pro` 保留为迁移来源，不删除、不继续同步修改。旧日志、原始交接及哈希记录按原字节保留，可能含原路径和旧输出名；它们仅证明对应历史版本。旧 `.gprj.user` 实现状态缓存和大批中间文件未迁入。

迁移内容、哈希与验证范围见 `reports/migration/manifest.json`、`reports/migration/validation.json` 和 `docs/change_log.md`。仿真通过不能替代当前源码的实现时序与实板验收。
