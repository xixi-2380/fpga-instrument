# Main 完整布局布线与物理验收

运行器为 `scripts/run_main_physical.py`，使用 Python 3.10 以上版本和标准库。不会烧录硬件。正常运行没有执行时限；启动后需要让其完成。运行目录名称必须是新名称，避免覆盖证据。

从项目根执行：

```powershell
python -X utf8 scripts/run_main_physical.py --name main_default_01
```

项目根默认为脚本所在项目，也可通过 `--root` 指定。`--manifest` 是相对于项目根的路径，默认为 `reports/integration_20261101/synthesis_initial/netlist_manifest.json`。必要时用 `--tool` 指定 `gw_sh.exe`，默认使用本机 Gowin V1.9.12.04。运行器调用原有 `scripts/build_keyboard.tcl pnr`，默认 Place 3 / Route 2 / fanout 23，不改该脚本或工程设置，也不扩大时钟预算。

输出位于 `reports/integration_20261101/physical/<name>`。`start.json` 记录 UTC、PID、命令、配置和启动网表哈希；连续输出为 `tool.log`。运行前核对综合 manifest 的 `source_files` 与 `netlist_sha256`，要求 manifest 覆盖全部 `src/**/*.sv`、`*.svh`、`*.hex` 和项目根所有 GPRJ。CST、SDC、build Tcl 与两个验收脚本另记哈希，并存档输入。运行结束和验收完成后再次核对内容及文件集合，新增、删除或变更源码均不能通过。

只清理 `impl/pnr` 本层、输出基名为 `D2_keyboard_leds` 的已知报告/位流文件；先复制到本次报告的 `preexisting`，校验哈希后才删除原文件。不会递归删除目录、改动综合目录或清理数据库。结果归档包括 FS、TR、RPT、SDF、PIN、LOG，以及工具生成的其他已知报告，逐项保留原始 mtime、大小和 SHA256。必需产物必须非空，生成时间不得早于本次启动。每次运行仍需独占工程的 EDA 输出目录；不要对同一工程同时启动第二个综合/PNR。

高云可能在 `pnr` 命令中自动重综合。运行器在日志出现 `Reading netlist file` 和 `Running placement` 后，于进程仍运行时抓取实际 VG、综合报告、综合日志和工程中间文件。`observed_netlist_manifest.json` 分开记录启动 VG 和实际 VG 的哈希；VG 单独改变不被称为源码变化，但实际 VG 必须与存档及最终当前 VG 吻合，源码与约束必须全程保持一致。进程结束前未抓到实际输入证据时不能通过。工具退出失败或验收异常也会写 `result.json`。

`qualified_bitstream=true` 同时要求：

- 工具退出码 0，日志没有 ERROR/FATAL，最终 routing、PNR、bitstream generation、100% power analysis 完成；若报告明确给出 unrouted nets，其值必须全为 0。此高云版本成功时可能不打印零未布通行，此时记录其完整布线完成标志作为证据。
- FS 头为 `SecurityBit: OFF`，必需产物齐全、时间有效、存档哈希一致，实际综合网表与来源一致。
- 从真实 RPT 的 Pinout by Port Name 表读取恰好 69 个端口、69 个唯一球位，每个球位与冻结 CST 逐项相符且 Constraint 为 Y；I/O usage 必须为 69。S0–S3、旧 key[]、DBG、matrix/row/col 接口不能出现。
- 复用 `inspect_timing.py`，要求 Setup/Hold endpoint 均为 0，TNS 均为 0 且覆盖三个主时钟，Setup/Hold 表非空，所有路径表及详细 Slack 非负，pulse-width 表非空且所有余量非负。ref/audio/pixel 的内部 setup 最小余量分别至少 0.5 ns，目标仍为 50 / 61.44 / 35 MHz。
- 复用 `check_lcd_clock_timing.py`，LCD 独立慢/快时钟模型和物理 SDF 检查通过。

`hardware_programmed` 始终为 false。通过以上检查属于物理报告及位流验收，不代表实板功能已经测量。

已有产物只读复验：

```powershell
python -X utf8 scripts/run_main_physical.py --name main_initial_review --verify-dir reports/closure_2026-11-01/main_initial
```

`--verify-dir` 支持项目相对或绝对目录。不会启动 EDA、不会修改已有报告目录，新的 review 和 `result.json` 写入上述 physical 目录。支持本运行器，以及旧 `run_closure.py` + `observe_netlist.py` 的报告格式。旧观察时间必须落在原 start/finished UTC 之间，原标签必须为 `during physical run`，来源 manifest 与实际 netlist 路径必须匹配，VG 哈希仍用原 observer 记录；综合报告哈希若是在复验时才计算会明确注明。旧运行器使用 copyfile 丢失原 mtime 时，仅允许从哈希完全一致的当前 `impl/pnr` 文件恢复真实 mtime；没有对应文件就保守判为时效证据不足。不会把存档复制时间当作原 EDA 生成时间。旧 73 管脚产物仍会失败，不降低 69 管脚和时序断言。

退出码为 0 表示所有物理验收通过；1 表示失败、证据不足或异常。具体原因见 `failed_checks`、`exception` 和完整 `result.json`。
