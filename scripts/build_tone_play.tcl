set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set profile $::env(TONE_PROFILE)
open_project [file join $root tone_play_${profile}.gprj]
set_device -device_version C GW5AST-LV138FPG676AC1/I0
set_option -top_module tone_play_${profile}
set_option -include_path [list [file join $root config]]
set_option -verilog_std sysv2017
set_option -output_base_name D1_${profile}_440
set_option -bit_security 0
set_option -bit_incl_bsram_init 1
run syn
run pnr
exit
