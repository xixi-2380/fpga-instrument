// Shared control IDs and exact half-open hit rectangles. Intentionally no
// include guard: these declarations belong ui_inside each importing module.
localparam [5:0] UI_SINE=0,UI_FLUTE=1,UI_REED=2,UI_ECHO=3,UI_ROOM=4,
 UI_TREMOLO=5,UI_FX=6,UI_MODE=7,UI_LESS=8,UI_MORE=9,
 UI_SLOWER=10,UI_FASTER=11,UI_DEFAULTS=12,UI_NONE=63;
function automatic ui_inside(input integer px,py,left,top,width,height);
 begin ui_inside=px>=left && px<left+width && py>=top && py<top+height;end
endfunction
function automatic [5:0] ui_hit(input integer px,py,input [1:0] fx);
 begin
  ui_hit=UI_NONE;
  if(ui_inside(px,py,624,16,152,56))ui_hit=UI_MODE;
  else if(ui_inside(px,py,24,104,176,60))ui_hit=UI_SINE;
  else if(ui_inside(px,py,216,104,176,60))ui_hit=UI_FLUTE;
  else if(ui_inside(px,py,408,104,176,60))ui_hit=UI_REED;
  else if(ui_inside(px,py,608,104,168,60))ui_hit=UI_FX;
  else if(ui_inside(px,py,24,208,240,60))ui_hit=UI_ECHO;
  else if(ui_inside(px,py,280,208,240,60))ui_hit=UI_ROOM;
  else if(ui_inside(px,py,536,208,240,60))ui_hit=UI_TREMOLO;
  else if(ui_inside(px,py,40,328,64,56))ui_hit=UI_LESS;
  else if(ui_inside(px,py,312,328,64,56))ui_hit=UI_MORE;
  else if(fx==2 && ui_inside(px,py,424,328,64,56))ui_hit=UI_SLOWER;
  else if(fx==2 && ui_inside(px,py,696,328,64,56))ui_hit=UI_FASTER;
  else if(ui_inside(px,py,624,408,152,56))ui_hit=UI_DEFAULTS;
 end
endfunction
