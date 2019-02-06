#import "helpers.asm"

.label border = $d020
.label background = $d021

.label cia1_interrupt_control_register = $dc0d
.label cia2_interrupt_control_register = $dd0d

// Note: the '-2' is required because stabilize_irq() takes 2 raster
// lines to synchronize the raster. More precisely, it _always_ ends
// after completing the 3rd cycle of raster line number RASTER_LINE.
.const RASTER_LINE = 48-2 // We want to "land" at RL:48:03

// The number of cycles we want to skip: imagine to be at the top left
// corner of the character page (by default at $0400) and that you can
// choose to "rebase" what is the character that appears in that corner.
//
// Notice that when below I say "equivalent" I do not mean "identical":
// it goes without saying that we will still need to adjust things
// (typically the 1st or 25th row, and the 1st or 40th column.)
//
// If you choose:
// (A) 0: Equivalent to no effect on scrolling.
// (B) 1: Equivalent to right to left scrolling, where the second column
//        becomes the 1st, and the 1st becomes the 40th (shifted up
//        by one character because the 1001th byte of the char memory,
//        that normally is not visible, becomes the character in the
//        bottom right corner.)
// (C)39: Equivalent to left to right scrolling, where the 40th column
//        becomes the 1st, and the 1st becomes the 2nd, etc.
//        Notice that the 25th row, from the 2nd to the 25th column, is
//        made of 24 characters from the 1001st to the 1024th char memory
//        that are normally not visible (remarkably, the last 8 of these
//        24 hidden chars, are seen by the VIC-II as sprite pointers.)
//        Notice that the 25th row, from the 26th to the 40th column, is
//        made of the 15 characters corresponding to the bytes from the
//        1st to the 15th char memory.
// (D)40: Equivalent to upward vertical scrolling, where the 2nd row
//        becomes the 1st, the 25th row becomes the 24th.
//        Notice how the first 24 characters of the 25th row are the
//        normally hidden charcters from the 1001st to the 1024th char
//        memory.
//        Notice how the last 16 characters of the 25th row correspond
//        to the symbols associated to the bytes that go from the 1st
//        to the 16th char memory locations.

//By default, we shift 2 columns to the left
.const NUM_DMA_DELAY_CYCLES = 2

:BasicUpstart2(main)
main:
  sei
    lda #WHITE
    sta border
    lda #BLACK
    sta background

    // We are simply emphasizing that $D011 is set at its default value,
    // and this means YSCROLL is 3, and the first bad line is 51.
    lda #$1B
    sta $D011

    clear_screen(32) //Clean all chars, including chars in the 1000-1023 range
    randomize_screen() //Fill up screen in the range 0-999 with letters
    //Place few '<' and '>' symbols close to the 4 corners of the screen,
    //so we can better assess the effect of scrolling using DMA Delay/VSP.
    lda #60           //'<' symbol..
    sta 1024+1*40+0   //..on the 2nd row, 1st column
    sta 1024+2*40+1   //..on the 3rd row, 2st column
    sta 1024+22*40+1  //..on the 23rd row, 2st column
    sta 1024+23*40+0  //..on the 24th row, 1st column
    lda #62           //'>' symbol..
    sta 1024+1*40+39  //..on the 2nd row, 40th column
    sta 1024+2*40+38  //..on the 3rd row, 39st column
    sta 1024+22*40+38 //..on the 23th row, 39th column
    sta 1024+23*40+39 //..on the 24th row, 40th column

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
//http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt
//
//3.14.6. DMA delay
//-----------------
//The most sophisticated Bad Line manipulation is to create a Bad Line
//Condition within cycles 15-53 of a raster line in the display window in
//which the graphics data sequencer is in idle state, e.g. by modifying
//register $d011 so that YSCROLL is equal to the lower three bits of RASTER.

irq1:
//jmp exiting_irq1 //Uncomment this to verify initialization works as intended
  :stabilize_irq() //RasterLine 48 after cycle 3, in short RL:48:03

  // Notice that up to this point, raster line 51 is the one that is
  // expected to become the first bad line since YSCROLL has value 3.

  // About cycles:
  //
  // - The inital -3 is to compensate for the fixed 3 cycle delay after
  // stabilize_irq() has completed running.
  //
  // - The final -6 is because lda #$18 + sta $D011 are 6 cycles combined.
  //
  // - The middle +14 is the earliest VSP can be triggered
  // (see 3.14.6. DMA delay in the "VIC-II article" by Christian Bauer.)
  //
  :cycles(-3 +14+(40-NUM_DMA_DELAY_CYCLES) -6) //RL:48:(8+40-NUM_DMA_DELAY_CYCLES)
            // Make *this* raster line (i.e. raster line 48) be
            // a Bad Line => This triggers the VSP/scroll
            // of (40-NUM_DMA_DELAY_CYCLES) columns.
  lda #$18  //(2,RL:48:(8+NUM_DMA_DELAY_CYCLES+2) %0001:1000
  sta $D011 //(4,RL:48:(8+NUM_DMA_DELAY_CYCLES+6)

  //...because raster line 48 is forced into a bad line, a VSP scroll
  // is triggered, so the CPU is stun until cycle 54...

  // ...so we can reset $D011 to use $1B as soon as we can: this way
  // we make sure that by the end of raster line 48, YSCROLL is
  // back to its default value 3, and we are ready for the next frame.
  lda #$1B  //(2, RL48:56)
  sta $D011 //(4, RL48:60)

exiting_irq1:
  asl vic2_interrupt_status_register
  :set_raster(RASTER_LINE)
  :mov16 #irq1 : $fffe
  rti