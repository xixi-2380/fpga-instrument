`timescale 1ns/1ps
`include "config/synth_config.svh"
// Touch/encoder settings. Dock S0..S3 and old automatic volume are retired.
module timbre_control #(parameter integer DEBOUNCE_CYCLES=1,LONG_PRESS_CYCLES=1,ULTRA_SLEW_CYCLES=1)(
 input wire clk,rst,input wire [3:0] buttons_n,
 output reg [4:0] selected,output wire effects_enabled,output reg [1:0] effect_mode,
 input wire ui_action_valid,input wire [6:0] ui_action,input wire cfg_ready,
 output reg menu_mode,output reg cfg_valid,
 output reg [8:0] echo_wet,room_wet,tremolo_depth,output reg [4:0] cfg_tremolo_rate_hz,
 output reg [6:0] echo_percent,room_percent,depth_percent,output reg [4:0] tremolo_rate_hz,
 output reg [6:0] volume_percent,output reg ultrasonic_page,ultrasonic_enabled,
 // Public name retained: ultrasonic_sensitivity is neutral half-width, 1..5cm.
 output reg [2:0] ultrasonic_sensitivity,output reg [6:0] ultrasonic_min,ultrasonic_max,
 output reg [7:0] ultrasonic_version,
 input wire auto_valid,input wire [7:0] auto_version,input wire [6:0] auto_target,
 input wire [2:0] encoder_up,encoder_down,encoder_single,encoder_double,
 output reg [2:0] effect_mask,cfg_effect_mask,output reg echo_edit_strength,tremolo_edit_rate,
 output reg [10:0] echo_time_ms,output wire [15:0] echo_time_bcd,output reg [16:0] cfg_echo_samples,
 output reg [1:0] theme_id,view_mode,output reg language_zh);
 `include "config/ui_layout.svh"
 reg [1:0] normal_theme;
 wire [6:0] current_percent=effect_mode==0?echo_percent:effect_mode==1?room_percent:depth_percent;
    function automatic [8:0] amount(input [6:0] percent);
        begin case(percent)
            7'd0:amount=9'd0;
            7'd1:amount=9'd3;
            7'd2:amount=9'd5;
            7'd3:amount=9'd8;
            7'd4:amount=9'd10;
            7'd5:amount=9'd13;
            7'd6:amount=9'd15;
            7'd7:amount=9'd18;
            7'd8:amount=9'd20;
            7'd9:amount=9'd23;
            7'd10:amount=9'd26;
            7'd11:amount=9'd28;
            7'd12:amount=9'd31;
            7'd13:amount=9'd33;
            7'd14:amount=9'd36;
            7'd15:amount=9'd38;
            7'd16:amount=9'd41;
            7'd17:amount=9'd44;
            7'd18:amount=9'd46;
            7'd19:amount=9'd49;
            7'd20:amount=9'd51;
            7'd21:amount=9'd54;
            7'd22:amount=9'd56;
            7'd23:amount=9'd59;
            7'd24:amount=9'd61;
            7'd25:amount=9'd64;
            7'd26:amount=9'd67;
            7'd27:amount=9'd69;
            7'd28:amount=9'd72;
            7'd29:amount=9'd74;
            7'd30:amount=9'd77;
            7'd31:amount=9'd79;
            7'd32:amount=9'd82;
            7'd33:amount=9'd84;
            7'd34:amount=9'd87;
            7'd35:amount=9'd90;
            7'd36:amount=9'd92;
            7'd37:amount=9'd95;
            7'd38:amount=9'd97;
            7'd39:amount=9'd100;
            7'd40:amount=9'd102;
            7'd41:amount=9'd105;
            7'd42:amount=9'd108;
            7'd43:amount=9'd110;
            7'd44:amount=9'd113;
            7'd45:amount=9'd115;
            7'd46:amount=9'd118;
            7'd47:amount=9'd120;
            7'd48:amount=9'd123;
            7'd49:amount=9'd125;
            7'd50:amount=9'd128;
            7'd51:amount=9'd131;
            7'd52:amount=9'd133;
            7'd53:amount=9'd136;
            7'd54:amount=9'd138;
            7'd55:amount=9'd141;
            7'd56:amount=9'd143;
            7'd57:amount=9'd146;
            7'd58:amount=9'd148;
            7'd59:amount=9'd151;
            7'd60:amount=9'd154;
            7'd61:amount=9'd156;
            7'd62:amount=9'd159;
            7'd63:amount=9'd161;
            7'd64:amount=9'd164;
            7'd65:amount=9'd166;
            7'd66:amount=9'd169;
            7'd67:amount=9'd172;
            7'd68:amount=9'd174;
            7'd69:amount=9'd177;
            7'd70:amount=9'd179;
            7'd71:amount=9'd182;
            7'd72:amount=9'd184;
            7'd73:amount=9'd187;
            7'd74:amount=9'd189;
            7'd75:amount=9'd192;
            7'd76:amount=9'd195;
            7'd77:amount=9'd197;
            7'd78:amount=9'd200;
            7'd79:amount=9'd202;
            7'd80:amount=9'd205;
            7'd81:amount=9'd207;
            7'd82:amount=9'd210;
            7'd83:amount=9'd212;
            7'd84:amount=9'd215;
            7'd85:amount=9'd218;
            7'd86:amount=9'd220;
            7'd87:amount=9'd223;
            7'd88:amount=9'd225;
            7'd89:amount=9'd228;
            7'd90:amount=9'd230;
            7'd91:amount=9'd233;
            7'd92:amount=9'd236;
            7'd93:amount=9'd238;
            7'd94:amount=9'd241;
            7'd95:amount=9'd243;
            7'd96:amount=9'd246;
            7'd97:amount=9'd248;
            7'd98:amount=9'd251;
            7'd99:amount=9'd253;
            7'd100:amount=9'd256;
            default:amount=9'd64;
        endcase end
    endfunction
    function automatic [15:0] time_bcd(input [10:0] ms);
        begin case(ms)
            11'd20:time_bcd=16'h0020;
            11'd30:time_bcd=16'h0030;
            11'd40:time_bcd=16'h0040;
            11'd50:time_bcd=16'h0050;
            11'd60:time_bcd=16'h0060;
            11'd70:time_bcd=16'h0070;
            11'd80:time_bcd=16'h0080;
            11'd90:time_bcd=16'h0090;
            11'd100:time_bcd=16'h0100;
            11'd110:time_bcd=16'h0110;
            11'd120:time_bcd=16'h0120;
            11'd130:time_bcd=16'h0130;
            11'd140:time_bcd=16'h0140;
            11'd150:time_bcd=16'h0150;
            11'd160:time_bcd=16'h0160;
            11'd170:time_bcd=16'h0170;
            11'd180:time_bcd=16'h0180;
            11'd190:time_bcd=16'h0190;
            11'd200:time_bcd=16'h0200;
            11'd210:time_bcd=16'h0210;
            11'd220:time_bcd=16'h0220;
            11'd230:time_bcd=16'h0230;
            11'd240:time_bcd=16'h0240;
            11'd250:time_bcd=16'h0250;
            11'd260:time_bcd=16'h0260;
            11'd270:time_bcd=16'h0270;
            11'd280:time_bcd=16'h0280;
            11'd290:time_bcd=16'h0290;
            11'd300:time_bcd=16'h0300;
            11'd310:time_bcd=16'h0310;
            11'd320:time_bcd=16'h0320;
            11'd330:time_bcd=16'h0330;
            11'd340:time_bcd=16'h0340;
            11'd350:time_bcd=16'h0350;
            11'd360:time_bcd=16'h0360;
            11'd370:time_bcd=16'h0370;
            11'd380:time_bcd=16'h0380;
            11'd390:time_bcd=16'h0390;
            11'd400:time_bcd=16'h0400;
            11'd410:time_bcd=16'h0410;
            11'd420:time_bcd=16'h0420;
            11'd430:time_bcd=16'h0430;
            11'd440:time_bcd=16'h0440;
            11'd450:time_bcd=16'h0450;
            11'd460:time_bcd=16'h0460;
            11'd470:time_bcd=16'h0470;
            11'd480:time_bcd=16'h0480;
            11'd490:time_bcd=16'h0490;
            11'd500:time_bcd=16'h0500;
            11'd510:time_bcd=16'h0510;
            11'd520:time_bcd=16'h0520;
            11'd530:time_bcd=16'h0530;
            11'd540:time_bcd=16'h0540;
            11'd550:time_bcd=16'h0550;
            11'd560:time_bcd=16'h0560;
            11'd570:time_bcd=16'h0570;
            11'd580:time_bcd=16'h0580;
            11'd590:time_bcd=16'h0590;
            11'd600:time_bcd=16'h0600;
            11'd610:time_bcd=16'h0610;
            11'd620:time_bcd=16'h0620;
            11'd630:time_bcd=16'h0630;
            11'd640:time_bcd=16'h0640;
            11'd650:time_bcd=16'h0650;
            11'd660:time_bcd=16'h0660;
            11'd670:time_bcd=16'h0670;
            11'd680:time_bcd=16'h0680;
            11'd690:time_bcd=16'h0690;
            11'd700:time_bcd=16'h0700;
            11'd710:time_bcd=16'h0710;
            11'd720:time_bcd=16'h0720;
            11'd730:time_bcd=16'h0730;
            11'd740:time_bcd=16'h0740;
            11'd750:time_bcd=16'h0750;
            11'd760:time_bcd=16'h0760;
            11'd770:time_bcd=16'h0770;
            11'd780:time_bcd=16'h0780;
            11'd790:time_bcd=16'h0790;
            11'd800:time_bcd=16'h0800;
            11'd810:time_bcd=16'h0810;
            11'd820:time_bcd=16'h0820;
            11'd830:time_bcd=16'h0830;
            11'd840:time_bcd=16'h0840;
            11'd850:time_bcd=16'h0850;
            11'd860:time_bcd=16'h0860;
            11'd870:time_bcd=16'h0870;
            11'd880:time_bcd=16'h0880;
            11'd890:time_bcd=16'h0890;
            11'd900:time_bcd=16'h0900;
            11'd910:time_bcd=16'h0910;
            11'd920:time_bcd=16'h0920;
            11'd930:time_bcd=16'h0930;
            11'd940:time_bcd=16'h0940;
            11'd950:time_bcd=16'h0950;
            11'd960:time_bcd=16'h0960;
            11'd970:time_bcd=16'h0970;
            11'd980:time_bcd=16'h0980;
            11'd990:time_bcd=16'h0990;
            11'd1000:time_bcd=16'h1000;
            11'd1010:time_bcd=16'h1010;
            11'd1020:time_bcd=16'h1020;
            11'd1030:time_bcd=16'h1030;
            11'd1040:time_bcd=16'h1040;
            11'd1050:time_bcd=16'h1050;
            11'd1060:time_bcd=16'h1060;
            11'd1070:time_bcd=16'h1070;
            11'd1080:time_bcd=16'h1080;
            11'd1090:time_bcd=16'h1090;
            11'd1100:time_bcd=16'h1100;
            11'd1110:time_bcd=16'h1110;
            11'd1120:time_bcd=16'h1120;
            11'd1130:time_bcd=16'h1130;
            11'd1140:time_bcd=16'h1140;
            11'd1150:time_bcd=16'h1150;
            11'd1160:time_bcd=16'h1160;
            11'd1170:time_bcd=16'h1170;
            11'd1180:time_bcd=16'h1180;
            11'd1190:time_bcd=16'h1190;
            11'd1200:time_bcd=16'h1200;
            11'd1210:time_bcd=16'h1210;
            11'd1220:time_bcd=16'h1220;
            11'd1230:time_bcd=16'h1230;
            11'd1240:time_bcd=16'h1240;
            11'd1250:time_bcd=16'h1250;
            11'd1260:time_bcd=16'h1260;
            11'd1270:time_bcd=16'h1270;
            11'd1280:time_bcd=16'h1280;
            11'd1290:time_bcd=16'h1290;
            11'd1300:time_bcd=16'h1300;
            11'd1310:time_bcd=16'h1310;
            11'd1320:time_bcd=16'h1320;
            11'd1330:time_bcd=16'h1330;
            11'd1340:time_bcd=16'h1340;
            11'd1350:time_bcd=16'h1350;
            11'd1360:time_bcd=16'h1360;
            11'd1370:time_bcd=16'h1370;
            11'd1380:time_bcd=16'h1380;
            11'd1390:time_bcd=16'h1390;
            11'd1400:time_bcd=16'h1400;
            11'd1410:time_bcd=16'h1410;
            11'd1420:time_bcd=16'h1420;
            11'd1430:time_bcd=16'h1430;
            11'd1440:time_bcd=16'h1440;
            11'd1450:time_bcd=16'h1450;
            11'd1460:time_bcd=16'h1460;
            11'd1470:time_bcd=16'h1470;
            11'd1480:time_bcd=16'h1480;
            11'd1490:time_bcd=16'h1490;
            11'd1500:time_bcd=16'h1500;
            11'd1510:time_bcd=16'h1510;
            11'd1520:time_bcd=16'h1520;
            11'd1530:time_bcd=16'h1530;
            11'd1540:time_bcd=16'h1540;
            11'd1550:time_bcd=16'h1550;
            11'd1560:time_bcd=16'h1560;
            11'd1570:time_bcd=16'h1570;
            11'd1580:time_bcd=16'h1580;
            11'd1590:time_bcd=16'h1590;
            11'd1600:time_bcd=16'h1600;
            11'd1610:time_bcd=16'h1610;
            11'd1620:time_bcd=16'h1620;
            11'd1630:time_bcd=16'h1630;
            11'd1640:time_bcd=16'h1640;
            11'd1650:time_bcd=16'h1650;
            11'd1660:time_bcd=16'h1660;
            11'd1670:time_bcd=16'h1670;
            11'd1680:time_bcd=16'h1680;
            11'd1690:time_bcd=16'h1690;
            11'd1700:time_bcd=16'h1700;
            11'd1710:time_bcd=16'h1710;
            11'd1720:time_bcd=16'h1720;
            11'd1730:time_bcd=16'h1730;
            11'd1740:time_bcd=16'h1740;
            11'd1750:time_bcd=16'h1750;
            11'd1760:time_bcd=16'h1760;
            11'd1770:time_bcd=16'h1770;
            11'd1780:time_bcd=16'h1780;
            11'd1790:time_bcd=16'h1790;
            11'd1800:time_bcd=16'h1800;
            11'd1810:time_bcd=16'h1810;
            11'd1820:time_bcd=16'h1820;
            11'd1830:time_bcd=16'h1830;
            11'd1840:time_bcd=16'h1840;
            11'd1850:time_bcd=16'h1850;
            11'd1860:time_bcd=16'h1860;
            11'd1870:time_bcd=16'h1870;
            11'd1880:time_bcd=16'h1880;
            11'd1890:time_bcd=16'h1890;
            11'd1900:time_bcd=16'h1900;
            11'd1910:time_bcd=16'h1910;
            11'd1920:time_bcd=16'h1920;
            11'd1930:time_bcd=16'h1930;
            11'd1940:time_bcd=16'h1940;
            11'd1950:time_bcd=16'h1950;
            11'd1960:time_bcd=16'h1960;
            11'd1970:time_bcd=16'h1970;
            11'd1980:time_bcd=16'h1980;
            11'd1990:time_bcd=16'h1990;
            11'd2000:time_bcd=16'h2000;
            default:time_bcd=16'h0150;
        endcase end
    endfunction
 assign effects_enabled=effect_mask[effect_mode];
 assign echo_time_bcd=time_bcd(echo_time_ms);
 // Preserve a submitted snapshot while the audio engine is backpressured.
 always @(posedge clk or posedge rst)begin
  if(rst)begin echo_wet<=64;room_wet<=64;tremolo_depth<=128;cfg_tremolo_rate_hz<=5;cfg_valid<=1;cfg_effect_mask<=0;cfg_echo_samples<=7200;end
  else if(!cfg_valid || cfg_ready)begin
   if(echo_wet!=amount(echo_percent) || room_wet!=amount(room_percent) || tremolo_depth!=amount(depth_percent) ||
      cfg_tremolo_rate_hz!=tremolo_rate_hz || cfg_effect_mask!=effect_mask || cfg_echo_samples!=echo_time_ms*17'd48)begin
    echo_wet<=amount(echo_percent);room_wet<=amount(room_percent);tremolo_depth<=amount(depth_percent);
    cfg_tremolo_rate_hz<=tremolo_rate_hz;cfg_effect_mask<=effect_mask;cfg_echo_samples<=echo_time_ms*17'd48;cfg_valid<=1;
   end else cfg_valid<=0;
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   selected<=0;effect_mask<=0;effect_mode<=0;echo_edit_strength<=0;tremolo_edit_rate<=0;echo_time_ms<=150;
   echo_percent<=25;room_percent<=25;depth_percent<=50;tremolo_rate_hz<=5;volume_percent<=100;menu_mode<=0;
   ultrasonic_page<=0;ultrasonic_enabled<=0;ultrasonic_sensitivity<=1;ultrasonic_min<=5;ultrasonic_max<=40;ultrasonic_version<=0;
   theme_id<=0;normal_theme<=0;language_zh<=0;view_mode<=0;
  end else begin
   if(ui_action_valid)case(ui_action)
    7'd64,7'd65,7'd66,7'd67,7'd68,7'd69,7'd70,7'd71:selected<={1'b0,selected[3],ui_action[2:0]};
    UI_TONE_PAGE:selected<=selected^5'd8;
    UI_SINE:selected<=0;UI_FLUTE:selected<=1;UI_REED:selected<=2;UI_CELLO:selected<=3;UI_PIANO:selected<=4;UI_GUITAR:selected<=5;UI_VIBES:selected<=6;
    UI_PREV:selected<=selected==0?5'd15:selected-1'b1;UI_NEXT:selected<=selected==15?5'd0:selected+1'b1;
    UI_ECHO:effect_mode<=0;UI_ROOM:effect_mode<=1;UI_TREMOLO:effect_mode<=2;
    UI_FX:effect_mask[effect_mode]<=!effect_mask[effect_mode];
    UI_MODE:begin menu_mode<=!menu_mode;ultrasonic_page<=0;end
    UI_VOLUME_DOWN:volume_percent<=volume_percent>=5?volume_percent-7'd5:7'd0;
    UI_VOLUME_UP:volume_percent<=volume_percent<=95?volume_percent+7'd5:7'd100;
    UI_OPEN_MORE,UI_SENSITIVITY:ultrasonic_page<=0;
    UI_ULTRA_OPEN:if(menu_mode)ultrasonic_page<=1;
    UI_ULTRA_BACK:ultrasonic_page<=0;
    UI_ULTRA_TOGGLE:begin ultrasonic_enabled<=!ultrasonic_enabled;ultrasonic_version<=ultrasonic_version+1'b1;end
    UI_SENS_DOWN:if(ultrasonic_sensitivity>1)begin ultrasonic_sensitivity<=ultrasonic_sensitivity-1'b1;ultrasonic_version<=ultrasonic_version+1'b1;end
    UI_SENS_UP:if(ultrasonic_sensitivity<5)begin ultrasonic_sensitivity<=ultrasonic_sensitivity+1'b1;ultrasonic_version<=ultrasonic_version+1'b1;end
    UI_MIN_DOWN:if(ultrasonic_min>=5)begin ultrasonic_min<=ultrasonic_min-7'd5;ultrasonic_version<=ultrasonic_version+1'b1;end
    UI_MIN_UP:if(ultrasonic_min+7'd5<ultrasonic_max)begin ultrasonic_min<=ultrasonic_min+7'd5;ultrasonic_version<=ultrasonic_version+1'b1;end
    UI_MAX_DOWN:if(ultrasonic_max>ultrasonic_min+7'd5)begin ultrasonic_max<=ultrasonic_max-7'd5;ultrasonic_version<=ultrasonic_version+1'b1;end
    UI_MAX_UP:if(ultrasonic_max<=95)begin ultrasonic_max<=ultrasonic_max+7'd5;ultrasonic_version<=ultrasonic_version+1'b1;end
    UI_LESS,UI_MORE:case(effect_mode)
     0:echo_percent<=ui_action==UI_MORE?(current_percent<=95?current_percent+7'd5:7'd100):(current_percent>=5?current_percent-7'd5:7'd0);
     1:room_percent<=ui_action==UI_MORE?(current_percent<=95?current_percent+7'd5:7'd100):(current_percent>=5?current_percent-7'd5:7'd0);
     default:depth_percent<=ui_action==UI_MORE?(current_percent<=95?current_percent+7'd5:7'd100):(current_percent>=5?current_percent-7'd5:7'd0);
    endcase
    UI_SLOWER:if(effect_mode==2 && tremolo_rate_hz>1)tremolo_rate_hz<=tremolo_rate_hz-1'b1;
    UI_FASTER:if(effect_mode==2 && tremolo_rate_hz<20)tremolo_rate_hz<=tremolo_rate_hz+1'b1;
    UI_THEME:begin normal_theme<=normal_theme==2?0:normal_theme+1'b1;theme_id<=normal_theme==2?0:normal_theme+1'b1;end
    UI_EGG:theme_id<=theme_id==3?normal_theme:2'd3;
    UI_LANGUAGE:language_zh<=!language_zh;
    UI_VIEW:view_mode<=view_mode==2?0:view_mode+1'b1;
    UI_DEFAULTS:begin
     volume_percent<=100;ultrasonic_enabled<=0;ultrasonic_page<=0;ultrasonic_sensitivity<=1;ultrasonic_min<=5;ultrasonic_max<=40;
     ultrasonic_version<=ultrasonic_version+1'b1;echo_percent<=25;room_percent<=25;depth_percent<=50;tremolo_rate_hz<=5;
     effect_mode<=0;effect_mask<=0;echo_time_ms<=150;echo_edit_strength<=0;tremolo_edit_rate<=0;
    end
    default:begin end
   endcase
   // Encoder2 owns only master volume, never the reverb mask or coefficient.
   if(encoder_up[1]===1'b1)begin if(volume_percent<100)volume_percent<=volume_percent+1'b1;end
   else if(encoder_down[1]===1'b1 && volume_percent>0)volume_percent<=volume_percent-1'b1;
   if(encoder_single[0]===1'b1)begin effect_mode<=0;echo_edit_strength<=!echo_edit_strength;end
   if(encoder_double[0]===1'b1)begin effect_mode<=0;effect_mask[0]<=!effect_mask[0];end
   if(encoder_up[0]===1'b1 || encoder_down[0]===1'b1)begin
    effect_mode<=0;
    if(!echo_edit_strength)begin
     if(encoder_up[0]===1'b1 && echo_time_ms<2000)echo_time_ms<=echo_time_ms+11'd10;
     else if(encoder_down[0]===1'b1 && echo_time_ms>20)echo_time_ms<=echo_time_ms-11'd10;
    end else begin
     if(encoder_up[0]===1'b1 && echo_percent<100)echo_percent<=echo_percent+1'b1;
     else if(encoder_down[0]===1'b1 && echo_percent>0)echo_percent<=echo_percent-1'b1;
    end
   end
   if(encoder_single[2]===1'b1)begin effect_mode<=2;tremolo_edit_rate<=!tremolo_edit_rate;end
   if(encoder_double[2]===1'b1)begin effect_mode<=2;effect_mask[2]<=!effect_mask[2];end
   if(encoder_up[2]===1'b1 || encoder_down[2]===1'b1)begin
    effect_mode<=2;
    if(tremolo_edit_rate)begin
     if(encoder_up[2]===1'b1 && tremolo_rate_hz<20)tremolo_rate_hz<=tremolo_rate_hz+1'b1;
     else if(encoder_down[2]===1'b1 && tremolo_rate_hz>1)tremolo_rate_hz<=tremolo_rate_hz-1'b1;
    end else begin
     if(encoder_up[2]===1'b1 && depth_percent<100)depth_percent<=depth_percent+1'b1;
     else if(encoder_down[2]===1'b1 && depth_percent>0)depth_percent<=depth_percent-1'b1;
    end
   end
  end
 end
endmodule
