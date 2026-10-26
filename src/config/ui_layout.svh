// Shared actions and half-open rectangles for the British UI,800x480.
localparam [5:0] UI_SINE=0,UI_FLUTE=1,UI_REED=2,UI_ECHO=3,UI_ROOM=4,
 UI_TREMOLO=5,UI_FX=6,UI_MODE=7,UI_LESS=8,UI_MORE=9,
 UI_SLOWER=10,UI_FASTER=11,UI_DEFAULTS=12,UI_CELLO=13,UI_PIANO=14,
 UI_GUITAR=15,UI_VIBES=16,UI_PREV=17,UI_NEXT=18,UI_THEME=19,UI_LANGUAGE=20,UI_VIEW=21,UI_NONE=63;
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
  else if(ui_inside(px,py,536,420,112,44))ui_hit=UI_THEME;
  else if(ui_inside(px,py,400,420,120,44))ui_hit=UI_LANGUAGE;
  else if(ui_inside(px,py,264,420,120,44))ui_hit=UI_VIEW;
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
   if(ui_inside(px,py,664,420,116,44))ui_hit=UI_DEFAULTS;
  end
 end
endfunction
