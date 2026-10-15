set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
open_project [file join $root keyboard_adsr.gprj]
set_device -device_version C GW5AST-LV138FPG676AC1/I0
set_option -top_module keyboard_top
set_option -include_path [list [file join $root src] [file join $root src config]]
set_option -verilog_std sysv2017
set_option -output_base_name D2_keyboard_leds
set_option -bit_security 0
set_option -bit_incl_bsram_init 1
run syn
run pnr
exit
