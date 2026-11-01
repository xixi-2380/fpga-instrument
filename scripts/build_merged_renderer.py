"""Reconstruct merged renderer from the audited main pixel pipeline."""
from pathlib import Path
import re,json,shutil
R=Path(__file__).resolve().parents[1]
src=(R/'references/audit_main/src/rgb_ui_renderer.sv').read_text(encoding='utf-8')
s=src.replace('module rgb_ui_renderer(','module rgb_ui_renderer #(parameter integer FRAME_LOCKED_INPUTS=0)(',1)
s=s.replace('input wire [1111:0] status_data','input wire [1279:0] status_data',1)
s=s.replace('input wire [512:0] analysis_data,input wire analysis_valid);','input wire [512:0] analysis_data,input wire analysis_valid,\n input wire [145:0] more_data,input wire [63:0] performance_data);',1)
s=s.replace('wire [1:0] theme=state[55:54];','wire [1:0] theme=state[1209:1208];',1).replace('wire language_zh=state[56];','wire language_zh=state[1210];',1).replace('wire [1:0] view_mode=state[58:57];','wire [1:0] view_mode=state[1212:1211];',1)
s=s.replace('reg [1111:0] state;','''reg [1279:0] state_q;reg [145:0] more_q;reg [63:0] performance_q;
 wire [1279:0] state=FRAME_LOCKED_INPUTS!=0 ? status_data : state_q;
 wire [145:0] more_state=FRAME_LOCKED_INPUTS!=0 ? more_data : more_q;
 wire [63:0] performance_state=FRAME_LOCKED_INPUTS!=0 ? performance_data : performance_q;
 wire [31:0] sensitivity=state[1244:1213];
 wire sensitivity_page=sensitivity[15];
 wire sensor_page=state[1166],sensor_enabled=state[1165];
 wire [2:0] sensor_sensitivity=state[1164:1162],sensor_state=state[1147:1145];
 wire [6:0] sensor_min=state[1161:1155],sensor_max=state[1154:1148];
 wire [11:0] sensor_distance=state[1144:1133];
 wire [35:0] piano_notes={state[1203:1184],state[79:64]};
 wire performance_page=performance_state[0] && !state[20];
 wire library_page=state[20] && more_state[81];
 wire ordinary_page=!state[20] && !performance_page && !sensitivity_page && !sensor_page && !library_page;
 wire [2:0] effect_bits=state[1169:1167];
 wire [6:0] volume=state[60:54];
 wire [15:0] sustain_ms_bcd={2'd0,state[63:62],state[1183:1172]};''',1)
s=s.replace('wire [2:0] timbre={state[53],state[13:12]};','wire [3:0] timbre={state[1207],state[53],state[13:12]};',1)
s=s.replace('wire [3:0] rate=state[48:45];','wire [4:0] rate={state[61],state[48:45]};',1)
s=s.replace('reg [3:0] note_index;','reg [5:0] note_index;',1)
s=s.replace('reg [14:0] peak_scaled;','reg [14:0] peak_scaled;',1)
s=s.replace('wire xy_region=!menu && view_mode==2','wire xy_region=ordinary_page && view_mode==2',1)
s=s.replace('frame_start && status_valid && !status_data[20] && status_data[58:57]==2,','frame_start && status_valid && !status_data[20] && !performance_data[0] && !status_data[1228] && status_data[1212:1211]==2,',1)
s=s.replace('wire [6:0] zh_index=char_s4[6:0];', '''wire [7:0] zh_index=char_s4>=128 ? {1'b0,char_s4[6:0]} : char_s4<32 ? 8'd127+{3'd0,char_s4[4:0]} : 8'd159+{3'd0,char_s4[4:0]};
 wire chinese_char=char_s4<32 || char_s4>=96;''',1)
