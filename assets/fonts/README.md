# UI font assets

Existing English fonts/ROM are preserved. Chinese additions are renamed offline subsets with the 89 glyphs needed by assets/ui_language.json:

| Project subset | Upstream family | UI use | Upstream file |
|---|---|---|---|
| HighWaterChineseBrush.ttf | Ma Shan Zheng | British / Easter brush title and body | https://github.com/google/fonts/blob/main/ofl/mashanzheng/MaShanZheng-Regular.ttf |
| HighWaterChineseElegant.ttf | ZCOOL XiaoWei | Elegant cat theme | https://github.com/google/fonts/blob/main/ofl/zcoolxiaowei/ZCOOLXiaoWei-Regular.ttf |
| HighWaterChinesePlayful.ttf | ZCOOL KuaiLe | Playful capybara theme | https://github.com/google/fonts/blob/main/ofl/zcoolkuaile/ZCOOLKuaiLe-Regular.ttf |

Source fonts: SIL Open Font License 1.1; original notices/licenses are committed as mashanzheng-OFL.txt, zcoolxiaowei-OFL.txt, zcoolkuaile-OFL.txt. Derived subsets use HighWaterChinese family names. Original copyright/license name records are preserved. Glyph coverage, subset hashes, ROM offsets and the unchanged English-prefix hash are recorded in assets/ui_language_manifest.json.

Regenerate compact RTL/header/ROM with `python scripts/gen_ui_language.py`; Pillow and fontTools are used offline. The board loads the committed HEX only. The original English font sources and OFL notices remain in repository history/current remote tree; this Chinese subset generation does not replace them.

## Preserved English font provenance

# 离线字库来源

三个TTF仅供可选的ROM再生成；运行FPGA不加载TTF。它们从Google Fonts上游字体制作ASCII 32..127子集，并更名为HighWaterScript、HighWaterElegant、HighWaterRound，保留各自SIL OFL许可证。正文均为英文，本轮未加入中文切换。

| 文件 | 来源 | 处理 |
|---|---|---|
| HighWaterScript.ttf | [Great Vibes](https://github.com/google/fonts/tree/main/ofl/greatvibes) | ASCII子集，保留连笔布局字形 |
| HighWaterElegant.ttf | [Cormorant Garamond](https://github.com/google/fonts/tree/main/ofl/cormorantgaramond) | weight 700实例化后ASCII子集，增强小字可读性 |
| HighWaterRound.ttf | [Quicksand](https://github.com/google/fonts/tree/main/ofl/quicksand) | weight 600实例化后ASCII子集，更名避免保留名称冲突 |

子集由fontTools Subsetter生成，变量字体先用instantiateVariableFont指定wght，再保留ASCII及所需布局闭包；名称表family/full/PostScript等改为上述HighWater名称。对应原OFL文本同目录保存。原英伦正文继续使用外部LiberationSansNarrow-Bold.ttf，须通过--font-dir提供；字库生成ROM已包含编译所需像素，不需要用户安装字体才能综合。
