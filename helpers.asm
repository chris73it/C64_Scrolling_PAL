#importonce

.const colorRam = $d800
.const screen = $0400
.const screen_0 = $0400
.const screen_0_40 = $0428
.const screen_1 = $0500
.const screen_2 = $0600
.const screen_3 = $0700

.const NAS = 1

.label vic2_screen_control_register1 = $d011
.label vic2_screen_control_register2 = $d016
.label vic2_rasterline_register = $d012
.label vic2_interrupt_control_register = $d01a
.label vic2_interrupt_status_register = $d019

.macro stabilize_irq() {
  start:
    :mov16 #irq2 : $fffe
    inc vic2_rasterline_register
    asl vic2_interrupt_status_register
    tsx
    cli

    :cycles(18)

  irq2:
    txs
    :cycles(44)
  test:
    lda vic2_rasterline_register
    cmp vic2_rasterline_register
    beq next_instruction
  next_instruction:
}

.macro set_raster(line_number) {
  // Notice that only the 8 least significant bits are stored in the accumulator.
  lda #line_number
  sta vic2_rasterline_register

  lda vic2_screen_control_register1
  .if (line_number > 255) {
    ora #%10000000
  } else {
    and #%01111111
  }
  sta vic2_screen_control_register1
}

.pseudocommand mov16 source : destination {
  :_mov bits_to_bytes(16) : source : destination
}
.pseudocommand mov source : destination {
  :_mov bits_to_bytes(8) : source : destination
}
.pseudocommand _mov bytes_count : source : destination {
  .for (var i = 0; i < bytes_count.getValue(); i++) {
    lda extract_byte_argument(source, i) 
    sta extract_byte_argument(destination, i) 
  } 
}
.pseudocommand _add bytes_count : left : right : result {
  clc
  .for (var i = 0; i < bytes_count.getValue(); i++) {
    lda extract_byte_argument(left, i) 
    adc extract_byte_argument(right, i) 
    sta extract_byte_argument(result, i)
  } 
}

.function extract_byte_argument(arg, byte_id) {
  .if (arg.getType()==AT_IMMEDIATE) {
    .return CmdArgument(arg.getType(), extract_byte(arg.getValue(), byte_id))
  } else {
    .return CmdArgument(arg.getType(), arg.getValue() + byte_id)
  }
}
.function extract_byte(value, byte_id) {
  .var bits = _bytes_to_bits(byte_id)
  .eval value = value >> bits
  .return value & $ff
}
.function _bytes_to_bits(bytes) {
  .return bytes * 8
}
.function bits_to_bytes(bits) {
  .return bits / 8
}

//Clears the screen using the blank (' ') character.
//Notice that we also clean up the extra 24 bytes after the first 1000,
//in fact, we even clean up 16 extra chatacters: this is done for
//simplicity, but on production code you should probably refrain from
//cleaning up those 16 bytes as well.
.macro clear_screen(filler) {
  lda #filler //PETSCII for blank (' ') character
  ldx #0  //column index
repeat:
  .for (var row = 0; row < 25+1; row++) {
    sta screen + row * 40, x
  }
  inx
  cpx #40
  bne repeat
}

.macro randomize_screen() {
  //randomize character codes
  ldx #0  //column index
!repeat: //The exclamation point is necessary because 'repeat' is a duplicated label
  txa
  adc #33 //33 is the PETSCII char code for exclamation point '!' character
  .for (var row = 0; row < 25+1; row++) {
    sta screen + row * 40, x
  }
  inx
  cpx #40
  bne !repeat- //The minus means "go to the previous 'repeat' label"

  //randomize colors
  ldx #0  //column index
!repeat: //The exclamation point is necessary because 'repeat' is a duplicated label
  txa
  adc #33 //33 is the PETSCII char code for exclamation point '!' character
  .for (var row = 0; row < 25+1; row++) {
    sta colorRam + row * 40, x
  }
  inx
  cpx #40
  bne !repeat- //The minus means "go to the previous 'repeat' label"
}

//Place blank chars on the first ($0400) and the second ($2000) screen.
.macro init_screen_ram() {
  lda #32 //in PETSCII 32 is the character code for blank/whitespace
  ldx #0  //column index
!ok:
  //We want to also initialize the 24 hidden bytes after the first
  // normally visible 1000 bytes: we actually overflow by 16 bytes: this
  // is ok since this demo is a proof of concept of how to implement VSP,
  // but on a real game you should probably fix that.)
  .for (var row = 0; row < 25+1; row++) {
    sta $0400 + row * 40,x
  }
  inx
  cpx #40
  bne !ok-

  ldx #0  //column index
!ok:
  //We want to also initialize the 24 hidden bytes after the first
  // normally visible 1000 bytes: we actually overflow by 16 bytes: this
  // is ok since this demo is a proof of concept of how to implement VSP,
  // but on a real game you should probably fix that.)
  .for (var row = 0; row < 25+1; row++) {
    sta $2000 + row * 40,x
  }
  inx
  cpx #40
  bne !ok-

  // Place certain colors in color memory.
  ldx #0 //column index
  ldy #BLACK+1 //color index
  lda #BLACK+1 //char color (numerically same as y)
next_color:
  .for (var row = 0; row < 25+1; row++) {
    sta colorRam + row * 40,x
  }
  iny
  cpy #8+1 //We only use 8 colors, because 8 divides both 16 and 24
           // and we do not need to bend head over hills just to make
           // this demo look right (the gosl here is to show how VSP
           // works, and not implement a full blown scroller: said that
           // it should be easy to add a tiler system for the new
           // graphics that enters from the right side of the screen.)
  bne !ok+
  ldy #BLACK+1 //roll back to WHITE
!ok:
  tya
  inx
  cpx #40
  bne next_color
}

.macro nops(count) {
  .for (var i = 0; i < count; i++) {
    nop
  }
}

.macro cycles(count) {
  .if (count < 0) {
    .error "The cycle count cannot be less than 0 (" + count + " given)." 
  }
  .if (count == 1) {
    .error "Can't wait only one cycle." 
  }
  .if (mod(count, 2) != 0) {
    bit $ea
    .eval count -= 3 
  }
  :nops(count/2)
}
