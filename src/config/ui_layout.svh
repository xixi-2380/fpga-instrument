// Shared actions and half-open rectangles for the British UI,800x480.
localparam [5:0] UI_SINE=0,UI_FLUTE=1,UI_REED=2,UI_ECHO=3,UI_ROOM=4,
 UI_TREMOLO=5,UI_FX=6,UI_MODE=7,UI_LESS=8,UI_MORE=9,
 UI_SLOWER=10,UI_FASTER=11,UI_DEFAULTS=12,UI_CELLO=13,UI_PIANO=14,
 UI_GUITAR=15,UI_VIBES=16,UI_PREV=17,UI_NEXT=18,UI_VOLUME_DOWN=19,UI_VOLUME_UP=20,
 UI_OPEN_MORE=21,UI_MORE_BACK=22,UI_SONG_PREV=23,UI_SONG_NEXT=24,UI_SONG_PLAY=25,
 UI_SONG_PAUSE=26,UI_SONG_RESUME=27,UI_SONG_STOP=28,UI_SONG_LOAD=29,UI_SONG_SAVE=30,
 UI_SONG_DELETE=31,UI_FLASH_INFO=32,UI_ULTRA_OPEN=33,UI_ULTRA_TOGGLE=34,UI_SENS_DOWN=35,UI_SENS_UP=36,
 UI_MIN_DOWN=37,UI_MIN_UP=38,UI_MAX_DOWN=39,UI_MAX_UP=40,UI_ULTRA_BACK=41,UI_NONE=63;
function automatic ui_inside(input integer px,py,left,top,width,height);
 begin ui_inside=px>=left && px<left+width && py>=top && py<top+height;end
endfunction
function automatic integer timbre_x(input integer id);
 begin timbre_x=28+(id%2)*124;end
endfunction
function automatic integer timbre_y(input integer id);
 begin timbre_y=132+(id/2)*64;end
endfunction
function automatic [5:0] timbre_action(input integer id);
 begin case(id)
 0:timbre_action=UI_SINE;1:timbre_action=UI_FLUTE;2:timbre_action=UI_REED;
 3:timbre_action=UI_CELLO;4:timbre_action=UI_PIANO;5:timbre_action=UI_GUITAR;
 6:timbre_action=UI_VIBES;default:timbre_action=UI_NONE;endcase end
endfunction
function automatic [5:0] ui_hit(input integer px,py,input [1:0] fx,input menu);
 integer i;
 begin
  ui_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))ui_hit=UI_MODE;
  else if(menu)begin
   for(i=0;i<7;i=i+1)
    if(ui_inside(px,py,timbre_x(i),timbre_y(i),112,52))ui_hit=timbre_action(i);
   if(ui_inside(px,py,152,324,112,52))ui_hit=UI_FX;
   if(ui_inside(px,py,308,124,148,48))ui_hit=UI_ECHO;
   if(ui_inside(px,py,464,124,148,48))ui_hit=UI_ROOM;
   if(ui_inside(px,py,620,124,148,48))ui_hit=UI_TREMOLO;
   if(ui_inside(px,py,308,240,52,48))ui_hit=UI_LESS;
   if(ui_inside(px,py,716,240,52,48))ui_hit=UI_MORE;
   if(fx==2 && ui_inside(px,py,308,344,52,48))ui_hit=UI_SLOWER;
   if(fx==2 && ui_inside(px,py,716,344,52,48))ui_hit=UI_FASTER;
   if(ui_inside(px,py,24,420,44,44))ui_hit=UI_VOLUME_DOWN;
   if(ui_inside(px,py,272,420,44,44))ui_hit=UI_VOLUME_UP;
   if(ui_inside(px,py,664,420,116,44))ui_hit=UI_DEFAULTS;
   if(ui_inside(px,py,550,420,104,44))ui_hit=UI_OPEN_MORE;
   if(ui_inside(px,py,340,420,96,44))ui_hit=UI_ULTRA_OPEN;
   if(ui_inside(px,py,444,420,96,44))ui_hit=6'd42;
  end
 end
