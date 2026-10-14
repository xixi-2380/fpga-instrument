set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
open_project [file join $root bringup_digital.gprj]
set_device -device_version C GW5AST-LV138FPG676AC1/I0
cd $root
set_option -top_module bringup_digital
set_option -include_path [list [file join $root config]]
set_option -verilog_std sysv2017
set_option -output_base_name bringup_D0_header_mirror
# Temporary, non-secret diagnostic must allow operation 4 SRAM readback.
# This affects only this bitstream; it does not program any efuse or Flash.
set_option -bit_security 0
run syn
run pnr
exit
