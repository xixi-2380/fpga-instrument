# U7 Flash：能识别、RAM成功但保存失败的检查（2026-10-27）

当前工程：`E:\gowin\fpga-instrument-integrated`。用户确认故障发生在手机 App 的 RAM 下载/校验完成之后，保存到 U7 Flash 阶段；实板 Flash ID 和错误码暂未提供。本次未连接或擦写实板，没有运行 Gowin 综合/P&R/STA/Programmer，也没有提交推送。

## 检查结论与修正

正常 SPI 页编程/擦除、4096 条满容量曲谱、32 首目录、掉电恢复及 CRC 拒绝路径仿真通过。它们不能排除真实器件保护状态、信号或旧位流的问题。

已复现一个确定的源码问题：在 ID=EF4018、SR1=00、SR2=3B、SR3=60 时，芯片主数据区未开启块保护，但旧驱动返回错误 21。来源是将状态寄存器锁定位 SRP/SRL 以及仅决定保护区域形状的 SEC/TB 一并拒绝。上层 App 能力判断和 WREN 后检查也有相同问题。

依据 [Winbond 官方说明](https://winbond.com/hq/support/online-learning/articles-item/safeguarding-boot-code-and-other-critical-data.html?__locale=en)及 [W25Q128JV Rev D 数据手册](https://datasheet.lcsc.com/datasheet/pdf/cf3e7cd7501b4484ab05b628ac6261a9.pdf?productCode=C111478)第 12～17 页，现将主数据区权限判断集中在 `src/config/flash_profile.svh`，由 `spi_nor_flash` 和 `score_services` 共同使用。允许 BP=000、CMP=0、WPS=0 且非 BUSY/SUS 的已支持芯片写入；SRP/SRL、SEC/TB 不再造成误拒绝。WEL 仍必须实际置位，真正的数据区保护、独立块保护、未知 ID、越界及禁写配置仍会拒绝。

没有修改任何保护寄存器，没有发送解锁或整片擦除命令。Flash 型号白名单仍仅 EF4018，曲库地址范围仍为 000000～21FFFF，引脚和 1MHz SPI 不变。并未确认实板正是上述状态，此修正不等于已经找出实板的唯一故障原因。

## 现在如何获取实板结果

新安装包：`android/dist/GaoshanScore-0.3.1-flashdiag.apk`。versionCode=4，与现有 0.3 APK 使用相同开发签名，签名和清单已验证。未进行手机安装或蓝牙实测。

1. 安装新 APK，连接原蓝牙模块，完成“验证 FPGA 通信”。
2. 点击“读取Flash诊断”。此按钮只查询，不启动擦写。
3. 点击“复制诊断记录”，发送复制的文字。会包含 ID、SR1/SR2/SR3、INIT、WRITE、JOB、ERROR、RAM CRC。
4. 若需复现，用“三音符示例”下载，并保留出现问题后的诊断记录；已有任务结果未知时先查询未完成任务，不重复启动保存。

FPGA 权限修复必须由本工程重新综合、布局布线并下载后才会生效。新 App 可以先连接旧固件读取状态；它不会替旧固件开放写入。

App 同时修正了错误表达：Flash 阶段失败时保留“RAM下载与校验已完成”的事实，明确显示 Flash 保存未确认，不再笼统显示上传未完成；Flash 任务错误保留十六进制代码，09 明确为曲谱或目录的读回校验失败。

| 结果 | 解释 |
| --- | --- |
| ID 非 EF4018 | 当前写入配置不支持该型号，需按实际 ID 和芯片资料增加对应配置 |
| INIT=0 | 曲库尚未初始化，先检查器件响应与启动扫描 |
| BP/CMP 数据保护位非零 | 需要核对实际保护配置，本轮不会自动清保护 |
| WPS=1 | 使用独立块保护模式，当前实现不开放写入 |
| 数据保护位为空但 WRITE=0 | 检查是否仍使用旧权限判断或禁写配置 |
| 错误 21 | 型号/禁写/保护或写使能检查拒绝，结合状态值判断 |
| 错误 22 | 擦写忙等待超时 |
| 错误 09 | 曲谱或目录读回 CRC/提交标记验证失败 |
| 错误 28 | 任务指纹失效或结果被替代，应核对目录和曲谱 CRC |

## 验证

证据目录：`reports/flash_link_2026-10-27`。

- `repro_register_lock`：修改前稳定复现错误 21，保留失败日志。
- `fixed_permissions` 和 `permissions_1mhz`：8 组非数据保护标志允许擦写读回；真实 BP/CMP/WPS/SUS 保护仍拒绝，未发出状态写入/解锁/整片擦除，分别 60 项检查。
- `driver_regression`：SPI 线级页读写、边界、禁写、未知型号、忙超时共 275 项检查通过。
- `baseline_library`：4096 条满容量、32 首及替换、掉电打断、CRC 损坏共 90 项检查通过。曲库模块本身没有修改，复用本轮同源码的通过证据。
- `phone_register_locks`：带 SR1=E0、SR2=3B、SR3=60 的实际协议核心→曲库服务→SPI 芯片模型→重启载入→本地播放/删除，336 项检查通过。
- `protocol`：原曲库协议 19 项检查通过，协议载荷布局不变。
- Java 核心/连接/曲库共 36,114 项检查通过；生产顶层使用官方仿真库语法检查通过；APK 编译、签名、版本、与 0.3 证书一致性通过。

单项复测：`python scripts/run_sim.py --test tb_flash_write_permissions --param HALF=25 --out-dir reports/自选目录`。手机链路仿真：`python scripts/run_sim.py --test tb_bt_library_link --param REGISTER_LOCKS=1 --behavioral-pll --out-dir reports/自选目录`。行为 PLL、协议模拟和签名验证均不代表实板保存成功或新的 STA 已通过。
