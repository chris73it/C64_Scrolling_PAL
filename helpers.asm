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

.macro clear_screen(char_code) {
  ldx #0
  lda #char_code
clear_next_char:
  sta screen_0,x
  sta screen_1,x
  sta screen_2,x
  sta screen_3,x
  inx
  bne clear_next_char
}

.macro randomize_screen() {
  // Place some chars on screen memory.
  ldx #0 //column index
  lda #0 // char index
next_char:
  cmp #32 //Skip the blank character..
  bne ok
  lda #33//..by using the next character code
ok:
  .for (var row = 0; row < 25; row++) {
    sta screen + row * 40,x
  }
  inx
  txa
  cpx #40
  bne next_char

  // Place some colors in color memory.
  ldx #0 //column index
  ldy #BLACK+1 //color index
  lda #BLACK+1 //char color (numerically same as y)
next_color:
  .for (var row = 0; row < 25; row++) {
    sta colorRam + row * 40,x
  }
  iny
  cpy #16
  bne continue
  ldy #BLACK+1
continue:
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