endfunction
function automatic [5:0] more_hit(input integer px,py);
 begin
  more_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))more_hit=UI_MORE_BACK;
  if(ui_inside(px,py,24,200,160,40))more_hit=UI_SONG_PREV;
  if(ui_inside(px,py,204,200,160,40))more_hit=UI_SONG_NEXT;
  if(ui_inside(px,py,384,200,160,40))more_hit=UI_SONG_LOAD;
  if(ui_inside(px,py,564,200,160,40))more_hit=UI_SONG_PLAY;
  if(ui_inside(px,py,24,252,160,40))more_hit=UI_SONG_PAUSE;
  if(ui_inside(px,py,204,252,160,40))more_hit=UI_SONG_RESUME;
  if(ui_inside(px,py,384,252,160,40))more_hit=UI_SONG_STOP;
  if(ui_inside(px,py,24,304,160,40))more_hit=UI_SONG_SAVE;
  if(ui_inside(px,py,204,304,160,40))more_hit=UI_SONG_DELETE;
  if(ui_inside(px,py,384,304,160,40))more_hit=UI_FLASH_INFO;
 end
endfunction
function automatic [5:0] ultrasonic_hit(input integer px,py);
 begin
  ultrasonic_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))ultrasonic_hit=UI_ULTRA_BACK;
  else if(ui_inside(px,py,500,100,248,52))ultrasonic_hit=UI_ULTRA_TOGGLE;
  else if(ui_inside(px,py,500,180,64,48))ultrasonic_hit=UI_SENS_DOWN;
  else if(ui_inside(px,py,684,180,64,48))ultrasonic_hit=UI_SENS_UP;
  else if(ui_inside(px,py,500,252,64,48))ultrasonic_hit=UI_MIN_DOWN;
  else if(ui_inside(px,py,684,252,64,48))ultrasonic_hit=UI_MIN_UP;
  else if(ui_inside(px,py,500,324,64,48))ultrasonic_hit=UI_MAX_DOWN;
  else if(ui_inside(px,py,684,324,64,48))ultrasonic_hit=UI_MAX_UP;
 end
endfunction

// PCB diagnostics use only LCD touch; board buttons keep their legacy actions.
localparam [5:0] UI_PCB_OPEN=42,UI_PCB_BACK=43,UI_PCB_TAB0=44,UI_PCB_TAB1=45,
 UI_PCB_TAB2=46,UI_PCB_TAB3=47,UI_PCB_TAB4=48,UI_PCB_PREV=49,UI_PCB_NEXT=50,
 UI_PCB_CH_PREV=51,UI_PCB_CH_NEXT=52,UI_PCB_MINUS=53,UI_PCB_PLUS=54,
 UI_PCB_ITEM=55,UI_PCB_ALL=56,UI_PCB_APPLY=57,UI_PCB_DEFAULT=58,
 UI_PCB_REINIT=59,UI_PCB_FREEZE=60,UI_PCB_CLEAR=61,UI_PCB_DETAIL=62;
function automatic [5:0] pcb_hit(input integer px,py);
 begin
  pcb_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))pcb_hit=UI_PCB_BACK;
  else if(py>=80 && py<120)begin
   if(px>=24 && px<168)pcb_hit=UI_PCB_TAB0;
   else if(px>=176 && px<320)pcb_hit=UI_PCB_TAB1;
   else if(px>=328 && px<472)pcb_hit=UI_PCB_TAB2;
   else if(px>=480 && px<624)pcb_hit=UI_PCB_TAB3;
   else if(px>=632 && px<776)pcb_hit=UI_PCB_TAB4;
  end else if(py>=134 && py<178)begin
   if(px>=24 && px<124)pcb_hit=UI_PCB_PREV;
   else if(px>=132 && px<232)pcb_hit=UI_PCB_NEXT;
   else if(px>=244 && px<344)pcb_hit=UI_PCB_CH_PREV;
   else if(px>=352 && px<452)pcb_hit=UI_PCB_CH_NEXT;
   else if(px>=464 && px<564)pcb_hit=UI_PCB_ITEM;
   else if(px>=576 && px<676)pcb_hit=UI_PCB_DETAIL;
   else if(px>=688 && px<776)pcb_hit=UI_PCB_FREEZE;
  end else if(py>=420 && py<464)begin
   if(px>=24 && px<140)pcb_hit=UI_PCB_APPLY;
   else if(px>=150 && px<266)pcb_hit=UI_PCB_DEFAULT;
   else if(px>=276 && px<392)pcb_hit=UI_PCB_REINIT;
   else if(px>=402 && px<518)pcb_hit=UI_PCB_ALL;
   else if(px>=528 && px<644)pcb_hit=UI_PCB_CLEAR;
   else if(px>=654 && px<710)pcb_hit=UI_PCB_MINUS;
   else if(px>=720 && px<776)pcb_hit=UI_PCB_PLUS;
  end
 end
endfunction

localparam [31:0] PCB_BUILD_ID=32'h26102902;
