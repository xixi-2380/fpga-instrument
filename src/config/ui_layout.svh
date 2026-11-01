// Shared actions and half-open rectangles for the British UI,800x480.
localparam [6:0] UI_SINE=0,UI_FLUTE=1,UI_REED=2,UI_ECHO=3,UI_ROOM=4,
 UI_TREMOLO=5,UI_FX=6,UI_MODE=7,UI_LESS=8,UI_MORE=9,
 UI_SLOWER=10,UI_FASTER=11,UI_DEFAULTS=12,UI_CELLO=13,UI_PIANO=14,
 UI_GUITAR=15,UI_VIBES=16,UI_PREV=17,UI_NEXT=18,UI_VOLUME_DOWN=19,UI_VOLUME_UP=20,
 UI_OPEN_MORE=21,UI_MORE_BACK=22,UI_SONG_PREV=23,UI_SONG_NEXT=24,UI_SONG_PLAY=25,
 UI_SONG_PAUSE=26,UI_SONG_RESUME=27,UI_SONG_STOP=28,UI_SONG_LOAD=29,UI_SONG_SAVE=30,
 UI_SONG_DELETE=31,UI_FLASH_INFO=32,UI_ULTRA_OPEN=33,UI_ULTRA_TOGGLE=34,UI_SENS_DOWN=35,UI_SENS_UP=36,
 UI_MIN_DOWN=37,UI_MIN_UP=38,UI_MAX_DOWN=39,UI_MAX_UP=40,UI_ULTRA_BACK=41,UI_NONE=63,UI_TONE_FIRST=64,UI_TONE_PAGE=80,
 UI_THEME=81,UI_LANGUAGE=82,UI_VIEW=83,UI_EGG=84,UI_SENSITIVITY=85,
 UI_GSR_DOWN=86,UI_GSR_UP=87,UI_KOR_DOWN=88,UI_KOR_UP=89,
 UI_SENS_APPLY=90,UI_SENS_DEFAULT=91,UI_SENS_BACK=92,
 UI_HARP_OPEN=94,UI_HARP_BACK=95,UI_CHORUS=96,UI_CHORUS_MIX=97,
 UI_CHORUS_DEPTH=98,UI_CHORUS_RATE=99,UI_HARP_TONE=100;
function automatic ui_inside(input integer px,py,left,top,width,height);
 begin ui_inside=px>=left && px<left+width && py>=top && py<top+height;end
endfunction
function automatic integer timbre_x(input integer id);
 begin timbre_x=28+(id%2)*124;end
endfunction
function automatic integer timbre_y(input integer id);
 begin timbre_y=132+(id/2)*64;end
endfunction
function automatic [6:0] timbre_action(input integer id);
 begin case(id)
 0:timbre_action=UI_SINE;1:timbre_action=UI_FLUTE;2:timbre_action=UI_REED;
 3:timbre_action=UI_CELLO;4:timbre_action=UI_PIANO;5:timbre_action=UI_GUITAR;
 6:timbre_action=UI_VIBES;7:timbre_action=7'd71;default:timbre_action=UI_NONE;endcase end
