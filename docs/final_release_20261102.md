# 最终完整版：2026-11-02

用户已对本次生成的位流进行上板测试，并确认“没有任何问题”，指定本版为最终完整版。停止进一步优化，旧实板版本与暂停的优化候选继续保留。

功能源码提交：256214a5fb864ea6e1601e01c2e1ef7ecd19d314。本次发布只添加验收记录，不改变HDL、约束或APK。

包含W25新按键1ms检测标记、超声波距离与回中范围统一cm、原16采样延迟XY，以及兼容GM鼓键/可选锣声近似的Android 0.5。XY未复现明确缺陷，保留原算法。

物理运行：adjustments_powered_20261102。布线完整，0未布通，70管脚核对通过；PNR47分46秒，总耗时56分22秒。历史STA结果如实保留：57 setup / 0 hold，WNS ref +0.746ns / audio -0.618ns / pixel -7.688ns。用户实板验收不改变静态时序报告，不能称为零违例时序收敛。

最终烧录文件本地位置：F:/FPGA_Projects/D2_最终完整版_实板通过_20261102.fs
SHA256：3ff2909921e6b15e5e8cf20aad9d758cdcbe6f3d5fd0f816f033bc5703b2f44a

APK：android/dist/GaoshanScore-0.5-percussion-20261102.apk；SHA256 14bab9b7701fe0feeb641fc54edbfbcdd6ea00a04e1380ef6b3b62e870ab3332。开发签名与旧版不同，安装说明见GM鼓与锣声近似文档。

原版保存在GitHub baseline/main-board-tested-20261101及F:/FPGA_Projects/main-board-tested-7d84ac3-20261101。
