#import "helpers.asm"

.label border = $d020
.label background = $d021

.label cia1_interrupt_control_register = $dc0d
.label cia2_interrupt_control_register = $dd0d

// Note: the '-2' is required because stabilize_irq() takes 2 raster
// lines to synchronize the raster. More precisely, it _always_ ends
// after completing the 3rd cycle of raster line number RASTER_LINE.
.const RASTER_LINE_47 = (48-1)-2 //We want to "land" at RL:47:03.
.const RASTER_LINE_251 = 251 //No need to be cycle exact, so RL:251.

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
    lda #BLACK
    sta border
    sta background

    //Place the screen as right as possible by setting XSCROLL = 7.
    //Notice that we are also setting screen width to 38 columns.
    lda #$C7
    sta $D016

    //Here we are simply emphasizing that $D011 is set at its default
    // value, and this means YSCROLL is 3, and that the first bad line is
    // 51. Since it is a good line, raster line 48 can be made into a bad
    // line by tinkering with $D011.
    // If it were a bad line to start with, it wouldn't be possible
    // to _change_ it into one: this change is what we call DMA delay.
    // Then immediately after, we restore raster line 51 to be the next
    // bad line.
    lda #$1B
    sta $D011

    //By default, we start with the screen in neutral position,
    //i.e., no column is scrolled. The valid values for $FE are:
    //[0:39] is 40 different positions for horizontal scrolling.
    //   40  is the "scrolled up" position (not used in this demo.)

    //Notice that the initial value for $FE can only be either 0 or 39,
    // that is because we use 0 in $FF to mean "right to left".
    lda #0 //By default we scroll right to left (so $ff will be 0)
    sta $FE
//  cmp #0 //Right to left?
    beq finalize_scroll_dir 
left2rigth:
    lda #$FF //Scroll left to right (TODO: not implemented yet!)
finalize_scroll_dir:
    sta $FF

    //$FD keeps track of which screen is the primary and which one
    // is the one used as double buffer.
    lda #0  //First screen is primary (1: second screen is primary)
    sta $FD
    //cmp #0 //First screen is primary
    bne ssip //Second screen is primary
  fsip: //First screen is primary (default $0400: no need to activate)
    jmp init_screen
  ssip:
    jsr activate_second_buffer

init_screen:
    init_screen_ram()

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
    :set_raster(RASTER_LINE_47)
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

  ldy $FE      //(3, RL:47:06)
  sty ndelay+1 //(4, RL:47:10) Set $FE cycles into LSB NDelay's address
  :cycles(-3-3-4 +63 -6) //RL:47:57
ndelay:
  //Notice that sty above is writing into the LSB of the NDelay address
  jsr NDelay //RL:47:57+6+42-$FE+6 == RL:47:69+42-$FE == RL:48:8+40-$FE

  // Make *this* raster line (i.e. raster line 48) be a Bad Line
  // => This triggers the VSP/DMA delay of $FE cycles.
  lda #$18  //(2,RL:48:(8+2+40-$FE)) %0001:1000
  sta $D011 //(4,RL:48:(10+4+40-$FE) = RL:48:54-$FE)

  //...because raster line 48 is forced into a bad line, a VSP scroll
  // is triggered, so the CPU is stun until cycle 54...

  // ...so we can reset $D011 to use $1B as soon as we can: this way
  // we make sure that by the end of raster line 48, YSCROLL is
  // back to its default value 3, and we are ready for the next frame.
  lda #$1B  //(2, RL:48:(54-$FE+2))
  sta $D011 //(4, RL:48:(56-$FE+4) = RL:48:60-$FE)

exiting_irq1_to_irq2:
  asl vic2_interrupt_status_register
  :set_raster(RASTER_LINE_251)
  :mov16 #irq2 : $fffe
  rti

irq2:
//jmp exiting_irq2
  //Check XSCROLL and decrease it
  lda $D016
  and #$07
  beq reset_xscroll_back_to_7
  dec $D016
  jmp exiting_irq2_to_irq1
reset_xscroll_back_to_7:
  //Set XSCROLL back to 7.
  lda #$C7
  sta $D016

primary_screen:
  //Check what screen is primary
  lda $FD
  //cmp #0 //First screen is primary
  bne second_screen_is_primary

first_screen_is_primary:
  lda $FE
  cmp #24
  bcs first_from_24_to_39 //Accumulator >= 24?
first_from_0_to_23:
  jsr first_screen_is_primary_shift_column_0_23_down
  jmp scroll_screen
first_from_24_to_39:
  jsr first_screen_is_primary_shift_column_24_39_down
  lda $FE
  cmp #39 //Time to switch to the second buffer?
  bne scroll_screen
  jsr activate_second_buffer
  jmp scroll_screen

