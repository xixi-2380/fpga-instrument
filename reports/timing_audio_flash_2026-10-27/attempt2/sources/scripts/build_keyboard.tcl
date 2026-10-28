set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
open_project [file join $root keyboard_adsr.gprj]
set_device -device_version C GW5AST-LV138FPG676AC1/I0
set_option -top_module keyboard_top
set_option -include_path "[file join $root src];[file join $root src config]"
set_option -verilog_std sysv2017
set_option -output_base_name D2_keyboard_leds
set_option -bit_security 0
set_option -bit_incl_bsram_init 1
set_option -oreg_in_iob 1
set_option -inc_pnr 0
set_option -gen_sdf 1
set stage [lindex $argv 0]
if {$stage eq "pnr" && [llength $argv] > 1} {
    set_option -inc_pnr [file normalize [lindex $argv 1]]
}
if {$stage ne "pnr"} {
    run syn
}
if {$stage ne "syn"} {
    run pnr
}
exit
