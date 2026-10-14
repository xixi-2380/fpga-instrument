set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
open_project [file join $root tone_feasibility.gprj]
set_device -device_version C GW5AST-LV138FPG676AC1/I0
cd $root
set_option -top_module tone_top
set_option -include_path [list [file join $root config]]
set_option -verilog_std sysv2017
set_option -output_base_name tone_UNVERIFIED
run syn
if {[info exists env(RUN_PNR)] && $env(RUN_PNR) eq "1"} { run pnr }
exit
