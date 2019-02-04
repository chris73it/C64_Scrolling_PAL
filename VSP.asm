#import "helpers.asm"

.label border = $d020
.label background = $d021

.label cia1_interrupt_control_register = $dc0d
.label cia2_interrupt_control_register = $dd0d

// Note: the '-2' is required because stabilize_irq() takes 2 raster
// lines to synchronize the raster. More precisely, it _always_ ends
// after completing the 3rd cycle of raster line number RASTER_LINE.
.const RASTER_LINE = 48-2 // We want to "land" at RL:48:03

// The number of columns we want to vsp/scroll from left to right.
// This value must be a number between 0 - equivalent to no scrolling,
// and 39 - that makes the first column become the 40th.
// Notice that setting this value to 40 will make the VSP hack fail,
// i.e. the screen will not scroll at all.
.const NUM_L2R_COLUMNS = 3

:BasicUpstart2(main)
main:
  sei
    //Display blanks on 1024 bytes, starting from $0400
    clear_screen(32)

    // Display a column of numbers, to make it simpler to see
    // whether the VSP based left to right scrolling is working.
    ldx #48
    .for(var index=0; index < 5; index++) {
      stx screen +   0 + index * 40
      stx screen + 200 + index * 40
      stx screen + 400 + index * 40
      stx screen + 600 + index * 40
      stx screen + 800 + index * 40
      inx
    }

    lda $01
    and #%11111101
    sta $01

    lda #%01111111
    sta cia1_interrupt_control_register
    sta cia2_interrupt_control_register
    lda cia1_interrupt_control_register
    lda cia2_interrupt_control_register

    lda #%00000001
    sta vic2_interrupt_control_register
    sta vic2_interrupt_status_register
    :set_raster(RASTER_LINE)
    :mov16 #irq1 : $fffe
  cli

loop:
  jmp loop

//From Christian Bauer "VIC-II article"
//3.14.6. DMA delay
//-----------------
//The most sophisticated Bad Line manipulation is to create a Bad Line
//Condition within cycles 15-53 of a raster line in the display window in
//which the graphics data sequencer is in idle state, e.g. by modifying
//register $d011 so that YSCROLL is equal to the lower three bits of RASTER.

irq1:
//jmp exiting_irq1
  :stabilize_irq() //RasterLine 48 after cycle 3, in short RL:48:03

  // About cycles:
  //
  // - The inital -3 is to compensate for the fixed 3 cycle delay after
  // stabilize_irq() has completed running.
  //
  // - The final -6 is because lda #$18 + sta $D011 are 6 cycles combined.
  //
  // - The middle 14+NUM_L2R_COLUMNS is the earliest VSP can be triggered
  // (see 3.14.6. DMA delay in the "VIC-II article" by Christian Bauer.)
  //
  :cycles(-3 +14+NUM_L2R_COLUMNS -6) //RL:48:(8+NUM_L2R_COLUMNS)
            // Make *this* raster line (i.e. raster line 48) be
            // a Bad Line => This triggers the VSP/scroll
            // of N_L2R_COLUMNS columns.
  lda #$18  //(2,RL:48:(8+NUM_L2R_COLUMNS+2) %0001:1000
  sta $D011 //(4,RL:48:(8+NUM_L2R_COLUMNS+6)

  //...because raster line 48 is triggered into a VSP scroll, it becomes
  // a bad line, so the CPU is stun until cycle 54...

  // ...so we can reset $D011 to use $1B as soon as we can: this way
  // we make sure that YSCROLL is back to 3 for the next frame.
  lda #$1B
  sta $D011

exiting_irq1:
  asl vic2_interrupt_status_register
  :set_raster(RASTER_LINE)
  :mov16 #irq1 : $fffe
  rti