s=s.replace('char_s4>=128 ? zh_bases[3]+{4\'d0,zh_index,row_s4}','chinese_char ? zh_bases[3]+{3\'d0,zh_index,row_s4}',1)
s=s.replace('char_s4>=32 && char_s4<128+ZH_GLYPHS','(char_s4!=0 && (!chinese_char || zh_index<ZH_GLYPHS))',1)
s=s.replace('state<=0;spectrum_state<=0;', 'state_q<=0;more_q<=0;performance_q<=0;spectrum_state<=0;',1)
s=s.replace('if(status_valid)state<=status_data;', 'if(status_valid)begin state_q<=status_data;more_q<=more_data;performance_q<=performance_data;end',1)
s=s.replace('status_data[55:54]!=theme','status_data[1209:1208]!=theme',1)
a=s.index(' function automatic [325:0] timbre_word')
b=s.index(' function [23:0] card',a)
s=s[:a]+''' function automatic [325:0] timbre_word(input [3:0] id);
  begin timbre_word=ui_word({3'd0,id},language_zh);end
 endfunction
 function automatic [6:0] action_word(input [6:0] a);
  begin case(a)
   UI_MODE:action_word=menu ? TXT_RETURN : TXT_SETTINGS;
   UI_MORE_BACK,UI_ULTRA_BACK,UI_SENS_BACK,UI_HARP_BACK:action_word=TXT_RETURN;
   UI_HARP_OPEN:action_word=TXT_HARP;
   UI_THEME:action_word=TXT_THEME;UI_VIEW:action_word=TXT_VIEW;UI_EGG:action_word=TXT_EGG;
   UI_ECHO:action_word=TXT_SUSTAIN;UI_ROOM:action_word=TXT_ROOM;UI_TREMOLO:action_word=TXT_TREMOLO;
   UI_FX:action_word=effect_bits[fx] ? TXT_ON : TXT_OFF;
   UI_DEFAULTS,UI_SENS_DEFAULT:action_word=TXT_DEFAULT;
   UI_TONE_PAGE:action_word=TXT_NEXT_PAGE;
   UI_OPEN_MORE:action_word=TXT_LIBRARY;UI_ULTRA_OPEN:action_word=TXT_ULTRA_PITCH;UI_SENSITIVITY:action_word=TXT_SENSITIVITY;
   UI_SONG_PREV:action_word=TXT_PREV;UI_SONG_NEXT:action_word=TXT_NEXT;UI_SONG_LOAD:action_word=TXT_LOAD;UI_SONG_PLAY:action_word=TXT_PLAY;
   UI_SONG_PAUSE:action_word=TXT_PAUSE;UI_SONG_RESUME:action_word=TXT_RESUME;UI_SONG_STOP:action_word=TXT_STOP;
   UI_SONG_SAVE:action_word=TXT_SAVE;UI_SONG_DELETE:action_word=TXT_DELETE;UI_FLASH_INFO:action_word=TXT_FLASH_INFO;
   UI_ULTRA_TOGGLE:action_word=sensor_enabled ? TXT_ON : TXT_OFF;
   UI_SENS_APPLY:action_word=TXT_APPLY;
   UI_CHORUS:action_word=performance_state[1] ? TXT_ON : TXT_OFF;
   UI_CHORUS_DEPTH:action_word=performance_state[6:5]==0 ? TXT_LOW : performance_state[6:5]==1 ? TXT_MID : TXT_HIGH;
   UI_CHORUS_RATE:action_word=performance_state[8:7]==0 ? TXT_SLOW : performance_state[8:7]==1 ? TXT_MID : TXT_FAST;
   UI_HARP_TONE:action_word=performance_state[33] ? TXT_PANEL_TIMBRE : TXT_FIXED_GUITAR;
   default:action_word=TXT_RETURN;
  endcase end
 endfunction
 reg [6:0] hit_action;
 reg [43:0] hit_rect;
 reg button_selected;
''' +s[b:]
layout_start=s.index(' always @*begin\n  px=')
layout_end=s.index(' // S1 layout;',layout_start)
old=s[layout_start:layout_end]
play_start=old.index('  end else if(theme==3)begin')
play_end=old.index('  // Shared header/status',play_start)
play=old[play_start:play_end]
play=play.replace('  end else if(theme==3)begin','  end else if(theme==3)begin',1)
# Replace old sixteen-note tiles by all36 physical note indicators.
ea=play.index('   if(ui_inside(px,py,480,342,288,60))begin')
eb=play.index('  end else begin',ea)
play=play[:ea]+'''   if(py>=342 && py<402 && px>=480 && px<768)begin
    note_index=(py<362 ? 0 : py<382 ? 12 : 24);left=480;top=py<362 ? 342 : py<382 ? 362 : 382;
    for(integer tile=0;tile<12;tile=tile+1)if(px>=480+tile*24 && px<504+tile*24)begin note_index=note_index+tile;left=480+tile*24;end
    if(px<left+22 && py<top+18)begin base=piano_notes[note_index] ? GOLD : BG;end
   end
''' +play[eb:]
na=play.index('   if(py>=348 && py<396')
nb=play.index('  end\n  if(!menu && view_mode==1)',na)
play=play[:na]+'''   if(py>=346 && py<400 && px>=32 && px<764)begin
    note_index=py<364 ? 0 : py<382 ? 12 : 24;left=32;top=py<364 ? 346 : py<382 ? 364 : 382;
    for(integer tile=0;tile<12;tile=tile+1)if(px>=32+tile*61 && px<93+tile*61)begin note_index=note_index+tile;left=32+tile*61;end
    if(px<left+57 && py<top+16)begin
     base=piano_notes[note_index] ? GOLD : BG;fg=piano_notes[note_index] ? INK : DIM;
     case(note_index%12)0,1:ch="C";2,3:ch="D";4:ch="E";5,6:ch="F";7,8:ch="G";9,10:ch="A";default:ch="B";endcase
     wide_text=0;text={ch,(note_index%12==1 || note_index%12==3 || note_index%12==6 || note_index%12==8 || note_index%12==10)?8'd35:8'd32,digit(note_index/12+4)};
     len=3;tx=left+7;ty=top;
    end
   end
''' +play[nb:]
oldwords=list(json.loads((R/'assets/ui_language.json').read_text(encoding='utf-8')).keys())[:-4]
mapping={'ECHO':'SUSTAIN','FX ON':'ON','FX OFF':'OFF','ECHO ON':'ON','ROOM ON':'ON','TREMOLO ON':'ON','EFFECTS OFF':'OFF','OUTPUT WAVEFORM':'WAVEFORM','NEAR FULL':'LEVEL','PCM OUTPUT':'READY','REALTIME SPECTRUM':'SPECTRUM','LOG MAG':'SPECTRUM','X8 DISPLAY':'WAVEFORM','0-24 KHZ':'SPECTRUM','150 MS':'TAIL TIME','DELAY TIME':'TAIL TIME','AMOUNT':'AMOUNT','R4C4: RETURN':'RETURN','TOUCH SETTINGS':'SETTINGS'}
def token(n):
 key=oldwords[int(n)];key=mapping.get(key,key);return 'TXT_'+re.sub('[^A-Z0-9]+','_',key).strip('_')