second_screen_is_primary:
  lda $FE
  cmp #24
  bcs second_from_24_to_39 //Accumulator >= 24?
second_from_0_to_23:
  jsr second_screen_is_primary_shift_column_0_23_down
  jmp scroll_screen
second_from_24_to_39:
  jsr second_screen_is_primary_shift_column_24_39_down
  lda $FE
  cmp #39 //Time to switch to the second buffer?
  bne scroll_screen
  jsr activate_first_buffer

scroll_screen:
  jsr make_screen_scroll

exiting_irq2_to_irq1:
  asl vic2_interrupt_status_register
  :set_raster(RASTER_LINE_47)
  :mov16 #irq1 : $fffe
  rti

activate_second_buffer:
  lda #1
  sta $FD //Make second screen primary
  lda $D018
  and #$0F
  ora #$80 //$2000
  sta $D018
  rts

activate_first_buffer:
  lda #0
  sta $FD //Make first screen primary
  lda $D018
  and #$0F
  ora #$10 //$0400
  sta $D018
  rts

first_screen_is_primary_shift_column_0_23_down:
  ldx $FE
  clc
  lda $FE
  adc #33 //in PETSCII 33 is the character code for '!'
  //Second screen (now it is being used for double buffering)
  sta $2000,x //1st row
  sta $2028,x //2nd row
  sta $2050,x
  sta $2078,x
  sta $20A0,x
  sta $20C8,x
  sta $20F0,x
  sta $2118,x
  sta $2140,x
  sta $2168,x
  sta $2190,x
  sta $21B8,x
  sta $21E0,x
  sta $2208,x
  sta $2230,x
  sta $2258,x
  sta $2280,x
  sta $22A8,x
  sta $22D0,x
  sta $22F8,x
  sta $2320,x
  sta $2348,x
  sta $2370,x
  sta $2398,x
  sta $23C0,x //25th row
  //First (current) screen
  sta $0428,x //2nd row
  sta $0450,x
  sta $0478,x
  sta $04A0,x
  sta $04C8,x
  sta $04F0,x
  sta $0518,x
  sta $0540,x
  sta $0568,x
  sta $0590,x
  sta $05B8,x
  sta $05E0,x
  sta $0608,x
  sta $0630,x
  sta $0658,x
  sta $0680,x
  sta $06A8,x
  sta $06D0,x
  sta $06F8,x
  sta $0720,x
  sta $0748,x
  sta $0770,x
  sta $0798,x
  sta $07C0,x //25th row
  sta $07E8,x //26th row
exiting_first_screen_is_primary_shift_column_0_23_down:
   rts

first_screen_is_primary_shift_column_24_39_down:
  ldx $FE
  clc
  lda $FE
  adc #33 //33 is PETSCII for '!'
  //Second screen (now it is being used for double buffering)
  sta $2000,x //1st row
  sta $2028,x //2nd row
  sta $2050,x
  sta $2078,x
  sta $20A0,x
  sta $20C8,x
  sta $20F0,x
  sta $2118,x
  sta $2140,x
  sta $2168,x
  sta $2190,x
  sta $21B8,x
  sta $21E0,x
  sta $2208,x
  sta $2230,x
  sta $2258,x
  sta $2280,x
  sta $22A8,x
  sta $22D0,x
  sta $22F8,x
  sta $2320,x
  sta $2348,x
  sta $2370,x
  sta $2398,x
  sta $23C0,x //25th row
  //First (current) screen
  sta $0428,x //2nd row
  sta $0450,x
  sta $0478,x
  sta $04A0,x
  sta $04C8,x
  sta $04F0,x
  sta $0518,x
  sta $0540,x
  sta $0568,x
  sta $0590,x
  sta $05B8,x
  sta $05E0,x
  sta $0608,x
  sta $0630,x
  sta $0658,x
  sta $0680,x
  sta $06A8,x
  sta $06D0,x
  sta $06F8,x
  sta $0720,x
  sta $0748,x
  sta $0770,x
  sta $0798,x
  sta $07C0,x //25th row
  //The x index is offset by -33-24 compared to its current value so far
  sec
  sbc #33+24 //33 are for the '!', and 24 are for the column's offset
  tax //Now x is 24 less than $FE
  //Fix first row
  clc
  lda $FE
  adc #33 //33 is PETSCII for '!'
  sta $0400,x //1st row
  //TRICK for this demo: fix color using a color on the same x column
  ldy $FE
  lda $D800,y
  sta $D800,x
