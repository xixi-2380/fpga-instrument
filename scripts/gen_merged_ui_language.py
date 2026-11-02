"""Merged UI font: preserve main's Latin glyphs/title, add compact Chinese words.

8-bit codes32..95 are ordinary ASCII. Chinese uses128..255,1..31,96..127 (zero remains blank).
This permits191 Chinese glyphs without widening every pixel text register.
Old unused script-heading words are reused; ROM remains32768x16.
"""
from pathlib import Path
import json,hashlib,re,os,sys
R=Path(__file__).resolve().parents[1]
if (R/'work/ui_deps').is_dir():sys.path.insert(0,str(R/'work/ui_deps'))
from PIL import Image,ImageDraw,ImageFont
from fontTools.ttLib import TTFont
R=Path(__file__).resolve().parents[1]
WORDS='''SINE|正弦
FLUTE|长笛
REED|簧管
CELLO|大提琴
PIANO|钢琴
GUITAR|木吉他
VIBRAPHONE|颤音琴
ORGAN|管风琴
BASS|电贝斯
VIOLIN|小提琴
STRINGS|弦乐
TRUMPET|小号
SAX|萨克斯
LEAD|主音
PAD|铺底
ACCORDION|手风琴
SUSTAIN|延音
ROOM|混响
TREMOLO|颤音
ON|开启
OFF|关闭
TIMBRE|音色
EFFECT|效果
AMOUNT|强度
DEPTH|深度
RATE|速度
TAIL TIME|延音时间
VOLUME|音量
DEFAULT|默认
SETTINGS|设置
RETURN|返回
THEME|主题
EGG|彩蛋
VIEW|视图
WAVEFORM|输出波形
SPECTRUM|实时频谱
LISSAJOUS|李萨如
FFT WAIT|频谱准备
LEVEL|电平
VOICES|声部
READY|就绪
STARTING|启动中
LIVE KEYS|键盘演奏
AUTO SCORE|自动演奏
KEYBOARD|琴键
CHINESE|中文
HARP|箜篌
CHORUS|合唱
MIX|混合
LOW|低
MID|中
HIGH|高
SLOW|慢
FAST|快
NEXT PAGE|下一页
LIBRARY|曲库
PREV|上一首
NEXT|下一首
LOAD|加载
PLAY|播放
PAUSE|暂停
RESUME|继续
STOP|停止
SAVE|保存
DELETE|删除
FLASH INFO|存储信息
VALID|有效
EMPTY|空白
BUSY|处理中
ERROR|错误
DELETE AGAIN|再次点击确认删除
READ ONLY|只读
ULTRA PITCH|超声波滑音
DEADBAND|回中范围
MIN CM|距离下限
MAX CM|距离上限
DISTANCE|距离
SENSITIVITY|整体灵敏度
APPLY|应用
SUCCESS|完成
FAILED|失败
GLOBAL GSR KOR|三板统一设置
TOUCH READY|触摸就绪
TOUCH ERROR|触摸异常
TOUCH WAIT|等待触摸
MONO DELAY XY|单声道延迟XY
16 SAMPLE DELAY|延迟16采样
FIXED GUITAR|固定吉他
PANEL TIMBRE|当前音色
TOUCH STRINGS|触屏拨弦
SENSOR BEND|超声波控制音高
CHORUS ON|合唱开启
CHORUS OFF|合唱关闭
PEAK|峰值
TITLE|高山流水'''

