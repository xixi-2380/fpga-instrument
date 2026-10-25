# 彩蛋图像来源与处理

用户原图：image(20261023-125826).png；原文件只读保留，没有替换用户上传文件。

本目录egg_cutout.png是通过内置image_gen编辑生成的派生图，取出同一人物和前景脚部、去除背景与字幕，再转换为适合项目存储的RGBA PNG（约400×300）。不使用原视频音轨。生成资产由scripts/gen_theme_assets.py --egg-only转换为现有400×240×8bit ROM（32色+脚部蒙版），没有扩大动画帧或ROM容量。

## 使用的编辑提示词

Edit this exact reference photograph into a clean transparent-background cutout asset for an FPGA screen. Keep BOTH the same seated woman (东北雨姐) on the LEFT, including her entire visible head, crossed arms, pink shirt and dark trousers, AND the same enlarged foreground raised bare foot/sole on the RIGHT. Preserve her facial identity, expression, clothing, pose, the photographic look, the original foot appearance and their relative perspective. The woman must remain clearly visible; do not crop her out or create a foot-only image. Keep the pair together as a landscape 4:3 composition with a little transparent safety margin at every edge; fit all visible head and foot/toes inside the canvas. Remove the gray/white background to actual transparency. Completely remove the subtitle 最神奇的是 from the lower part, restoring the underlying trousers/skin cleanly. No text, no captions, no watermark, no extra people or objects. Do not add decorations, frames, UI, or change the scene into an illustration. Intended output is only this woman-plus-foot cutout.

## 显示与边界

演奏页：独立左侧图像区400×300，右侧保持真实波形、峰值和16个音符监视，避免面部被卡片挡住。设置页：完整人物+脚缩放在右下空白背景中，保留七音色、三效果、参数与按钮的原触摸命中矩形。派生素材留有透明边距，脚部放大时不裁掉脚趾；人物不参与脚部变换。照片采用32色和有限分辨率，存在像素化与图像编辑重建取舍。
