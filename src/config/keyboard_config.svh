`ifndef KEYBOARD_CONFIG_SVH
`define KEYBOARD_CONFIG_SVH
`include "synth_config.svh"
// 50 us per column, 200 us per scan. Fifteen scans qualify a change.
`define KEY_SLOT_CYCLES (`AUDIO_HZ/20000)
`define KEY_SETTLE_CYCLES (`AUDIO_HZ/100000)
`define KEY_DEBOUNCE_SCANS 15
`define ADSR_ATTACK_FRAMES (`SAMPLE_HZ/100)
`define ADSR_DECAY_FRAMES (`SAMPLE_HZ/10)
`define ADSR_SUSTAIN_LEVEL 17'd45875
`define ADSR_RELEASE_FRAMES (`SAMPLE_HZ/5)
`endif
