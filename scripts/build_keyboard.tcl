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
if {$stage eq "pnr"} {
    foreach item [lrange $argv 1 end] {
        if {$item eq "--routability"} {
            # Official routability-first placement and documented fanout limit.
            # Does not alter clocks, SDC, pin constraints, or timing exceptions.
            set_option -place_option 1
            set_option -route_option 2
            set_option -route_maxfan 60
            puts "PNR_PROFILE=routability PLACE=1 ROUTE=2 ROUTE_MAXFAN=60"
        } else {
            set_option -inc_pnr [file normalize $item]
        }
    }
}
if {$stage ne "pnr"} {
    run syn
}
if {$stage ne "syn"} {
    run pnr
}
exit
