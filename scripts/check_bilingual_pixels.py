"""Check actual tb_theme_pixels raster glyphs against committed font bitmaps.
Independent screen coordinates for seven cards, language button and C4 tile.
Usage: python scripts/check_bilingual_pixels.py --render-dir reports/.../...
"""
from pathlib import Path
import argparse,json,hashlib
from PIL import Image
R=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--render-dir',type=Path,required=True);a=ap.parse_args()
 manifest=json.loads((R/'assets/ui_language_manifest.json').read_text());translations=json.loads((R/'assets/ui_language.json').read_text())
 words=[int(t,16) for t in (R/'src/rom/theme_font.hex').read_text().split()]
 codes={c:128+i for i,c in enumerate(manifest['glyph_order'])};checks=0;scenes=[]
 creams=[0xf2e6c9,0x43392f,0x493321,0x332f2d];inks=[0x17191b,0xfffaf1,0xfffaf1,0xfffaf1];golds=[0xd6b979,0x856b57,0xa3652c,0x884652]
 def rgb(c):return (c>>16,(c>>8)&255,c&255)
 for scene in range(16):
  f=a.render_dir/f'theme_{scene}.ppm';im=Image.open(f).convert('RGB');assert im.size==(800,480)
  zh=scene>=8;theme=(scene%8)//2;style=0 if theme==3 else theme;menu=scene%2
  def body(text,tx,ty,advance,fg):
   nonlocal checks
   for n,ch in enumerate(text):
    code=codes[ch] if ord(ch)>=128 else ord(ch)
    base=manifest['glyph_base']+style*manifest['glyphs']*16+(code-128)*16 if code>=128 else style*1536+(code-32)*16
    for y in range(16):
     for x in range(advance):
      expected=bool(words[base+y]&(1<<(15-x)))
      actual=im.getpixel((tx+n*advance+x,ty+y))==rgb(fg)
      assert expected==actual,(scene,text,ch,x,y,'glyph mask differs')
      checks+=1
  if menu:
   for i,en in enumerate(['SINE','FLUTE','REED','CELLO','PIANO','GUITAR','VIBRAPHONE']):
    text=translations[en] if zh else en;advance=16 if zh else 10;left=28+(i%2)*124;top=132+(i//2)*64
    body(text,left+(112-len(text)*advance)//2,top+18,advance,inks[theme] if i==1 else creams[theme])
  else:
   # C4 deliberately retains narrow ASCII cells in Chinese mode to fit tile.
   body('C 4',482 if theme==3 else 38,348 if theme==3 else 364,10,inks[theme])
  body('ENGLISH' if zh else '中文',404 if zh else 450,434,16,golds[theme])
  # Fully covered title pixels must be the actual theme foreground colour.
  title_base=manifest['title_base']+style*3072 if zh else 4608+style*3072
  count=0
  for y in range(64):
   for x in range(384):
    word=words[title_base+y*48+x//8];alpha=(word>>(14-(x%8)*2))&3
    if alpha==3:
     assert im.getpixel((24+x,4+y))==rgb(golds[theme]),(scene,'title glyph mismatch',x,y)
     count+=1;checks+=1
  assert count>100
  scenes.append({'scene':scene,'language':'zh' if zh else 'en','theme':theme,'menu':bool(menu),'sha256':hashlib.sha256(im.tobytes()).hexdigest()})
 print(json.dumps({'passed':True,'checks':checks,'scenes':scenes},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
