# 鼓／锣调整验证

全部 **468711 项检查通过**：Java 原有核心 36259 项、专用打击乐 259 项、原 FPGA 验证器/播放器兼容 163 项、原 10 种鼓 DDS/包络 432030 项。生成的6条示例记录通过CRC32 `488E9EB5`，产生6个On、6个Off、开始清音及自然结束清音。正式结果、编译命令、源哈希和实板基线对照在 `validation.json`、`tested_source_hashes.json`。

本功能仅改 App 导入/界面和软件示例，**没有改 FPGA 生产代码**。验证中10个相关生产文件（DDS、包络、鼓记录规则、验证器、播放器、蓝牙core/bridge、声部分配及两时钟配置）逐一与实板main `7d84ac3` 完整保留副本核对，SHA-256一致；这不代表其他代理负责的键盘/超声波/XY任务没有改动其文件。本任务没有启动EDA、安装APK或烧录硬件。

## 最终行为

第10通道GM1键35～81共47键，手机端规范化到原先22个可达键／10个鼓ID16～25。原22键的输出记录逐字节保留，旧8字节记录与26音色能力握手不变。其他键明确显示近似警告，不宣称47个独立采样或完整GM1合规音源。标准范围以外的鼓起音仍报错。

鼓按现有一次性固定包络处理，不再因短Off或缺Off丢掉有效鼓轨；旋律缺失/孤立Off仍报错。可选52中国镲+41低鼓模拟锣，每击占2自动声部，默认关闭；8击同时用满16声部，9击经真实转换记录统计后被拒绝。统一旋律音色、移调、轨道/通道筛选、排鼓、CC7静音和同键重击均有定向用例。

GM1表中52为Chinese Cymbal，没有专用Gong键。已实际读取 [MIDI Association规范入口](https://midi.org/general-midi-level-1) 所链接的 [官方PDF](https://drive.google.com/file/d/1TTM2HI2JAp_XiTJYEJ8gPNvuJpIjJiTP/view)，Table3第6页；PDF SHA-256为 `ba09e13069ce3ad79989c3abc1d70c8f1e8ce3e3dd1097d9c241d6665e152bac`。官方文件与抽取文本仅留在忽略目录 `android/build-local/reference`，不随本报告复制发布。详细映射和使用说明见 `docs/bluetooth_score/GM鼓与锣声近似.md`。

## APK与复现

最终APK：`android/dist/GaoshanScore-0.5-percussion-20261102.apk`，57747字节，SHA-256 `14bab9b7701fe0feeb641fc54edbfbcdd6ea00a04e1380ef6b3b62e870ab3332`。包名 `cn.whu.gaoshan`，versionCode8、minSDK26、targetSDK35；编译/D8/aapt2/zipalign/v2-v3验签均完成，manifest证据在本目录。此哈希的诊断复制文字也已更新为0.5，不使用之前的中间包。

旧开发私钥未找到，本版生成了新的本地开发签名。证书SHA-256 `c65b9883def227f038066e07071a1dc0f3ae6d902f2f6ba5cfd6f429da5fbeb7`，与旧0.4的 `b63e5608b4331ebae578a47d8036bbc2e81a39844eea2e8937d73bbccf6a1379` 不同，因此不能直接覆盖安装旧版；证书对照在 `apk_verify.log` / `prior_apk_certificate.txt`。没有卸载或清理用户数据。若原私钥找回，可通过新增 `--keystore` 参数重新签兼容升级包。密钥文件只在本地忽略目录，不上传。

使用已有 `D:/PyCharm 2025.2.4/jbr/bin` JDK；必要SDK仅下载官方Platform35和Build-tools35.0.0，已核对repository官方SHA1，并额外记录SHA256在 `sdk_download_manifest.json`。SDK/JDK/缓存/密钥不作为源码发布。

```powershell
$env:PATH='D:/PyCharm 2025.2.4/jbr/bin;'+$env:PATH
python -X utf8 scripts/run_power_guard.py -- python -X utf8 scripts/run_percussion_adjustment_tests.py
python -X utf8 scripts/run_power_guard.py -- python -X utf8 android/build_apk.py --sdk-root android/build-local/sdk --out-dir android/build-local/percussion-20261102 --version-code 8 --version-name 0.5-percussion-20261102
```

构建和回归均受电池保护包装，30秒轮询，未接电且电量<=25%时停止自身进程树并保存状态；本次收尾电量约56%，未触发停止。短HDL播放器按明确的1MHz参数加速5秒音乐时间，DDS/包络检查的是原始48000Hz规定帧数；没有缩短生产固定时长，也不将行为仿真当作手机UI、无线链路、实板音质或时序验收。
