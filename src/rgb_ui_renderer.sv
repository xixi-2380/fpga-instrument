`timescale 1ns/1ps
// Four visual themes. Nine registered pixel stages; RGB/DE/HS/VS aligned.
// Atomic1280-bit UI/wave and513-bit FFT snapshots; passive audio analysis.
module rgb_ui_renderer #(parameter integer FRAME_LOCKED_INPUTS=0)(
 input wire pixel_clk,rst,frame_start,status_valid,input wire [1279:0] status_data,
 input wire [10:0] x,y,input wire de_in,hs_in,vs_in,
 output reg [23:0] rgb,output reg de_out,hs_out,vs_out,
 input wire [512:0] analysis_data,input wire analysis_valid,
 input wire [145:0] more_data,input wire [63:0] performance_data);
 reg [10:0] raster_x,raster_y;
 reg raster_de,raster_hs,raster_vs;
 always @(posedge pixel_clk)begin
  if(rst)begin raster_x<=0;raster_y<=0;raster_de<=0;raster_hs<=0;raster_vs<=0;end
  else begin raster_x<=x;raster_y<=y;raster_de<=de_in;raster_hs<=hs_in;raster_vs<=vs_in;end
 end
 `include "config/ui_layout.svh"
 // Palette changes are visual only; appended state bits1209:1208 carry the theme.
 reg [1279:0] state_q;reg [145:0] more_q;reg [63:0] performance_q;
 wire [1279:0] state=FRAME_LOCKED_INPUTS!=0 ? status_data : state_q;
 wire [145:0] more_state=FRAME_LOCKED_INPUTS!=0 ? more_data : more_q;
 wire [63:0] performance_state=FRAME_LOCKED_INPUTS!=0 ? performance_data : performance_q;
 wire [1:0] theme=state[1209:1208];
 wire language_zh=state[1210];
 wire [1:0] view_mode=state[1212:1211];
 reg [511:0] spectrum_state;reg spectrum_ready_state;
 wire [1:0] font_theme=theme==3 ? 0 : theme;
 wire [23:0] BG=theme==0 ? 24'h101214 : theme==1 ? 24'hf7f1e8 : theme==2 ? 24'hfff1d9 : 24'he7e5e3;
 wire [23:0] PANEL=theme==0 ? 24'h191c20 : theme==1 ? 24'heee3d4 : theme==2 ? 24'hfbe3bc : 24'heee8e1;
 wire [23:0] GOLD=theme==0 ? 24'hd6b979 : theme==1 ? 24'h856b57 : theme==2 ? 24'ha3652c : 24'h884652;
 wire [23:0] CREAM=theme==0 ? 24'hf2e6c9 : theme==1 ? 24'h43392f : theme==2 ? 24'h493321 : 24'h332f2d;
 wire [23:0] INK=theme==0 ? 24'h17191b : 24'hfffaf1;
 wire [23:0] DIM=theme==0 ? 24'h9c987f : theme==1 ? 24'h73685c : 24'h7d6148;
 wire [23:0] LINE=theme==0 ? 24'h4b4534 : theme==1 ? 24'hcbbba7 : 24'hd9b889;
 wire [23:0] WINE=theme==0 ? 24'h67333e : 24'hb87e6c;
 wire [23:0] GREEN=theme==0 ? 24'h8bc79b : 24'h3d795f;
 localparam [23:0] RED=24'hef8f85;
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
 wire [15:0] sustain_ms_bcd={2'd0,state[63:62],state[1183:1172]};
 wire [3:0] timbre={state[1207],state[53],state[13:12]};
 wire [1:0] fx=state[22:21];wire menu=state[20],enabled=state[23];
 wire [6:0] percent=fx==0 ? state[30:24] : fx==1 ? state[37:31] : state[44:38];
 wire [4:0] rate={state[61],state[48:45]};
 wire [5:0] voices=state[5:0]>32 ? 6'd32 : state[5:0];
 wire [7:0] peak=state[87:80];
 reg [14:0] peak_scaled;
 reg [6:0] peak_percent;
 reg [7:0] peak_hundreds,peak_tens,peak_units,amount_hundreds,amount_tens,amount_units,voice_tens,voice_units;
 always @(posedge pixel_clk)begin
  if(rst)begin
   peak_scaled<=127;peak_percent<=0;
   peak_hundreds<=32;peak_tens<=32;peak_units<=48;
   amount_hundreds<=32;amount_tens<=32;amount_units<=48;voice_tens<=48;voice_units<=48;
  end else begin
   peak_scaled<=peak*15'd100+15'd127;peak_percent<=peak_scaled/15'd255;
   peak_hundreds<=peak_percent==100 ? 8'd49 : 8'd32;
   peak_tens<=peak_percent>=10 ? 8'd48+(peak_percent/7'd10)%7'd10 : 8'd32;
   peak_units<=8'd48+peak_percent%7'd10;
   amount_hundreds<=percent==100 ? 8'd49 : 8'd32;
   amount_tens<=percent>=10 ? 8'd48+(percent/7'd10)%7'd10 : 8'd32;
   amount_units<=8'd48+percent%7'd10;
   voice_tens<=8'd48+voices/6'd10;voice_units<=8'd48+voices%6'd10;
  end
 end
 reg [23:0] base,fg;
 reg [319:0] text;
 reg [5:0] len;reg [10:0] tx,ty;
 integer dx,dy,ci,px,py,i,k,left,top;reg [5:0] note_index;
 reg [5:0] spectrum_bin;reg [7:0] spectrum_level;
 reg [6:0] bin; integer point_y,previous_y,minimum_y,maximum_y,pc;
 reg [7:0] ch;reg [14:0] font_addr;reg [3:0] font_bit;
 reg alpha_font,wide_text;
 reg text_ink;
 reg [15:0] font_rom[0:32767],font_row;
 initial $readmemh("src/rom/theme_font.hex",font_rom);
 `include "config/ui_language.svh"
 reg [25:0] animation_phase;
 reg [3:0] animation_frame;
 wire [23:0] art_pixel;
 ui_theme_art artwork(pixel_clk,theme,animation_frame,raster_x,raster_y,art_pixel,menu);
 wire xy_region=ordinary_page && view_mode==2 && !state[19] && raster_de &&
  (theme==3 ? (raster_x>=680 && raster_x<744 && raster_y>=172 && raster_y<236) :
              (raster_x>=376 && raster_x<504 && raster_y>=170 && raster_y<298));
 wire [5:0] xy_x=theme==3 ? raster_x-11'd680 : (raster_x-11'd376)>>1;
 wire [5:0] xy_y=theme==3 ? raster_y-11'd172 : (raster_y-11'd170)>>1;
 wire xy_pixel,xy_ready;
 lissajous_plot phase_plot(pixel_clk,rst,frame_start,
  frame_start && status_valid && !status_data[20] && !performance_data[0] && !status_data[1228] && status_data[1212:1211]==2,
  status_data[1111:88],xy_region,xy_x,xy_y,xy_pixel,xy_ready);
 // Limit color arithmetic to ten bits, rather than signed 32-bit division.
 function automatic [7:0] blend_channel(input [7:0] a,b,input [1:0] w);
  reg [9:0] sum;
  begin
   case(w)
    0:blend_channel=a;
    3:blend_channel=b;
    default:begin
     sum=w==1 ? ({2'b0,a}<<1)+{2'b0,b}+10'd1
              : {2'b0,a}+({2'b0,b}<<1)+10'd1;
     blend_channel=sum/10'd3;
    end
   endcase
  end
 endfunction
 function automatic [23:0] mix_color(input [23:0] a,b,input [1:0] weight);
  begin mix_color={blend_channel(a[23:16],b[23:16],weight),
   blend_channel(a[15:8],b[15:8],weight),blend_channel(a[7:0],b[7:0],weight)};end
 endfunction
 function automatic [7:0] digit(input integer value);
  begin digit=8'd48+value;end
 endfunction
 function automatic [325:0] timbre_word(input [3:0] id);
  begin timbre_word=ui_word({3'd0,id},language_zh);end
 endfunction
 function automatic [6:0] action_word(input [6:0] a,input menu_value,input [2:0] effect_flags,input [1:0] effect_id,input sensor_value,input [63:0] performance_value);
  begin case(a)
   UI_MODE:action_word=menu_value ? TXT_RETURN : TXT_SETTINGS;
   UI_MORE_BACK,UI_ULTRA_BACK,UI_SENS_BACK,UI_HARP_BACK:action_word=TXT_RETURN;
   UI_HARP_OPEN:action_word=TXT_HARP;
   UI_THEME:action_word=TXT_THEME;UI_VIEW:action_word=TXT_VIEW;UI_EGG:action_word=TXT_EGG;
   UI_ECHO:action_word=TXT_SUSTAIN;UI_ROOM:action_word=TXT_ROOM;UI_TREMOLO:action_word=TXT_TREMOLO;
   UI_FX:action_word=effect_flags[effect_id] ? TXT_ON : TXT_OFF;
   UI_DEFAULTS,UI_SENS_DEFAULT:action_word=TXT_DEFAULT;
   UI_TONE_PAGE:action_word=TXT_NEXT_PAGE;
   UI_OPEN_MORE:action_word=TXT_LIBRARY;UI_ULTRA_OPEN:action_word=TXT_ULTRA_PITCH;UI_SENSITIVITY:action_word=TXT_SENSITIVITY;
   UI_SONG_PREV:action_word=TXT_PREV;UI_SONG_NEXT:action_word=TXT_NEXT;UI_SONG_LOAD:action_word=TXT_LOAD;UI_SONG_PLAY:action_word=TXT_PLAY;
   UI_SONG_PAUSE:action_word=TXT_PAUSE;UI_SONG_RESUME:action_word=TXT_RESUME;UI_SONG_STOP:action_word=TXT_STOP;
   UI_SONG_SAVE:action_word=TXT_SAVE;UI_SONG_DELETE:action_word=TXT_DELETE;UI_FLASH_INFO:action_word=TXT_FLASH_INFO;
   UI_ULTRA_TOGGLE:action_word=sensor_value ? TXT_ON : TXT_OFF;
   UI_SENS_APPLY:action_word=TXT_APPLY;
   UI_CHORUS:action_word=performance_value[1] ? TXT_ON : TXT_OFF;
   UI_CHORUS_DEPTH:action_word=performance_value[6:5]==0 ? TXT_LOW : performance_value[6:5]==1 ? TXT_MID : TXT_HIGH;
   UI_CHORUS_RATE:action_word=performance_value[8:7]==0 ? TXT_SLOW : performance_value[8:7]==1 ? TXT_MID : TXT_FAST;
   UI_HARP_TONE:action_word=performance_value[33] ? TXT_PANEL_TIMBRE : TXT_FIXED_GUITAR;
   default:action_word=TXT_RETURN;
  endcase end
 endfunction
 // Rectangles are static and disjoint within each selected page. Decode all
 // hits in parallel; the pixel path never traverses action/word/length/centering.
 // Labels and centered positions depend only on the frame state, not raster.
 localparam integer BUTTON_COUNT=61,BUTTON_LEAVES=64,BUTTON_BITS=397;
 wire button_sens=sensitivity_page;
 wire button_sensor=!sensitivity_page && sensor_page;
 wire button_library=!sensitivity_page && !sensor_page && library_page;
 wire button_harp=!sensitivity_page && !sensor_page && !library_page && performance_page;
 wire button_main=!sensitivity_page && !sensor_page && !library_page && !performance_page;
 wire button_menu=button_main && menu;
 wire [BUTTON_COUNT-1:0] button_hits;
 wire [BUTTON_BITS-1:0] button_tree[1:2*BUTTON_LEAVES-1];
 wire [6:0] button_action_tree[1:2*BUTTON_LEAVES-1];
 wire button_any=|button_hits;
 if(1)begin: button_0
  localparam [6:0] ACTION=UI_VIEW;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(1) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[0]=hit;
  assign button_tree[BUTTON_LEAVES+0]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+0]={7{hit}} & ACTION;
 end
 if(1)begin: button_1
  localparam [6:0] ACTION=UI_LANGUAGE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(1) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[1]=hit;
  assign button_tree[BUTTON_LEAVES+1]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+1]={7{hit}} & ACTION;
 end
 if(1)begin: button_2
  localparam [6:0] ACTION=UI_THEME;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(1) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[2]=hit;
  assign button_tree[BUTTON_LEAVES+2]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+2]={7{hit}} & ACTION;
 end
 if(1)begin: button_3
  localparam [6:0] ACTION=UI_EGG;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(1) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[3]=hit;
  assign button_tree[BUTTON_LEAVES+3]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+3]={7{hit}} & ACTION;
 end
 if(1)begin: button_4
  localparam [6:0] ACTION=UI_SENS_BACK;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sens) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[4]=hit;
  assign button_tree[BUTTON_LEAVES+4]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+4]={7{hit}} & ACTION;
 end
 if(1)begin: button_5
  localparam [6:0] ACTION=UI_ULTRA_BACK;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sensor) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[5]=hit;
  assign button_tree[BUTTON_LEAVES+5]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+5]={7{hit}} & ACTION;
 end
 if(1)begin: button_6
  localparam [6:0] ACTION=UI_MORE_BACK;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[6]=hit;
  assign button_tree[BUTTON_LEAVES+6]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+6]={7{hit}} & ACTION;
 end
 if(1)begin: button_7
  localparam [6:0] ACTION=UI_HARP_BACK;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_harp) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[7]=hit;
  assign button_tree[BUTTON_LEAVES+7]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+7]={7{hit}} & ACTION;
 end
 if(1)begin: button_8
  localparam [6:0] ACTION=UI_MODE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_main) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[8]=hit;
  assign button_tree[BUTTON_LEAVES+8]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+8]={7{hit}} & ACTION;
 end
 if(1)begin: button_9
  localparam [6:0] ACTION=UI_HARP_OPEN;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_main && !menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[9]=hit;
  assign button_tree[BUTTON_LEAVES+9]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+9]={7{hit}} & ACTION;
 end
 if(1)begin: button_10
  localparam [6:0] ACTION=64;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[10]=hit;
  assign button_tree[BUTTON_LEAVES+10]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+10]={7{hit}} & ACTION;
 end
 if(1)begin: button_11
  localparam [6:0] ACTION=65;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[11]=hit;
  assign button_tree[BUTTON_LEAVES+11]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+11]={7{hit}} & ACTION;
 end
 if(1)begin: button_12
  localparam [6:0] ACTION=66;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[12]=hit;
  assign button_tree[BUTTON_LEAVES+12]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+12]={7{hit}} & ACTION;
 end
 if(1)begin: button_13
  localparam [6:0] ACTION=67;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[13]=hit;
  assign button_tree[BUTTON_LEAVES+13]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+13]={7{hit}} & ACTION;
 end
 if(1)begin: button_14
  localparam [6:0] ACTION=68;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[14]=hit;
  assign button_tree[BUTTON_LEAVES+14]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+14]={7{hit}} & ACTION;
 end
 if(1)begin: button_15
  localparam [6:0] ACTION=69;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[15]=hit;
  assign button_tree[BUTTON_LEAVES+15]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+15]={7{hit}} & ACTION;
 end
 if(1)begin: button_16
  localparam [6:0] ACTION=70;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[16]=hit;
  assign button_tree[BUTTON_LEAVES+16]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+16]={7{hit}} & ACTION;
 end
 if(1)begin: button_17
  localparam [6:0] ACTION=71;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[17]=hit;
  assign button_tree[BUTTON_LEAVES+17]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+17]={7{hit}} & ACTION;
 end
 if(1)begin: button_18
  localparam [6:0] ACTION=UI_TONE_PAGE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[18]=hit;
  assign button_tree[BUTTON_LEAVES+18]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+18]={7{hit}} & ACTION;
 end
 if(1)begin: button_19
  localparam [6:0] ACTION=UI_ECHO;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[19]=hit;
  assign button_tree[BUTTON_LEAVES+19]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+19]={7{hit}} & ACTION;
 end
 if(1)begin: button_20
  localparam [6:0] ACTION=UI_ROOM;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[20]=hit;
  assign button_tree[BUTTON_LEAVES+20]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+20]={7{hit}} & ACTION;
 end
 if(1)begin: button_21
  localparam [6:0] ACTION=UI_TREMOLO;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[21]=hit;
  assign button_tree[BUTTON_LEAVES+21]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+21]={7{hit}} & ACTION;
 end
 if(1)begin: button_22
  localparam [6:0] ACTION=UI_FX;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[22]=hit;
  assign button_tree[BUTTON_LEAVES+22]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+22]={7{hit}} & ACTION;
 end
 if(1)begin: button_23
  localparam [6:0] ACTION=UI_LESS;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[23]=hit;
  assign button_tree[BUTTON_LEAVES+23]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+23]={7{hit}} & ACTION;
 end
 if(1)begin: button_24
  localparam [6:0] ACTION=UI_MORE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[24]=hit;
  assign button_tree[BUTTON_LEAVES+24]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+24]={7{hit}} & ACTION;
 end
 if(1)begin: button_25
  localparam [6:0] ACTION=UI_SLOWER;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu && fx==2 && !ui_action_inside(integer'(raster_x),integer'(raster_y),UI_OPEN_MORE)) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[25]=hit;
  assign button_tree[BUTTON_LEAVES+25]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+25]={7{hit}} & ACTION;
 end
 if(1)begin: button_26
  localparam [6:0] ACTION=UI_FASTER;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu && fx==2 && !ui_action_inside(integer'(raster_x),integer'(raster_y),UI_SENSITIVITY)) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[26]=hit;
  assign button_tree[BUTTON_LEAVES+26]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+26]={7{hit}} & ACTION;
 end
 if(1)begin: button_27
  localparam [6:0] ACTION=UI_VOLUME_DOWN;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[27]=hit;
  assign button_tree[BUTTON_LEAVES+27]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+27]={7{hit}} & ACTION;
 end
 if(1)begin: button_28
  localparam [6:0] ACTION=UI_VOLUME_UP;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[28]=hit;
  assign button_tree[BUTTON_LEAVES+28]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+28]={7{hit}} & ACTION;
 end
 if(1)begin: button_29
  localparam [6:0] ACTION=UI_OPEN_MORE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[29]=hit;
  assign button_tree[BUTTON_LEAVES+29]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+29]={7{hit}} & ACTION;
 end
 if(1)begin: button_30
  localparam [6:0] ACTION=UI_ULTRA_OPEN;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[30]=hit;
  assign button_tree[BUTTON_LEAVES+30]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+30]={7{hit}} & ACTION;
 end
 if(1)begin: button_31
  localparam [6:0] ACTION=UI_SENSITIVITY;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[31]=hit;
  assign button_tree[BUTTON_LEAVES+31]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+31]={7{hit}} & ACTION;
 end
 if(1)begin: button_32
  localparam [6:0] ACTION=UI_DEFAULTS;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_menu) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[32]=hit;
  assign button_tree[BUTTON_LEAVES+32]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+32]={7{hit}} & ACTION;
 end
 if(1)begin: button_33
  localparam [6:0] ACTION=UI_SONG_PREV;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[33]=hit;
  assign button_tree[BUTTON_LEAVES+33]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+33]={7{hit}} & ACTION;
 end
 if(1)begin: button_34
  localparam [6:0] ACTION=UI_SONG_NEXT;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[34]=hit;
  assign button_tree[BUTTON_LEAVES+34]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+34]={7{hit}} & ACTION;
 end
 if(1)begin: button_35
  localparam [6:0] ACTION=UI_SONG_LOAD;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[35]=hit;
  assign button_tree[BUTTON_LEAVES+35]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+35]={7{hit}} & ACTION;
 end
 if(1)begin: button_36
  localparam [6:0] ACTION=UI_SONG_PLAY;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[36]=hit;
  assign button_tree[BUTTON_LEAVES+36]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+36]={7{hit}} & ACTION;
 end
 if(1)begin: button_37
  localparam [6:0] ACTION=UI_SONG_PAUSE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[37]=hit;
  assign button_tree[BUTTON_LEAVES+37]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+37]={7{hit}} & ACTION;
 end
 if(1)begin: button_38
  localparam [6:0] ACTION=UI_SONG_RESUME;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[38]=hit;
  assign button_tree[BUTTON_LEAVES+38]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+38]={7{hit}} & ACTION;
 end
 if(1)begin: button_39
  localparam [6:0] ACTION=UI_SONG_STOP;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[39]=hit;
  assign button_tree[BUTTON_LEAVES+39]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+39]={7{hit}} & ACTION;
 end
 if(1)begin: button_40
  localparam [6:0] ACTION=UI_SONG_SAVE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[40]=hit;
  assign button_tree[BUTTON_LEAVES+40]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+40]={7{hit}} & ACTION;
 end
 if(1)begin: button_41
  localparam [6:0] ACTION=UI_SONG_DELETE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[41]=hit;
  assign button_tree[BUTTON_LEAVES+41]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+41]={7{hit}} & ACTION;
 end
 if(1)begin: button_42
  localparam [6:0] ACTION=UI_FLASH_INFO;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_library) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[42]=hit;
  assign button_tree[BUTTON_LEAVES+42]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+42]={7{hit}} & ACTION;
 end
 if(1)begin: button_43
  localparam [6:0] ACTION=UI_ULTRA_TOGGLE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sensor) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[43]=hit;
  assign button_tree[BUTTON_LEAVES+43]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+43]={7{hit}} & ACTION;
 end
 if(1)begin: button_44
  localparam [6:0] ACTION=UI_SENS_DOWN;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sensor) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[44]=hit;
  assign button_tree[BUTTON_LEAVES+44]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+44]={7{hit}} & ACTION;
 end
 if(1)begin: button_45
  localparam [6:0] ACTION=UI_SENS_UP;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sensor) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[45]=hit;
  assign button_tree[BUTTON_LEAVES+45]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+45]={7{hit}} & ACTION;
 end
 if(1)begin: button_46
  localparam [6:0] ACTION=UI_MIN_DOWN;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sensor) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[46]=hit;
  assign button_tree[BUTTON_LEAVES+46]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+46]={7{hit}} & ACTION;
 end
 if(1)begin: button_47
  localparam [6:0] ACTION=UI_MIN_UP;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sensor) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[47]=hit;
  assign button_tree[BUTTON_LEAVES+47]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+47]={7{hit}} & ACTION;
 end
 if(1)begin: button_48
  localparam [6:0] ACTION=UI_MAX_DOWN;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sensor) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[48]=hit;
  assign button_tree[BUTTON_LEAVES+48]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+48]={7{hit}} & ACTION;
 end
 if(1)begin: button_49
  localparam [6:0] ACTION=UI_MAX_UP;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sensor) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[49]=hit;
  assign button_tree[BUTTON_LEAVES+49]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+49]={7{hit}} & ACTION;
 end
 if(1)begin: button_50
  localparam [6:0] ACTION=UI_GSR_DOWN;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sens) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[50]=hit;
  assign button_tree[BUTTON_LEAVES+50]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+50]={7{hit}} & ACTION;
 end
 if(1)begin: button_51
  localparam [6:0] ACTION=UI_GSR_UP;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sens) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[51]=hit;
  assign button_tree[BUTTON_LEAVES+51]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+51]={7{hit}} & ACTION;
 end
 if(1)begin: button_52
  localparam [6:0] ACTION=UI_KOR_DOWN;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sens) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[52]=hit;
  assign button_tree[BUTTON_LEAVES+52]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+52]={7{hit}} & ACTION;
 end
 if(1)begin: button_53
  localparam [6:0] ACTION=UI_KOR_UP;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sens) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[53]=hit;
  assign button_tree[BUTTON_LEAVES+53]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+53]={7{hit}} & ACTION;
 end
 if(1)begin: button_54
  localparam [6:0] ACTION=UI_SENS_APPLY;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sens) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[54]=hit;
  assign button_tree[BUTTON_LEAVES+54]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+54]={7{hit}} & ACTION;
 end
 if(1)begin: button_55
  localparam [6:0] ACTION=UI_SENS_DEFAULT;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_sens) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[55]=hit;
  assign button_tree[BUTTON_LEAVES+55]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+55]={7{hit}} & ACTION;
 end
 if(1)begin: button_56
  localparam [6:0] ACTION=UI_CHORUS;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_harp) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[56]=hit;
  assign button_tree[BUTTON_LEAVES+56]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+56]={7{hit}} & ACTION;
 end
 if(1)begin: button_57
  localparam [6:0] ACTION=UI_CHORUS_MIX;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_harp) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[57]=hit;
  assign button_tree[BUTTON_LEAVES+57]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+57]={7{hit}} & ACTION;
 end
 if(1)begin: button_58
  localparam [6:0] ACTION=UI_CHORUS_DEPTH;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_harp) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[58]=hit;
  assign button_tree[BUTTON_LEAVES+58]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+58]={7{hit}} & ACTION;
 end
 if(1)begin: button_59
  localparam [6:0] ACTION=UI_CHORUS_RATE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_harp) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[59]=hit;
  assign button_tree[BUTTON_LEAVES+59]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+59]={7{hit}} & ACTION;
 end
 if(1)begin: button_60
  localparam [6:0] ACTION=UI_HARP_TONE;
  localparam [43:0] RECT=ui_rect(ACTION);
  localparam [10:0] L=RECT[43:33],T=RECT[32:22],W=RECT[21:11],H=RECT[10:0];
  wire hit=(button_harp) && raster_x>=L && raster_x<L+W && raster_y>=T && raster_y<T+H;
  wire border=raster_x<L+1 || raster_x>=L+W-1 || raster_y<T+1 || raster_y>=T+H-1;
  wire selected=(ACTION>=64 && ACTION<72 && timbre[2:0]==ACTION-64) ||
   (ACTION==UI_ECHO && fx==0)||(ACTION==UI_ROOM && fx==1)||(ACTION==UI_TREMOLO && fx==2)||
   (ACTION==UI_EGG && theme==3)||(ACTION==UI_CHORUS && performance_state[1]);
  wire [23:0] fill=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
  wire [23:0] edge_color=selected ? GOLD : LINE;
  reg [319:0] label_text;reg [5:0] label_len;reg wide;
  reg [10:0] label_x;
  always @*begin
   wide=language_zh;{label_len,label_text}=ui_word(action_word(ACTION,menu,effect_bits,fx,sensor_enabled,performance_state),language_zh);
   if(ACTION>=64 && ACTION<72){label_len,label_text}=timbre_word({timbre[3],ACTION[2:0]});
   if(ACTION==UI_LANGUAGE)begin wide=!language_zh;if(language_zh)begin label_text="ENGLISH";label_len=7;end else {label_len,label_text}=ui_word(TXT_CHINESE,1'b1);end
   if(ACTION==UI_CHORUS_MIX)begin wide=0;case(performance_state[4:2])1:label_text="13%";2:label_text="25%";3:label_text="38%";default:label_text="50%";endcase label_len=3;end
   if(ACTION==UI_LESS || ACTION==UI_SLOWER || ACTION==UI_VOLUME_DOWN || ACTION==UI_SENS_DOWN || ACTION==UI_MIN_DOWN || ACTION==UI_MAX_DOWN || ACTION==UI_GSR_DOWN || ACTION==UI_KOR_DOWN)begin wide=0;label_text="-";label_len=1;end
   if(ACTION==UI_MORE || ACTION==UI_FASTER || ACTION==UI_VOLUME_UP || ACTION==UI_SENS_UP || ACTION==UI_MIN_UP || ACTION==UI_MAX_UP || ACTION==UI_GSR_UP || ACTION==UI_KOR_UP)begin wide=0;label_text="+";label_len=1;end
   label_x=integer'(L)+(integer'(W)-integer'(label_len)*(wide?16:10))/2;
  end
  assign button_hits[60]=hit;
  assign button_tree[BUTTON_LEAVES+60]={BUTTON_BITS{hit}} & {border ? edge_color : fill,selected ? INK : GOLD,label_text,label_len,label_x,11'(T+(H-16)/2),wide};
  assign button_action_tree[BUTTON_LEAVES+60]={7{hit}} & ACTION;
 end
 for(genvar p=BUTTON_COUNT;p<BUTTON_LEAVES;p=p+1)begin: button_unused
  assign button_tree[BUTTON_LEAVES+p]=0;assign button_action_tree[BUTTON_LEAVES+p]=0;
 end
 for(genvar p=1;p<BUTTON_LEAVES;p=p+1)begin: button_reduce
  assign button_tree[p]=button_tree[2*p]|button_tree[2*p+1];
  assign button_action_tree[p]=button_action_tree[2*p]|button_action_tree[2*p+1];
 end
 wire [6:0] hit_action=button_any ? button_action_tree[1] : UI_NONE;
 function [23:0] card(input integer xx,yy,l,t,w,h,input selected);
  begin
   card=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
   if(xx<l+1 || xx>=l+w-1 || yy<t+1 || yy>=t+h-1)card=selected ? GOLD : LINE;
  end
 endfunction
 always @*begin
  px=integer'(raster_x);py=integer'(raster_y);base=BG;fg=CREAM;text=0;len=0;tx=0;ty=0;
  wide_text=language_zh;dx=0;dy=0;ci=0;i=0;k=0;left=0;top=0;note_index=0;pc=0;
  spectrum_bin=0;spectrum_level=0;bin=0;point_y=234;previous_y=234;minimum_y=234;maximum_y=234;
  ch=0;font_addr=0;font_bit=0;text_ink=0;alpha_font=0;
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
  end else if(theme==3)begin
   // Easter performance page: a clear portrait at left, live monitors at
   // right. No waveform, card or held-note tile may cover the woman's face.
   if(ui_inside(px,py,464,128,316,124) || ui_inside(px,py,464,260,316,70) ||
      ui_inside(px,py,464,338,316,68))base=PANEL;
   if(py>=94 && py<114)begin
    ty=96;fg=GOLD;
    if(px<296)begin {len,text}=timbre_word(timbre);tx=24;end
    else if(px<560)begin {len,text}=enabled ? (fx==0 ? ui_word(TXT_ON,language_zh) : fx==1 ? ui_word(TXT_ON,language_zh) : ui_word(TXT_ON,language_zh)) : ui_word(TXT_OFF,language_zh);tx=310;end
    else begin {len,text}=state[14] ? ui_word(TXT_AUTO_SCORE,language_zh) : ui_word(TXT_LIVE_KEYS,language_zh);tx=620;fg=DIM;end
   end
   if(view_mode==0 && ui_inside(px,py,488,164,256,80))begin
    if((px-488)%32==0 || (py-164)%20==0)base=24'hd4d0cc;
    bin=(px-488)>>1;
    point_y=204-($signed(state[88+bin*8+:8])>>>2);
    previous_y=bin>0 ? 204-($signed(state[88+(bin-1)*8+:8])>>>2) : point_y;
    minimum_y=point_y<previous_y ? point_y : previous_y;
    maximum_y=point_y>previous_y ? point_y : previous_y;
    if(py==point_y || ((px-488)%2==0 && py>=minimum_y && py<=maximum_y))base=GOLD;
   end
   if(py>=138 && py<158 && px>=480)begin {len,text}=ui_word(view_mode==0?TXT_WAVEFORM:view_mode==1?(spectrum_ready_state?TXT_SPECTRUM:TXT_FFT_WAIT):TXT_LISSAJOUS,language_zh);tx=488;ty=140;fg=DIM;end
   if(py>=268 && py<288 && px>=480)begin {len,text}=ui_word(TXT_LEVEL,language_zh);tx=488;ty=270;fg=DIM;end
   if(ui_inside(px,py,488,298,256,10))base=(px-488)<integer'(peak) ? GOLD : BG;
   if(py>=268 && py<288 && px>=640)begin
    pc=peak_percent;
    text=language_zh ? {peak_hundreds,peak_tens,peak_units,ZH_PEAK} : {peak_hundreds,peak_tens,peak_units,"% PEAK"};len=language_zh ? 6 : 9;tx=668;ty=270;fg=DIM;
   end
   if(py>=342 && py<402 && px>=480 && px<768)begin
    note_index=(py<362 ? 0 : py<382 ? 12 : 24);left=480;top=py<362 ? 342 : py<382 ? 362 : 382;
    for(integer tile=0;tile<12;tile=tile+1)if(px>=480+tile*24 && px<504+tile*24)begin note_index=note_index+tile;left=480+tile*24;end
    if(px<left+22 && py<top+18)begin base=piano_notes[note_index] ? GOLD : BG;end
   end
  end else begin
   if(ui_inside(px,py,20,128,552,196) || ui_inside(px,py,588,128,192,196) || ui_inside(px,py,20,338,760,68))base=PANEL;
   if(py>=94 && py<114)begin
    ty=96;fg=GOLD;
    if(px<296)begin {len,text}=timbre_word(timbre);tx=24;end
    else if(px<560)begin {len,text}=enabled ? (fx==0 ? ui_word(TXT_ON,language_zh) : fx==1 ? ui_word(TXT_ON,language_zh) : ui_word(TXT_ON,language_zh)) : ui_word(TXT_OFF,language_zh);tx=310;end
    else begin {len,text}=state[14] ? ui_word(TXT_AUTO_SCORE,language_zh) : ui_word(TXT_LIVE_KEYS,language_zh);tx=620;fg=DIM;end
   end
   if(view_mode==0 && ui_inside(px,py,32,164,512,140))begin
    if((px-32)%64==0 || (py-164)%35==0)base=24'h292c2c;
    bin=(px-32)>>2;
    point_y=234-($signed(state[88+bin*8+:8])>>>1);
    if(bin>0)previous_y=234-($signed(state[88+(bin-1)*8+:8])>>>1);else previous_y=point_y;
    minimum_y=point_y<previous_y ? point_y : previous_y;
    maximum_y=point_y>previous_y ? point_y : previous_y;
    if(py==point_y || ((px-32)%4==0 && py>=minimum_y && py<=maximum_y))base=GOLD;
   end
   if(py>=138 && py<158)begin
    ty=140;fg=DIM;
    if(px<390)begin {len,text}=ui_word(view_mode==0?TXT_WAVEFORM:view_mode==1?(spectrum_ready_state?TXT_SPECTRUM:TXT_FFT_WAIT):TXT_LISSAJOUS,language_zh);tx=32;end
    else if(px<572)begin {len,text}=ui_word(view_mode==1?TXT_SPECTRUM:TXT_WAVEFORM,language_zh);tx=440;end
    else begin {len,text}=ui_word(TXT_LEVEL,language_zh);tx=608;end
   end
   if(px>=608 && px<760 && py>=200 && py<224)base=(px-608)<(integer'(peak)*152>>8) ? (peak>=248 ? RED : GOLD) : BG;
   if(py>=244 && py<264 && px>=608)begin
    pc=peak_percent;
    text=language_zh ? {peak_hundreds,peak_tens,peak_units,ZH_PEAK} : {peak_hundreds,peak_tens,peak_units,"% PEAK"};len=language_zh ? 6 : 9;tx=608;ty=246;fg=DIM;
   end
   if(py>=280 && py<300 && px>=608)begin {len,text}=peak>=248 ? ui_word(TXT_LEVEL,language_zh) : ui_word(TXT_READY,language_zh);tx=608;ty=282;fg=peak>=248 ? RED : DIM;end
   if(py>=346 && py<400 && px>=32 && px<764)begin
    note_index=py<364 ? 0 : py<382 ? 12 : 24;left=32;top=py<364 ? 346 : py<382 ? 364 : 382;
    for(integer tile=0;tile<12;tile=tile+1)if(px>=32+tile*61 && px<93+tile*61)begin note_index=note_index+tile;left=32+tile*61;end
    if(px<left+57 && py<top+16)begin
     base=piano_notes[note_index] ? GOLD : BG;fg=piano_notes[note_index] ? INK : DIM;
     case(note_index%12)0,1:ch="C";2,3:ch="D";4:ch="E";5,6:ch="F";7,8:ch="G";9,10:ch="A";default:ch="B";endcase
     wide_text=0;text={ch,(note_index%12==1 || note_index%12==3 || note_index%12==6 || note_index%12==8 || note_index%12==10)?8'd35:8'd32,digit(note_index/12+4)};
     len=3;tx=left+7;ty=top;
    end
   end
  end
  if(ordinary_page && view_mode==1)begin
   left=theme==3 ? 488 : 32;top=164;
   if(ui_inside(px,py,left,top,theme==3 ? 256 : 512,theme==3 ? 80 : 140))begin
    if((px-left)%(theme==3 ? 32 : 64)==0 || (py-top)%20==0)base=LINE;
    spectrum_bin=(px-left)>>(theme==3 ? 2 : 3);spectrum_level=spectrum_state[spectrum_bin*8+:8];
    if(spectrum_ready_state && (px-left)%(theme==3 ? 4 : 8)<(theme==3 ? 3 : 6) &&
       py<(theme==3 ? 244 : 300) && py>=(theme==3 ? 244-(spectrum_level>>1) : 300-spectrum_level))base=GOLD;
   end
   if(theme==3 && py>=138 && py<158 && px>=648)begin {len,text}=ui_word(TXT_SPECTRUM,language_zh);tx=648;ty=140;fg=DIM;end
   if(theme!=3 && py>=306 && py<322 && px>=32 && px<572)begin
    wide_text=0;fg=DIM;ty=306;
    if(px<56)begin text="0";len=1;tx=32;end
    else if(px<168)begin {len,text}=ui_word(TXT_SPECTRUM,language_zh);tx=64;wide_text=language_zh;end
    else if(px<264)begin text="500";len=3;tx=188;end
    else if(px<360)begin text="1K";len=2;tx=300;end
    else if(px<470)begin text="4K";len=2;tx=394;end
    else begin text="24K";len=3;tx=514;end
   end
  end
  if(ordinary_page && view_mode==2)begin
   left=theme==3 ? 680 : 376;top=theme==3 ? 172 : 170;
   if(ui_inside(px,py,left,top,theme==3 ? 64 : 128,theme==3 ? 64 : 128))begin
    fg=GOLD;if((px-left)%(theme==3 ? 8 : 16)==0 || (py-top)%(theme==3 ? 8 : 16)==0)base=LINE;
   end
   if(px<(theme==3 ? 664 : 280) && px>=(theme==3 ? 488 : 32) && py>=180 && py<196)begin
    {len,text}=ui_word(TXT_MONO_DELAY_XY,language_zh);tx=theme==3 ? 488 : 32;ty=180;fg=DIM;
   end
   if(px<(theme==3 ? 664 : 280) && px>=(theme==3 ? 488 : 32) && py>=212 && py<228)begin
    {len,text}=ui_word(TXT_16_SAMPLE_DELAY,language_zh);tx=theme==3 ? 488 : 32;ty=212;fg=DIM;
   end
  end

  if(ordinary_page && px>=648 && py>=420 && py<464)begin
   wide_text=0;fg=DIM;tx=648;
   if(py<440)begin text={"LAT ",digit(state[1131:1128]),digit(state[1127:1124]),digit(state[1123:1120]),".",digit(state[1119:1116]),digit(state[1115:1112])};len=10;ty=422;if(!state[1132])begin text="LAT --";len=6;end end
   else begin text={"VOICES ",voice_tens,voice_units,"/32"};len=12;ty=446;end
  end
  // Preserve original overlay priority with a single parallel button result.
  if(button_any){base,fg,text,len,tx,ty,wide_text}=button_tree[1];
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
 // S1 layout; S2 relative position; S3 cell; S4 character; S5 address;
 // S6 synchronous ROM; S7 background/alpha; S8 final text blend.
 localparam integer PIXEL_LATENCY=9;
 reg [319:0] text_s1,text_s2,text_s3;
 reg [5:0] len_s1,len_s2,len_s3;
 reg [10:0] x_s1,y_s1,tx_s1,ty_s1;
 reg signed [11:0] dx_s2,dy_s2;
 reg [5:0] cell_s3;
 reg [3:0] row_s3,normal_bit_s3,row_s4,normal_bit_s4,bit_s5,bit_s6;
 reg normal_ink_s3,normal_ink_s4,ink_s5,ink_s6;
 reg [7:0] char_s4;
 reg [14:0] addr_s5;
 reg [23:0] bases[0:5],foregrounds[0:5],arts[1:5];
 reg [14:0] direct_addr[0:3];reg [3:0] direct_bit[0:3];
 reg [3:0] direct_ink,direct_alpha;
 reg [1:0] fonts[0:3];
 reg [14:0] zh_bases[0:3];
 wire [14:0] zh_style_base=font_theme==0 ? ZH_GLYPH_BASE : font_theme==1 ? ZH_GLYPH_BASE+ZH_STYLE_WORDS : ZH_GLYPH_BASE+2*ZH_STYLE_WORDS;
 wire [7:0] zh_index=char_s4>=128 ? {1'b0,char_s4[6:0]} : char_s4<32 ? 8'd127+{3'd0,char_s4[4:0]} : 8'd159+{3'd0,char_s4[4:0]};
 wire chinese_char=char_s4<32 || char_s4>=96;
 reg [3:0] chinese;
 reg [5:0] background,panels,blank,tests,des,hss,vss;
 reg [1:0] themes[0:5];
 reg [23:0] bg_s1,panel_s1;
 reg alpha_s5,alpha_s6;
 reg [23:0] resolved_s7,fg_s7;
 reg [1:0] alpha_s7;
 reg ink_s7,de_s7,hs_s7,vs_s7;
 // Unconditional synchronous ROM read preserves block-memory inference.
 always @(posedge pixel_clk)font_row<=font_rom[addr_s5];
 wire [5:0] glyph_index=len_s3-6'd1-cell_s3;
 wire normal_valid=dx_s2>=0 && dx_s2<({6'd0,len_s2}*(chinese[1] ? 12'd16 : 12'd10)) && dy_s2>=0 && dy_s2<16;
 always @(posedge pixel_clk)begin
  if(rst)begin
   state_q<=0;more_q<=0;performance_q<=0;spectrum_state<=0;spectrum_ready_state<=0;animation_phase<=0;animation_frame<=0;
   text_s1<=0;text_s2<=0;text_s3<=0;len_s1<=0;len_s2<=0;len_s3<=0;
   x_s1<=0;y_s1<=0;tx_s1<=0;ty_s1<=0;dx_s2<=0;dy_s2<=0;
   cell_s3<=0;row_s3<=0;normal_bit_s3<=0;normal_ink_s3<=0;
   char_s4<=0;row_s4<=0;normal_bit_s4<=0;normal_ink_s4<=0;
   addr_s5<=0;bit_s5<=0;ink_s5<=0;alpha_s5<=0;
   bit_s6<=0;ink_s6<=0;alpha_s6<=0;
   resolved_s7<=0;fg_s7<=0;alpha_s7<=0;ink_s7<=0;de_s7<=0;hs_s7<=0;vs_s7<=0;
   direct_ink<=0;direct_alpha<=0;background<=0;panels<=0;blank<=6'b111111;tests<=0;des<=0;hss<=0;vss<=0;
   for(integer q=0;q<6;q=q+1)begin bases[q]<=0;foregrounds[q]<=0;themes[q]<=0;end
   for(integer q=1;q<6;q=q+1)arts[q]<=0;
   for(integer q=0;q<4;q=q+1)begin direct_addr[q]<=0;direct_bit[q]<=0;fonts[q]<=0;zh_bases[q]<=0;end
   chinese<=0;bg_s1<=0;panel_s1<=0;rgb<=0;de_out<=0;hs_out<=0;vs_out<=0;
  end else begin
   if(frame_start)begin
    if(analysis_valid)begin spectrum_state<=analysis_data[511:0];spectrum_ready_state<=analysis_data[512];end
    if(status_valid)begin state_q<=status_data;more_q<=more_data;performance_q<=performance_data;end
    if(status_valid && status_data[1209:1208]!=theme)begin animation_phase<=0;animation_frame<=0;end
    else if(theme==1 || theme==2)begin
     if(animation_phase>=26'd28646640)begin animation_phase<=animation_phase-26'd28646640;animation_frame<=animation_frame+1'b1;end
     else animation_phase<=animation_phase+26'd6353360;
    end
   end
   text_s1<=text;len_s1<=len;x_s1<=raster_x;y_s1<=raster_y;tx_s1<=tx;ty_s1<=ty;
   direct_addr[0]<=font_addr;direct_bit[0]<=font_bit;fonts[0]<=font_theme;zh_bases[0]<=zh_style_base;chinese[0]<=wide_text;
   direct_ink[0]<=text_ink;direct_alpha[0]<=alpha_font;
   bases[0]<=base;foregrounds[0]<=fg;themes[0]<=theme;
   bg_s1<=BG;panel_s1<=PANEL;background[0]<=0;panels[0]<=0;tests[0]<=state[19];
   blank[0]<=!raster_de || raster_x>=800 || raster_y>=480;des[0]<=raster_de && raster_x<800 && raster_y<480;hss[0]<=raster_hs;vss[0]<=raster_vs;
   for(integer q=1;q<6;q=q+1)begin
    bases[q]<=bases[q-1];foregrounds[q]<=foregrounds[q-1];themes[q]<=themes[q-1];
    if(q==1)begin
     if(xy_pixel)bases[q]<=foregrounds[0];
     background[q]<=!xy_pixel && bases[0]==bg_s1;panels[q]<=!xy_pixel && bases[0]==panel_s1;
    end
    else begin background[q]<=background[q-1];panels[q]<=panels[q-1];end
    tests[q]<=tests[q-1];blank[q]<=blank[q-1];
    des[q]<=des[q-1];hss[q]<=hss[q-1];vss[q]<=vss[q-1];
    if(q==1)arts[q]<=art_pixel;else arts[q]<=arts[q-1];
   end
   for(integer q=1;q<4;q=q+1)begin
    direct_addr[q]<=direct_addr[q-1];direct_bit[q]<=direct_bit[q-1];fonts[q]<=fonts[q-1];zh_bases[q]<=zh_bases[q-1];chinese[q]<=chinese[q-1];
    direct_ink[q]<=direct_ink[q-1];direct_alpha[q]<=direct_alpha[q-1];
   end
   // Positions are bounded to the 800x480 canvas, not 32-bit signed dividers.
   dx_s2<=$signed({1'b0,x_s1})-$signed({1'b0,tx_s1});
   dy_s2<=$signed({1'b0,y_s1})-$signed({1'b0,ty_s1});text_s2<=text_s1;len_s2<=len_s1;
   cell_s3<=normal_valid ? (chinese[1] ? $unsigned(dx_s2)>>4 : $unsigned(dx_s2)/12'd10) : 0;
   normal_bit_s3<=15-(chinese[1] ? $unsigned(dx_s2)%12'd16 : $unsigned(dx_s2)%12'd10);row_s3<=dy_s2[3:0];normal_ink_s3<=normal_valid;
   text_s3<=text_s2;len_s3<=len_s2;
   char_s4<=normal_ink_s3 ? text_s3[{glyph_index,3'b000}+:8] : 8'd32;
   row_s4<=row_s3;normal_bit_s4<=normal_bit_s3;normal_ink_s4<=normal_ink_s3;
   addr_s5<=direct_ink[3] ? direct_addr[3] : (chinese_char ? zh_bases[3]+{3'd0,zh_index,row_s4} : {fonts[3],10'd0}+({fonts[3],10'd0}>>1)+(char_s4-8'd32)*15'd16+row_s4);
   bit_s5<=direct_ink[3] ? direct_bit[3] : normal_bit_s4;
   ink_s5<=!blank[3] && !tests[3] && (direct_ink[3] || (normal_ink_s4 && (char_s4!=0 && (!chinese_char || zh_index<ZH_GLYPHS))));
   alpha_s5<=direct_ink[3] && direct_alpha[3];
   bit_s6<=bit_s5;ink_s6<=ink_s5;alpha_s6<=alpha_s5;
   resolved_s7<=blank[5] ? 24'd0 : (!tests[5] && background[5]) ? arts[5] :
    (!tests[5] && panels[5] && themes[5]!=0) ? mix_color(bases[5],arts[5],2) : bases[5];
   fg_s7<=foregrounds[5];ink_s7<=ink_s6;
   alpha_s7<=alpha_s6 ? ((font_row>>bit_s6)&3) : (font_row[bit_s6] ? 3 : 0);
   de_s7<=des[5];hs_s7<=hss[5];vs_s7<=vss[5];
   rgb<=ink_s7 ? mix_color(resolved_s7,fg_s7,alpha_s7) : resolved_s7;
   de_out<=de_s7;hs_out<=hs_s7;vs_out<=vs_s7;
  end
 end
endmodule
