"""Reproducible monochrome font/title ROM for the British UI. Offline only.
Requires Pillow and Liberation Sans Narrow / Liberation Serif fonts.
No generated concept image is used as an FPGA framebuffer.
"""
from pathlib import Path
import argparse
from PIL import Image,ImageDraw,ImageFont
p=argparse.ArgumentParser();p.add_argument('--font-dir',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[1]
f=ImageFont.truetype(str(a.font_dir/'LiberationSansNarrow-Bold.ttf'),15)
words=[]
for code in range(32,128):
 im=Image.new('L',(10,16));ch=chr(code)
 box=f.getbbox(ch);w=max(1,box[2]-box[0]);h=max(1,box[3]-box[1])
 glyph=Image.new('L',(w,h));ImageDraw.Draw(glyph).text((-box[0],-box[1]),ch,font=f,fill=255)
 if w>9:glyph=glyph.resize((9,h),Image.Resampling.LANCZOS);w=9
 im.paste(glyph,((10-w)//2,max(0,13-h)))
 for y in range(16):words.append(sum((1<<(15-x)) for x in range(10) if im.getpixel((x,y))>=100))
title=Image.new('L',(384,64));d=ImageDraw.Draw(title)
t=ImageFont.truetype(str(a.font_dir/'LiberationSerif-Italic.ttf'),30)
d.text((0,-3),'High Mountains,',font=t,fill=255)
d.text((56,27),'Flowing Water',font=t,fill=255)
for y in range(64):
 for tile in range(24):words.append(sum(1<<(15-x) for x in range(16) if title.getpixel((tile*16+x,y))>=90))
words.extend([0]*(4096-len(words)))
(r/'src/rom/british_font.hex').write_text(''.join(f'{w:04x}\n' for w in words))
print('BRITISH_ROM words',len(words),'bits',len(words)*16)
