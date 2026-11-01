# 持续发声排查：松键事件必须独立排空

已复现并修复一个具体逻辑缺陷：key_note_events把所有状态变化都放在enabled门后。已有按键的On完成握手后，若enabled变低而琴键松开，reported_keys仍保持1，适配器不发Off，分配器及包络持续持音。

baseline/voices4.log为修改前的预期失败：release stranded while admission disabled，held=1、active=1、reported=1、valid=0，在300帧观察后仍未松键。baseline中的源码快照及哈希与失败输入对应。

修复仅修改src/key_note_events.sv：选择条件从enabled && (released || pressed)，改为released || (enabled && pressed)。禁用新起音不再禁止已有松键排出；优先级/FCW准备和所有已在途valid载荷仍保持到握手，没有新增强制截音超时。

## 验证

- 1/4/32声部端到端：实体键router、key_note_events、实体/触屏仲裁、分配器、原生包络和延音包络串联，共1023378拍检查，起音/松键105～438对/配置。
- 覆盖禁止新On后的Off、正常长按、菜单/断连/无效快照、恢复后必须松开重按、36键随机快照、引擎背压、声部替换/同键尾音、触屏/实体交错以及背压中复位。
- 定向在途/背压测试1713项，40个On和40个Off：valid已拉高后的300拍背压、优先级/ROM准备期间撤销enabled、旧键松开与新键按下并存、36键和弦全松。合法长按不被计时器截断。
- 既有16/36键适配器测试149/269项通过。
- 总计1025509项，详见summary.json及各阶段validation.json和源哈希。各组是组件/模型测试，不冒称完整新main或实板验收。

## 边界

旧生产顶层的菜单抑制主要通过note_keys归零，而enabled通常保持1；因此本修复是明确复现的组件缺口和整合时必要的健壮性处理，不宣称已经证明用户实板一直响只有这一原因。原DDS版128个setup违例、实际电极灵敏度/总线/硬件异常等仍需最终新main时序和上板复测。

主线应让菜单/灵敏度页禁止新On并把note_keys置零，但适配器继续运行以排出Off。BT/本地接管如重置reported_keys，应同时保证音源所有权确实flush。当前修复不会自行切断仍真实按住的键。

复现与检查入口：scripts/run_release_bug_tests.py --tool-bin <Icarus-bin> --out-dir <独立目录>。默认跑全组；--admission-only跑在途/背压定向组；--baseline-only仅应用于原始源码并期待上述缺陷失败。未运行Gowin，未烧录。
