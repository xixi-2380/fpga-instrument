`ifndef RUN_LEDS_CONFIG_SVH
`define RUN_LEDS_CONFIG_SVH
`include "synth_config.svh"
`define RUN_LED_STEP_CYCLES (`REF_HZ/4)
// Four quarter-second steps without audio-ready enter status diagnostics.
// Zero disables the diagnostic display for isolated tests.
`define RUN_LED_DIAG_STEPS 4
`endif