exiting_first_screen_is_primary_shift_column_24_39_down:
   rts

second_screen_is_primary_shift_column_0_23_down:
  ldx $FE
  clc
  lda $FE
  adc #33 //33 is PETSCII for '!'
  //First screen (here is being used for double buffering)
  sta $0400,x //1st row
  sta $0428,x //2nd row
  sta $0450,x
  sta $0478,x
  sta $04A0,x
  sta $04C8,x
  sta $04F0,x
  sta $0518,x
  sta $0540,x
  sta $0568,x
  sta $0590,x
  sta $05B8,x
  sta $05E0,x
  sta $0608,x
  sta $0630,x
  sta $0658,x
  sta $0680,x
  sta $06A8,x
  sta $06D0,x
  sta $06F8,x
  sta $0720,x
  sta $0748,x
  sta $0770,x
  sta $0798,x
  sta $07C0,x //25th row
  //Second (current) screen
  sta $2028,x //2nd row
  sta $2050,x
  sta $2078,x
  sta $20A0,x
  sta $20C8,x
  sta $20F0,x
  sta $2118,x
  sta $2140,x
  sta $2168,x
  sta $2190,x
  sta $21B8,x
  sta $21E0,x
  sta $2208,x
  sta $2230,x
  sta $2258,x
  sta $2280,x
  sta $22A8,x
  sta $22D0,x
  sta $22F8,x
  sta $2320,x
  sta $2348,x
  sta $2370,x
  sta $2398,x
  sta $23C0,x //25th row
  sta $23E8,x //26th row
exiting_second_screen_is_primary_shift_column_0_23_down:
   rts

second_screen_is_primary_shift_column_24_39_down:
  ldx $FE
  clc
  lda $FE
  adc #33 //33 is PETSCII for '!'
  //First screen (here it is being used for double buffering)
  sta $0400,x //1st row
  sta $0428,x //2nd row
  sta $0450,x
  sta $0478,x
  sta $04A0,x
  sta $04C8,x
  sta $04F0,x
  sta $0518,x
  sta $0540,x
  sta $0568,x
  sta $0590,x
  sta $05B8,x
  sta $05E0,x
  sta $0608,x
  sta $0630,x
  sta $0658,x
  sta $0680,x
  sta $06A8,x
  sta $06D0,x
  sta $06F8,x
  sta $0720,x
  sta $0748,x
  sta $0770,x
  sta $0798,x
  sta $07C0,x //25th row
  //Second (current) screen
  sta $2028,x //2nd row
  sta $2050,x
  sta $2078,x
  sta $20A0,x
  sta $20C8,x
  sta $20F0,x
  sta $2118,x
  sta $2140,x
  sta $2168,x
  sta $2190,x
  sta $21B8,x
  sta $21E0,x
  sta $2208,x
  sta $2230,x
  sta $2258,x
  sta $2280,x
  sta $22A8,x
  sta $22D0,x
  sta $22F8,x
  sta $2320,x
  sta $2348,x
  sta $2370,x
  sta $2398,x
  sta $23C0,x //25th row
  //The x index is offset by -33-24 compared to its current value so far
  sec
  sbc #33+24 //33 are for the '!', and 24 are for the column's offset
  tax //Now x is 24 less than $FE
  //Fix first row
  clc
  lda $FE
  adc #33 //33 is PETSCII for '!'
  sta $2000,x //1st row
  //TRICK for this demo: fix color using a color on the same x column
  ldy $FE
  lda $D800,y
  sta $D800,x
exiting_second_screen_is_primary_shift_column_24_39_down:
   rts

make_screen_scroll:
  lda $FF
//  cmp #0 //right to left?
  bne scroll_left_to_right
scroll_right_to_left:
  inc $FE
  lda $FE
  cmp #39+1
  bne exiting_make_screen_scroll
  lda #0
  sta $FE
  jmp exiting_make_screen_scroll
scroll_left_to_right:
  dec $FE
  lda $FE
  cmp #$FF //Equivalent to -1, i.e. 0 decremented by 1
  bne exiting_make_screen_scroll
  lda #39
  sta $FE
exiting_make_screen_scroll:
  rts

.align $100 //Align to the nearest page boundary
//Actual delay in cycles is 40+2-$FE = 42-$FE
//See https://bumbershootsoft.wordpress.com/2014/05/04/cycle-exact-delays-on-the-6502/
NDelay: //(0->42 ; 1->41 ; ... ; 39->3 ; 40->2) Notice that input+output is always 42
.byte $c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9
.byte $c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9
.byte $c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9
.byte $c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9,$c9
.byte $c5 //(3)
      nop //(2)
      rts //(6)