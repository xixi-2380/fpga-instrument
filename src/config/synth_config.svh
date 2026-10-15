`ifndef SYNTH_CONFIG_SVH
`define SYNTH_CONFIG_SVH
`define REF_HZ 50000000
`define AUDIO_HZ 61440000
`define MID_HZ 32000000
`define PLL1_FCLKIN "50"
`define PLL1_IDIV 1
`define PLL1_FBDIV 1
`define PLL1_MDIV 16
`define PLL1_ODIV 25
`define PLL2_FCLKIN "32"
`define PLL2_IDIV 1
`define PLL2_FBDIV 1
`define PLL2_MDIV 24
`define PLL2_ODIV 12
`define PLL2_ODIV_FRAC 4
`define SAMPLE_HZ 48000
`define PHASE_W 32
`define ROM_ADDR_W 12
`define ROM_DATA_W 16
`define VOICE_W 24
`define MIX_W 40
`define DAC_W 16
`define VOICE_COUNT 4
`define BCK_HALF_CYCLES (`AUDIO_HZ/(`SAMPLE_HZ*`WORD_BITS*2*2))
`define WORD_BITS 16
`define FRAME_CYCLES (`BCK_HALF_CYCLES*2*`WORD_BITS*2)
`define TONE_FCW 32'h0258BF26
`define LOCK_CYCLES (`REF_HZ*2/1000)
`define MUTE_FRAMES 480
`define FADE_FRAMES 240
`define GAIN_SHIFT 5
// Voice defaults are independent of the physical keyboard adapter.
`define ADSR_ATTACK_FRAMES (`SAMPLE_HZ/100)
`define ADSR_DECAY_FRAMES (`SAMPLE_HZ/10)
`define ADSR_SUSTAIN_LEVEL 17'd45875
`define ADSR_RELEASE_FRAMES (`SAMPLE_HZ/5)
`endif
