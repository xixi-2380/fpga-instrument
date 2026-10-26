set root [file normalize [file dirname [info script]]]
cd $root
open_project [file join $root touch_led.gprj]
set_device -device_version C GW5AST-LV138FPG676AC1/I0
set_option -top_module touch_led_top
set_option -verilog_std v2001
set_option -output_base_name touch_led
run syn
run pnr
exit