def main():
    words=dict(line.split('|') for line in WORDS.splitlines())
    chars=sorted(set(''.join(words.values()))-set(chr(c) for c in range(128)))
    assert len(chars)<=191
    codes={ch:(128+i if i<128 else i-127 if i<159 else i-63) for i,ch in enumerate(chars)}
    def encoded(t):return bytes(ord(c) if ord(c)<128 else codes[c] for c in t)
    rom=[int(x,16) for x in (R/'src/rom/theme_font.hex').read_text().split()][:13824]
    assert len(rom)==13824
    latin_sha=hashlib.sha256(b''.join(x.to_bytes(2,'big') for x in rom)).hexdigest()
    fonts=[R/'assets/fonts'/n for n in ['HighWaterChineseBrush.ttf','HighWaterChineseElegant.ttf','HighWaterChinesePlayful.ttf']]
    fallback=Path(os.environ.get('UI_FALLBACK_FONT','C:/Windows/Fonts/msyh.ttc'))
    fallback_font=ImageFont.truetype(str(fallback),15)
    fallback_cmap=TTFont(fallback,fontNumber=0).getBestCmap()
    font_info=[]
    for path in fonts:
        font=ImageFont.truetype(str(path),15);cmap=TTFont(path).getBestCmap();fallback_chars=[]
        for ch in chars:
            assert ord(ch) in cmap or ord(ch) in fallback_cmap,ch
            used=font if ord(ch) in cmap else fallback_font
            if ord(ch) not in cmap:fallback_chars.append(ch)
            box=used.getbbox(ch);g=Image.new('L',(box[2]-box[0],box[3]-box[1]));ImageDraw.Draw(g).text((-box[0],-box[1]),ch,font=used,fill=255)
            g.thumbnail((16,15),Image.Resampling.LANCZOS);im=Image.new('L',(16,16));im.paste(g,((16-g.width)//2,(16-g.height)//2))
            rows=[sum(1<<(15-x) for x in range(16) if im.getpixel((x,y))>=70) for y in range(16)]
            assert any(rows),ch;rom+=rows
        font_info.append(dict(file=str(path.relative_to(R)),fallback_chars=''.join(fallback_chars)))
    title_base=len(rom)
    for path in fonts:
        font=ImageFont.truetype(str(path),48);t=words['TITLE'];box=font.getbbox(t)
        g=Image.new('L',(box[2]-box[0],box[3]-box[1]));ImageDraw.Draw(g).text((-box[0],-box[1]),t,font=font,fill=255)
        g.thumbnail((370,60),Image.Resampling.LANCZOS);im=Image.new('L',(384,64));im.paste(g,((384-g.width)//2,(64-g.height)//2))
        for y in range(64):
            for tile in range(48):rom.append(sum(min(3,(im.getpixel((tile*8+x,y))+42)//85)<<(14-2*x) for x in range(8)))
    used=len(rom);assert used<=32768;rom += [0]*(32768-used)
    (R/'src/rom/theme_font.hex').write_text('\n'.join(' '.join(f'{v:04x}' for v in rom[i:i+32]) for i in range(0,len(rom),32))+'\n',encoding='utf-8')
    header=['// Generated compact bilingual word table; ASCII uppercase32..95, Chinese extended codes.',f'localparam integer ZH_GLYPH_BASE=13824,ZH_STYLE_WORDS={len(chars)*16},ZH_GLYPHS={len(chars)},ZH_TITLE_BASE={title_base};']
    for name,key in [('ZH_CHINESE','CHINESE'),('ZH_PEAK','PEAK'),('ZH_VOICES','VOICES')]:
        header.append(f"localparam [{len(words[key])*8-1}:0] {name}={len(words[key])*8}'h{encoded(words[key]).hex()};")
    for n,(en,zh) in enumerate(words.items()):header.append('localparam [6:0] TXT_'+re.sub('[^A-Z0-9]+','_',en).strip('_')+'=7\'d'+str(n)+';')
    header += ['function automatic [325:0] ui_word(input [6:0] id,input zh);','begin case(id)']
    for n,(en,zh) in enumerate(words.items()):
        assert all(32<=ord(c)<96 for c in en),en
        header.append(f" 7'd{n}:ui_word=zh?{{6'd{len(zh)},320'h{encoded(zh).hex()}}}:{{6'd{len(en)},320'h{encoded(en).hex()}}};")
    header += [' default:ui_word=0;','endcase end','endfunction']
    (R/'src/config/ui_language.svh').write_text('\n'.join(header)+'\n',encoding='utf-8')
    (R/'assets/merged_ui_language.json').write_text(json.dumps(words,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    manifest=dict(glyphs=len(chars),glyph_order=''.join(chars),used_words=used,rom_words=32768,latin_title_prefix_words=13824,latin_title_prefix_sha256=latin_sha,title_base=title_base,fonts=font_info,fallback_font=str(fallback))
    (R/'assets/merged_ui_language_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(glyphs=len(chars),used_words=used,rom_words=32768)))
if __name__=='__main__':main()