endfunction
// Rectangles shared by hit testing and rendering. No board-button actions.
// {left[10:0],top[10:0],width[10:0],height[10:0]}.
function automatic [43:0] ui_rect(input [6:0] action);
 integer l,t,w,h;
 begin l=0;t=0;w=0;h=0;
  if(action>=64 && action<72)begin l=timbre_x(action-64);t=timbre_y(action-64);w=112;h=52;end
  else case(action)
   UI_MODE,UI_MORE_BACK,UI_ULTRA_BACK,UI_SENS_BACK,UI_HARP_BACK:begin l=648;t=16;w=132;h=48;end
   UI_HARP_OPEN:begin l=456;t=16;w=176;h=48;end
   UI_VIEW:begin l=24;t=420;w=132;h=44;end
   UI_LANGUAGE:begin l=168;t=420;w=132;h=44;end
   UI_THEME:begin l=312;t=420;w=132;h=44;end
   UI_EGG:begin l=456;t=420;w=132;h=44;end
   UI_DEFAULTS:begin l=648;t=420;w=132;h=44;end
   UI_TONE_PAGE:begin l=28;t=390;w=236;h=24;end
   UI_ECHO:begin l=308;t=124;w=148;h=48;end
   UI_ROOM:begin l=464;t=124;w=148;h=48;end
   UI_TREMOLO:begin l=620;t=124;w=148;h=48;end
   UI_FX:begin l=628;t=184;w=140;h=40;end
   UI_LESS:begin l=308;t=240;w=52;h=48;end
   UI_MORE:begin l=716;t=240;w=52;h=48;end
   UI_SLOWER:begin l=308;t=344;w=52;h=48;end
   UI_FASTER:begin l=716;t=344;w=52;h=48;end
   UI_VOLUME_DOWN:begin l=308;t=302;w=52;h=36;end
   UI_VOLUME_UP:begin l=716;t=302;w=52;h=36;end
   UI_OPEN_MORE:begin l=308;t=390;w=140;h=24;end
   UI_ULTRA_OPEN:begin l=464;t=390;w=148;h=24;end
   UI_SENSITIVITY:begin l=628;t=390;w=140;h=24;end
   UI_SONG_PREV,UI_SONG_NEXT,UI_SONG_LOAD,UI_SONG_PLAY:begin l=24+(action==UI_SONG_PREV?0:action==UI_SONG_NEXT?1:action==UI_SONG_LOAD?2:3)*180;t=200;w=160;h=40;end
   UI_SONG_PAUSE,UI_SONG_RESUME,UI_SONG_STOP:begin l=24+(action==UI_SONG_PAUSE?0:action==UI_SONG_RESUME?1:2)*180;t=252;w=160;h=40;end
   UI_SONG_SAVE,UI_SONG_DELETE,UI_FLASH_INFO:begin l=24+(action==UI_SONG_SAVE?0:action==UI_SONG_DELETE?1:2)*180;t=304;w=160;h=40;end
   UI_ULTRA_TOGGLE:begin l=500;t=100;w=248;h=52;end
   UI_SENS_DOWN,UI_SENS_UP:begin l=action==UI_SENS_DOWN?500:684;t=180;w=64;h=48;end
   UI_MIN_DOWN,UI_MIN_UP:begin l=action==UI_MIN_DOWN?500:684;t=252;w=64;h=48;end
   UI_MAX_DOWN,UI_MAX_UP:begin l=action==UI_MAX_DOWN?500:684;t=324;w=64;h=48;end
   UI_GSR_DOWN,UI_GSR_UP:begin l=action==UI_GSR_DOWN?432:680;t=180;w=64;h=48;end
   UI_KOR_DOWN,UI_KOR_UP:begin l=action==UI_KOR_DOWN?432:680;t=264;w=64;h=48;end
   UI_SENS_APPLY:begin l=432;t=348;w=144;h=48;end
   UI_SENS_DEFAULT:begin l=600;t=348;w=144;h=48;end
   UI_CHORUS:begin l=704;t=104;w=80;h=52;end
   UI_CHORUS_MIX:begin l=704;t=176;w=80;h=48;end
   UI_CHORUS_DEPTH:begin l=704;t=244;w=80;h=48;end
   UI_CHORUS_RATE:begin l=704;t=312;w=80;h=48;end
   UI_HARP_TONE:begin l=24;t=368;w=260;h=40;end
   default:begin end
  endcase
  ui_rect={11'(l),11'(t),11'(w),11'(h)};
 end
endfunction
function automatic ui_action_inside(input integer px,py,input [6:0] action);
 reg [43:0] r;begin r=ui_rect(action);ui_action_inside=r[21:11]!=0 && ui_inside(px,py,r[43:33],r[32:22],r[21:11],r[10:0]);end
endfunction
function automatic [6:0] global_hit(input integer px,py);
 begin global_hit=UI_NONE;
  if(ui_action_inside(px,py,UI_VIEW))global_hit=UI_VIEW;
  else if(ui_action_inside(px,py,UI_LANGUAGE))global_hit=UI_LANGUAGE;
  else if(ui_action_inside(px,py,UI_THEME))global_hit=UI_THEME;
  else if(ui_action_inside(px,py,UI_EGG))global_hit=UI_EGG;
 end
endfunction
function automatic [6:0] ui_hit(input integer px,py,input [1:0] fx,input menu);
 integer i;
 begin ui_hit=global_hit(px,py);
  if(ui_action_inside(px,py,UI_MODE))ui_hit=UI_MODE;
  else if(!menu && ui_action_inside(px,py,UI_HARP_OPEN))ui_hit=UI_HARP_OPEN;
  else if(menu)begin
   for(i=0;i<8;i=i+1)if(ui_action_inside(px,py,64+i))ui_hit=64+i;
   if(ui_action_inside(px,py,UI_TONE_PAGE))ui_hit=UI_TONE_PAGE;
   if(ui_action_inside(px,py,UI_ECHO))ui_hit=UI_ECHO;
   if(ui_action_inside(px,py,UI_ROOM))ui_hit=UI_ROOM;
   if(ui_action_inside(px,py,UI_TREMOLO))ui_hit=UI_TREMOLO;
   if(ui_action_inside(px,py,UI_FX))ui_hit=UI_FX;
   if(ui_action_inside(px,py,UI_LESS))ui_hit=UI_LESS;
   if(ui_action_inside(px,py,UI_MORE))ui_hit=UI_MORE;
   if(fx==2 && ui_action_inside(px,py,UI_SLOWER))ui_hit=UI_SLOWER;
   if(fx==2 && ui_action_inside(px,py,UI_FASTER))ui_hit=UI_FASTER;
   if(ui_action_inside(px,py,UI_VOLUME_DOWN))ui_hit=UI_VOLUME_DOWN;
   if(ui_action_inside(px,py,UI_VOLUME_UP))ui_hit=UI_VOLUME_UP;
   if(ui_action_inside(px,py,UI_OPEN_MORE))ui_hit=UI_OPEN_MORE;
   if(ui_action_inside(px,py,UI_ULTRA_OPEN))ui_hit=UI_ULTRA_OPEN;
   if(ui_action_inside(px,py,UI_SENSITIVITY))ui_hit=UI_SENSITIVITY;
   if(ui_action_inside(px,py,UI_DEFAULTS))ui_hit=UI_DEFAULTS;
  end
 end