play=re.sub(r"6'd(\d+)",lambda m:token(m[1]),play)
play=play.replace('if(!menu && view_mode==','if(ordinary_page && view_mode==')

layout=''' always @*begin
  px=integer'(raster_x);py=integer'(raster_y);base=BG;fg=CREAM;text=0;len=0;tx=0;ty=0;
  wide_text=language_zh;dx=0;dy=0;ci=0;i=0;k=0;left=0;top=0;note_index=0;pc=0;
  spectrum_bin=0;spectrum_level=0;bin=0;point_y=234;previous_y=234;minimum_y=234;maximum_y=234;
  ch=0;font_addr=0;font_bit=0;text_ink=0;alpha_font=0;hit_action=UI_NONE;hit_rect=0;button_selected=0;
  if((py==78 && px>=20 && px<780)||(py==410 && px>=20 && px<780))base=LINE;
  if(sensitivity_page)begin
   if(py>=100 && py<124)begin {len,text}=ui_word(TXT_GLOBAL_GSR_KOR,language_zh);tx=32;ty=104;fg=GOLD;end
   if(py>=184 && py<208)begin
    if(px<380)begin wide_text=0;text="GSR";len=3;tx=64;ty=192;end
    else begin wide_text=0;text={digit(sensitivity[3:0]/10),digit(sensitivity[3:0]%10)};len=2;tx=570;ty=194;end
   end
   if(py>=268 && py<292)begin
    if(px<380)begin wide_text=0;text="KOR";len=3;tx=64;ty=276;end
    else begin wide_text=0;text={digit(sensitivity[11:4]/100),digit((sensitivity[11:4]/10)%10),digit(sensitivity[11:4]%10)};len=3;tx=564;ty=278;end
   end
   if(py>=344 && py<380 && px<400)begin {len,text}=ui_word(sensitivity[12]?TXT_BUSY:sensitivity[13]?TXT_FAILED:sensitivity[14]?TXT_SUCCESS:TXT_READY,language_zh);tx=64;ty=358;fg=sensitivity[13]?RED:GREEN;end
  end else if(sensor_page)begin
   if(py>=100 && py<124 && px<440)begin {len,text}=ui_word(TXT_ULTRA_PITCH,language_zh);tx=32;ty=108;fg=GOLD;end
   if(py>=188 && py<212)begin
    if(px<440)begin {len,text}=ui_word(TXT_RESPONSE,language_zh);tx=64;ty=196;end
    else begin wide_text=0;text={digit(sensor_sensitivity)};len=1;tx=616;ty=196;end
   end
   if(py>=260 && py<284)begin
    if(px<440)begin {len,text}=ui_word(TXT_MIN_CM,language_zh);tx=64;ty=268;end
    else begin wide_text=0;text={digit(sensor_min/100),digit((sensor_min/10)%10),digit(sensor_min%10)};len=3;tx=604;ty=268;end
   end
   if(py>=332 && py<356)begin
    if(px<440)begin {len,text}=ui_word(TXT_MAX_CM,language_zh);tx=64;ty=340;end
    else begin wide_text=0;text={digit(sensor_max/100),digit((sensor_max/10)%10),digit(sensor_max%10)};len=3;tx=604;ty=340;end
   end
   if(py>=376 && py<400)begin
    if(px<400)begin {len,text}=ui_word(TXT_DISTANCE,language_zh);tx=64;ty=380;end
    else begin wide_text=0;text={digit(sensor_distance[11:8]),digit(sensor_distance[7:4]),digit(sensor_distance[3:0])," CM"};len=6;tx=564;ty=380;fg=sensor_state==2?GREEN:DIM;end
   end
  end else if(library_page)begin
   if(py>=100 && py<124)begin {len,text}=ui_word(TXT_LIBRARY,language_zh);tx=32;ty=104;fg=GOLD;end
   if(py>=144 && py<168)begin
    wide_text=0;text={"S",digit((more_state[4:0]+1)/10),digit((more_state[4:0]+1)%10)};len=3;tx=32;ty=148;
    if(px>=200)begin wide_text=language_zh;{len,text}=ui_word(more_state[5]?TXT_VALID:TXT_EMPTY,language_zh);tx=224;end
   end
   if(py>=358 && py<382)begin {len,text}=ui_word(more_state[6]?TXT_BUSY:!more_state[58]?TXT_READ_ONLY:TXT_READY,language_zh);tx=32;ty=364;fg=GOLD;end
   if(py>=388 && py<410)begin
    if(more_state[80])begin {len,text}=ui_word(TXT_DELETE_AGAIN,language_zh);tx=32;ty=390;fg=RED;end
    else if(more_state[15:8]!=0)begin {len,text}=ui_word(TXT_ERROR,language_zh);tx=32;ty=390;fg=RED;
     if(px>=280)begin wide_text=0;text={digit(more_state[15:8]/100),digit((more_state[15:8]/10)%10),digit(more_state[15:8]%10)};len=3;tx=300;end
    end
   end
  end else if(performance_page)begin
   if(py>=84 && py<104)begin {len,text}=ui_word(TXT_TOUCH_STRINGS,language_zh);tx=32;ty=86;fg=GOLD;
    if(px>=688)begin {len,text}=ui_word(TXT_CHORUS,language_zh);tx=704;end
   end
   for(integer string_id=0;string_id<12;string_id=string_id+1)begin
    left=112+48*string_id;
    if(px>=left-1 && px<=left+1 && py>=132+7*string_id && py<340)base=performance_state[9+string_id]?GREEN:GOLD;
   end
   if(py>=112 && py<224 && px>=88 && px<668 && (py*48>=px*7+4752 && py*48<px*7+4896))base=GOLD;
   if(py>=340 && py<360 && px>=88 && px<688)begin
    i=(px-88)/48;left=88+i*48;wide_text=0;
    case(i)0,5,10:ch="C";1,6,11:ch="D";2,7:ch="E";3,8:ch="G";default:ch="A";endcase
    text={ch,digit(i<5?4:i<10?5:6)};len=2;tx=left+14;ty=344;
   end
   if(py>=376 && py<400 && px>=320 && px<688)begin {len,text}=ui_word(TXT_SENSOR_BEND,language_zh);tx=320;ty=380;fg=DIM;end
   if(px>=704 && py>=160 && py<176)begin {len,text}=ui_word(TXT_MIX,language_zh);tx=704;ty=160;fg=DIM;end
   if(px>=704 && py>=228 && py<244)begin {len,text}=ui_word(TXT_DEPTH,language_zh);tx=704;ty=228;fg=DIM;end
   if(px>=704 && py>=296 && py<312)begin {len,text}=ui_word(TXT_RATE,language_zh);tx=704;ty=296;fg=DIM;end
  end else if(menu)begin
   if(ui_inside(px,py,20,92,260,310)||ui_inside(px,py,296,92,484,310))base=PANEL;
   if(py>=98 && py<118)begin {len,text}=ui_word(px<280?TXT_TIMBRE:TXT_EFFECT,language_zh);tx=px<280?32:308;ty=100;fg=GOLD;end
   if(py>=190 && py<220 && px>=308 && px<620)begin {len,text}=ui_word(TXT_AMOUNT,language_zh);tx=308;ty=192;fg=GOLD;end
   if(py>=250 && py<278 && px>=380 && px<696)begin wide_text=0;text={amount_hundreds,amount_tens,amount_units,"%"};len=4;tx=514;ty=256;end
   if(py>=306 && py<330 && px>=380 && px<696)begin
    {len,text}=ui_word(TXT_VOLUME,language_zh);tx=380;ty=312;
    if(px>=568)begin wide_text=0;text={volume==100?8'd49:8'd32,volume>=10?digit((volume/10)%10):8'd32,digit(volume%10),"%"};len=4;tx=588;end
   end
   if(py>=350 && py<378 && px>=380 && px<696)begin
    if(fx==2)begin wide_text=0;text={digit(rate/10),digit(rate%10)," HZ"};len=5;tx=500;ty=358;end
    else if(fx==0)begin wide_text=0;text={digit(sustain_ms_bcd[15:12]),digit(sustain_ms_bcd[11:8]),digit(sustain_ms_bcd[7:4]),digit(sustain_ms_bcd[3:0])," MS"};len=7;tx=488;ty=358;end
    else begin {len,text}=ui_word(TXT_ROOM,language_zh);tx=504;ty=358;end
   end
''' +play+'''
  if(ordinary_page && px>=648 && py>=420 && py<464)begin
   wide_text=0;fg=DIM;tx=648;
   if(py<440)begin text={"LAT ",digit(state[1131:1128]),digit(state[1127:1124]),digit(state[1123:1120]),".",digit(state[1119:1116]),digit(state[1115:1112])};len=10;ty=422;if(!state[1132])begin text="LAT --";len=6;end end
   else begin text={"VOICES ",voice_tens,voice_units,"/32"};len=12;ty=446;end
  end
  // One geometry and action map drives both buttons and touch acceptance.
  hit_action=sensitivity_page ? sensitivity_hit(px,py) : sensor_page ? ultrasonic_hit(px,py) : library_page ? more_hit(px,py) : performance_page ? harp_hit(px,py) : ui_hit(px,py,fx,menu);
  if(hit_action!=UI_NONE)begin
   hit_rect=ui_rect(hit_action);left=hit_rect[43:33];top=hit_rect[32:22];
   button_selected=(hit_action>=64 && hit_action<72 && timbre[2:0]==hit_action-64) ||
    (hit_action==UI_ECHO && fx==0)||(hit_action==UI_ROOM && fx==1)||(hit_action==UI_TREMOLO && fx==2)||
    (hit_action==UI_EGG && theme==3)||(hit_action==UI_CHORUS && performance_state[1]);
   base=card(px,py,left,top,hit_rect[21:11],hit_rect[10:0],button_selected);fg=button_selected?INK:GOLD;
   wide_text=language_zh;{len,text}=ui_word(action_word(hit_action),language_zh);
   if(hit_action>=64 && hit_action<72){len,text}=timbre_word({timbre[3],hit_action[2:0]});
   if(hit_action==UI_LANGUAGE)begin wide_text=!language_zh;if(language_zh)begin text="ENGLISH";len=7;end else {len,text}=ui_word(TXT_CHINESE,1'b1);end
   if(hit_action==UI_CHORUS_MIX)begin wide_text=0;case(performance_state[4:2])1:text="13%";2:text="25%";3:text="38%";default:text="50%";endcase len=3;end
   if(hit_action==UI_LESS || hit_action==UI_SLOWER || hit_action==UI_VOLUME_DOWN || hit_action==UI_SENS_DOWN || hit_action==UI_MIN_DOWN || hit_action==UI_MAX_DOWN || hit_action==UI_GSR_DOWN || hit_action==UI_KOR_DOWN)begin wide_text=0;text="-";len=1;end
   if(hit_action==UI_MORE || hit_action==UI_FASTER || hit_action==UI_VOLUME_UP || hit_action==UI_SENS_UP || hit_action==UI_MIN_UP || hit_action==UI_MAX_UP || hit_action==UI_GSR_UP || hit_action==UI_KOR_UP)begin wide_text=0;text="+";len=1;end
   tx=left+(integer'(hit_rect[21:11])-integer'(len)*(wide_text?16:10))/2;ty=top+(integer'(hit_rect[10:0])-16)/2;
  end
  // Existing title bitmaps/fonts and artwork are retained for all themes.
  if(ui_inside(px,py,24,4,384,64))begin
   font_addr=(language_zh ? ZH_TITLE_BASE : 4608)+integer'(font_theme)*3072+(py-4)*48+((px-24)>>3);
   font_bit=14-((px-24)%8)*2;text_ink=1;alpha_font=1;fg=GOLD;
  end
  if(state[19])begin
   case(1'b1)px<100:base=24'hffffff;px<200:base=24'hffff00;px<300:base=24'h00ffff;px<400:base=24'h00ff00;px<500:base=24'hff00ff;px<600:base=24'hff0000;px<700:base=24'h0000ff;default:base=0;endcase
   if(px==0 || px==799 || py==0 || py==479)base=CREAM;text_ink=0;
  end
  if(!raster_de || px>=800 || py>=480)begin base=0;text_ink=0;end
 end
'''
s=s[:layout_start]+layout+s[layout_end:]
a=s.index(' reg [1279:0] state_q;');b=s.index(' wire [31:0] sensitivity=',a);block=s[a:b];s=s[:a]+s[b:];i=s.index(' wire [1:0] theme=');s=s[:i]+block+s[i:]
# Labels in extracted original monitor code refer to generated names above.
(R/'src/rgb_ui_renderer.sv').write_text(s,encoding='utf-8')
for name in ['ui_theme_art.sv','audio_spectrum.sv','lissajous_plot.sv']:
 shutil.copyfile(R/'references/audit_main/src'/name,R/'src'/name)
shutil.copyfile(R/'references/audit_main/src/config/theme_storage.svh',R/'src/config/theme_storage.svh')
print('Merged renderer and main visual modules written')
