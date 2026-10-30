package cn.whu.gaoshan.core;
/** Stable device IDs. GM programs use zero-based wire numbering. */
public final class Timbres {
 private Timbres(){}
 public static final String[] NAMES={"正弦","笛管","簧管","大提琴","钢琴","木吉他","颤音琴","管风琴","电贝斯","小提琴","弦乐合奏","小号","萨克斯","合成主音","铺底","手风琴"};
 public static final int[] DRUM_MS={250,180,140,80,450,350,300,250,1500,1000};
 public static int program(int p){
  if(p<0||p>127)throw new IllegalArgumentException("GM音色编号非法");
  if(p<8)return 4;if(p<16)return 6;if(p<21)return 7;if(p<24)return 15;
  if(p<32)return 5;if(p<40)return 8;if(p<42)return 9;if(p<44)return 3;
  if(p<56)return 10;if(p<64)return 11;if(p<68)return 12;if(p<72)return 2;
  if(p<80)return 1;if(p<88)return 13;if(p<104)return 14;if(p<108)return 5;
  if(p<120)return 6;return 13;
 }
 public static int drum(int key){switch(key){
  case 35:case 36:return 16;case 37:case 38:case 40:return 17;case 39:return 18;
  case 42:case 44:return 19;case 46:return 20;case 41:case 43:return 21;
  case 45:case 47:return 22;case 48:case 50:return 23;case 49:case 52:case 55:case 57:return 24;
  case 51:case 53:case 59:return 25;default:throw new IllegalArgumentException("不支持的GM鼓键："+key+"；可排除鼓轨后重试");}}
}