endfunction
function automatic [6:0] more_hit(input integer px,py);
 begin more_hit=global_hit(px,py);
  if(ui_action_inside(px,py,UI_MORE_BACK))more_hit=UI_MORE_BACK;
  else if(ui_action_inside(px,py,UI_SONG_PREV))more_hit=UI_SONG_PREV;
  else if(ui_action_inside(px,py,UI_SONG_NEXT))more_hit=UI_SONG_NEXT;
  else if(ui_action_inside(px,py,UI_SONG_LOAD))more_hit=UI_SONG_LOAD;
  else if(ui_action_inside(px,py,UI_SONG_PLAY))more_hit=UI_SONG_PLAY;
  else if(ui_action_inside(px,py,UI_SONG_PAUSE))more_hit=UI_SONG_PAUSE;
  else if(ui_action_inside(px,py,UI_SONG_RESUME))more_hit=UI_SONG_RESUME;
  else if(ui_action_inside(px,py,UI_SONG_STOP))more_hit=UI_SONG_STOP;
  else if(ui_action_inside(px,py,UI_SONG_SAVE))more_hit=UI_SONG_SAVE;
  else if(ui_action_inside(px,py,UI_SONG_DELETE))more_hit=UI_SONG_DELETE;
  else if(ui_action_inside(px,py,UI_FLASH_INFO))more_hit=UI_FLASH_INFO;
 end
endfunction
function automatic [6:0] ultrasonic_hit(input integer px,py);
 begin ultrasonic_hit=global_hit(px,py);
  if(ui_action_inside(px,py,UI_ULTRA_BACK))ultrasonic_hit=UI_ULTRA_BACK;
  else if(ui_action_inside(px,py,UI_ULTRA_TOGGLE))ultrasonic_hit=UI_ULTRA_TOGGLE;
  else if(ui_action_inside(px,py,UI_SENS_DOWN))ultrasonic_hit=UI_SENS_DOWN;
  else if(ui_action_inside(px,py,UI_SENS_UP))ultrasonic_hit=UI_SENS_UP;
  else if(ui_action_inside(px,py,UI_MIN_DOWN))ultrasonic_hit=UI_MIN_DOWN;
  else if(ui_action_inside(px,py,UI_MIN_UP))ultrasonic_hit=UI_MIN_UP;
  else if(ui_action_inside(px,py,UI_MAX_DOWN))ultrasonic_hit=UI_MAX_DOWN;
  else if(ui_action_inside(px,py,UI_MAX_UP))ultrasonic_hit=UI_MAX_UP;
 end
endfunction
function automatic [6:0] sensitivity_hit(input integer px,py);
 begin sensitivity_hit=global_hit(px,py);
  if(ui_action_inside(px,py,UI_SENS_BACK))sensitivity_hit=UI_SENS_BACK;
  else if(ui_action_inside(px,py,UI_GSR_DOWN))sensitivity_hit=UI_GSR_DOWN;
  else if(ui_action_inside(px,py,UI_GSR_UP))sensitivity_hit=UI_GSR_UP;
  else if(ui_action_inside(px,py,UI_KOR_DOWN))sensitivity_hit=UI_KOR_DOWN;
  else if(ui_action_inside(px,py,UI_KOR_UP))sensitivity_hit=UI_KOR_UP;
  else if(ui_action_inside(px,py,UI_SENS_APPLY))sensitivity_hit=UI_SENS_APPLY;
  else if(ui_action_inside(px,py,UI_SENS_DEFAULT))sensitivity_hit=UI_SENS_DEFAULT;
 end
endfunction
function automatic [6:0] harp_hit(input integer px,py);
 begin harp_hit=global_hit(px,py);
  if(ui_action_inside(px,py,UI_HARP_BACK))harp_hit=UI_HARP_BACK;
  else if(ui_action_inside(px,py,UI_CHORUS))harp_hit=UI_CHORUS;
  else if(ui_action_inside(px,py,UI_CHORUS_MIX))harp_hit=UI_CHORUS_MIX;
  else if(ui_action_inside(px,py,UI_CHORUS_DEPTH))harp_hit=UI_CHORUS_DEPTH;
  else if(ui_action_inside(px,py,UI_CHORUS_RATE))harp_hit=UI_CHORUS_RATE;
  else if(ui_action_inside(px,py,UI_HARP_TONE))harp_hit=UI_HARP_TONE;
 end
endfunction
