#import "helpers.asm"

.label border = $d020
.label background = $d021

.label cia1_interrupt_control_register = $dc0d
.label cia2_interrupt_control_register = $dd0d

// Note: the '-2' is required because stabilize_irq() takes 2 raster
// lines to synchronize the raster. More precisely, it _always_ ends
// after completing the 3rd cycle of raster line number RASTER_LINE.
.const RASTER_LINE = (48-1)-2 // We want to "land" at RL:47:03

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

:BasicUpstart2(main)
main:
  sei
    lda #LIGHT_GRAY
    sta border
    lda #BLACK
    sta background

    //We are simply emphasizing that $D011 is set at its default value,
    //and this means YSCROLL is 3, and the first bad line is 51: this
    //way we can DMA delay raster line 48 since it is a good line,
    //then immediately after we will restore raster line 51 to be
    //the next bad line.
    lda #$1B
    sta $D011

    //By default, we start with the screen in neutral position,
    //i.e., no column is scrolled. The valid values are:
    //[0:39] is 40 different positions for horizontal scrolling.
    //   40  is the "scrolled up" position (not used in this demo.)

    //Notice that the initial value for $fe can only be either 0 or 39.
    lda #0 //By default we scroll right to left (so $ff will be 0)
    sta $fe
//    cmp #0
    beq finalize_scroll_dir
left2rigth:
    lda #$ff //Scroll left to right
finalize_scroll_dir:
    sta $ff

prep_screen:
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
//jmp exiting_irq1 //Uncomment to verify initialization works as intended
  :stabilize_irq() //RasterLine 47 after cycle 3, in short RL:47:03

  // Notice that up to this point, raster line 51 is the one that is
  // expected to become the first bad line since YSCROLL has value 3.

  ldy $fe      //(3, RL:47:06)
  sty ndelay+1 //(4, RL:47:10) Set $fe cycles into LSB NDelay's address
  :cycles(-3-3-4 +63 -6) //RL:47:57
ndelay:
  //Notice that sty above is writing into the LSB of the NDelay address
  jsr NDelay //RL:47:57+6+42-$fe+6 == RL:47:69+42-$fe == RL:48:8+40-$fe

  // Make *this* raster line (i.e. raster line 48) be a Bad Line
  // => This triggers the VSP/DMA delay of $fe cycles.
  lda #$18  //(2,RL:48:(8+2+40-$fe)) %0001:1000
  sta $D011 //(4,RL:48:(10+4+40-$fe) = RL:48:54-$fe)

  //...because raster line 48 is forced into a bad line, a VSP scroll
  // is triggered, so the CPU is stun until cycle 54...

  // ...so we can reset $D011 to use $1B as soon as we can: this way
  // we make sure that by the end of raster line 48, YSCROLL is
  // back to its default value 3, and we are ready for the next frame.
  lda #$1B  //(2, RL:48:(54-$fe+2))
  sta $D011 //(4, RL:48:(56-$fe+4) = RL:48:60-$fe)

  //Make the screen scroll
  //(r2l if $ff is 0, or l2r if $ff is $ff.)
  lda $ff
//  cmp #0
  bne scroll_left_to_right
  inc $fe
  lda $fe
  cmp #40
  bne exiting_irq1
  lda #0
  sta $fe
  jmp exiting_irq1
scroll_left_to_right:
  dec $fe
  lda $fe
  cmp #$ff
  bne exiting_irq1
  lda #39
  sta $fe

exiting_irq1:
  asl vic2_interrupt_status_register
  :set_raster(RASTER_LINE)
  :mov16 #irq1 : $fffe
  rti

.align $100 //Align to the nearest page boundary
//Actual delay in cycles is 40+2-$fe = 42-$fe
//See https://bumbershootsoft.wordpress.com/2014/05/04/cycle-exact-delays-on-the-6502/
NDelay: //(0->42 ; 1->41 ; ... ; 39->3 ; 40->2) Notice that input+output is always 42
.byte $c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9
.byte $c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9
.byte $c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9
.byte $c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9
.byte $c5 //(3)
      nop //(2)
      rts //(6)