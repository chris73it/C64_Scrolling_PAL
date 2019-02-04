#importonce

#import "helpers.asm"

/*
 * Wait functions.
*/

// Waits 23 cycles minus 12 cycles for the caller's jsr and this function's rts.
wait_one_bad_line: //+6
  :cycles(-6+23-6) // 23-12
  rts //+6
wait_one_bad_line_minus_3: //+6
  :cycles(-6+23-3-6) //20-12
  rts //+6

// Waits 63 cycles minus 12 cycles for the caller's jsr and this function's rts.
wait_one_good_line: //+6
  :cycles(-6+63-6) // 63-12
  rts //+6

// Waits 63 cycles minus 12 cycles for the caller's jsr and this function's rts, and
// further minus 12 cycles for the caller's caller's jsr and corresponding rts.
// Basically this wait function is meant to be called from another wait function.
wait_one_good_line_minus_jsr_and_rts: //+6
  :cycles(-6-6+63-6-6) // 63-24
  rts //+6

// Waits 63 cycles minus 12 cycles for the caller's jsr and this function's rts, and
// further minus 12 cycles for the caller's caller's jsr and corresponding rts.
// Basically this wait function is meant to be called from another wait function.
wait_6_good_lines: //+6
  jsr wait_one_good_line // 1: 63-12+6+6 = 63
  jsr wait_one_good_line // 2: 63-12+6+6 = 63
  jsr wait_one_good_line // 3: 63-12+6+6 = 63
  jsr wait_one_good_line // 4: 63-12+6+6 = 63
  jsr wait_one_good_line // 5: 63-12+6+6 = 63
  // 6: Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 6: 63-12
  rts //+6

// Wait one entire row worth of cycles minus the 12 cycles to call this function.
wait_1_row_with_20_cycles_bad_line: //+6
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6

// Wait two full rows worth of cycles minus the 12 cycles to call this function.
wait_2_rows_with_20_cycles_bad_lines: //+6
  jsr wait_1_row_with_20_cycles_bad_line
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6

wait_4_rows_with_20_cycles_bad_lines: //+6
  jsr wait_2_rows_with_20_cycles_bad_lines
  jsr wait_1_row_with_20_cycles_bad_line
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6

wait_8_rows_with_20_cycles_bad_lines: //+6
  jsr wait_4_rows_with_20_cycles_bad_lines
  jsr wait_2_rows_with_20_cycles_bad_lines
  jsr wait_1_row_with_20_cycles_bad_line
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6
