z80code:
	.assume adl=0
	.org 0
r_bits:
	ex af,af'
	ex (sp),hl
	ld a,(hl)
	inc hl
	ex (sp),hl
	jp do_bits
	
	.block $08-$
r_mem:
	di
	pop ix
	push af
	 jp decode_mem
	
	.block $10-$
r_cycle_check:
	ex af,af'
	ld a,iyh
	or a
	ret nz
	jp cycle_overflow_for_jump
	
	.block $18-$
r_push:
	pop ix
	exx
	pop de
	jr do_push
	
	.block $20-$
r_pop:
	exx
	ld.l ix,(hl)
	ex (sp),ix
	jr do_pop
	
	.block $28-$
r_call:
	pop ix
	exx
	djnz do_call
	jr do_call_reset_callstack
	
	.block $30-$
r_event:
	ex af,af'
	pop ix
	dec ix
	jp do_event
	
	.block $38-$
r_invalid_opcode:
rst38h:
	push af
	 ld a,i
	 jp pe,Z80InvalidOpcode
	 ld.lil a,(mpLcdMis)
	 or a
	 jp.lil nz,frame_interrupt
	 ;ld.lil a,(mpIntMaskedStatus)
	 ;rra
	 ;jr nc,$
	
on_interrupt:
	 inc a
	 ld.lil (mpIntAcknowledge),a
	 inc a
	 ld.lil (exitReason),a
frame_interrupt_return:
	pop af
	ei
	ret
	 
Z80InvalidOpcode:
	di
	jp.lil Z80InvalidOpcode_helper
	
Z80Error:
	di
	jp.lil runtime_error
	
do_push_and_return:
	pop ix
do_push:
	dec.l hl
do_push_smc_1 = $+1
	ld.l (hl),d
	dec.l hl
do_push_smc_2 = $+1
	ld.l (hl),e
	exx
	jp (ix)
	
do_pop:
	inc.l hl
	inc.l hl
	exx
	jp (ix)
	
ophandlerRETnobank:
	ld c,b	;C is now at least 2
	ld de,(ix-2)
	ld a,e
	cpi.l
	jr nz,ophandlerRETnomatch_dec
	ld a,d
	cpi.l
	jr nz,ophandlerRETnomatch_dec2
	ld a,(ix-3)
dispatch_cycles_for_ret:
	ld (dispatch_cycles_for_ret_smc),a
dispatch_cycles_for_ret_smc = $+2
	lea iy,iy+0
	ld a,iyh
	or a
	jr z,cycle_overflow_for_ret
	exx
	ex af,af'
	jp (ix)
	
do_call_reset_callstack:
	ld b,CALL_STACK_DEPTH
	ld.lil sp,myADLstack
	ld sp,myz80stack-2
do_call:
	pea ix+7
	ex af,af'
	ld de,(ix+5)
	ld a,(ix+2)
do_call_common:
	ld ix,(ix)
	dec.l hl
do_push_smc_3 = $+1
	ld.l (hl),d
	dec.l hl
do_push_smc_4 = $+1
	ld.l (hl),e
	push.l hl
	call dispatch_cycles_for_call
call_stack_ret:
	ex af,af'
	exx
	pop.l de
	inc b
	xor a
	sbc.l hl,de
	add.l hl,de
	jr nz,ophandlerRETskip
	pop ix
	or (ix-4)
	jr z,ophandlerRETnobank
rom_bank_check_smc_3 = $+1
	xor 0
	jr z,ophandlerRETnobank
	jr ophandlerRETnomatch
	
ophandlerRETskip:
	jr c,ophandlerRETsave
	pop de
	exx
	ex af,af'
	ret
	
ophandlerRETsave:
	push.l de
	ld de,call_stack_ret
	push de
	djnz ophandlerRETnomatch	; B > 1 so always taken
	
ophandlerRETnomatch_dec2:
	dec.l hl
ophandlerRETnomatch_dec:
	dec.l hl
ophandlerRETnomatch:
	push bc
	 di
	 call.il pop_and_lookup_code_cached
	 ei
	pop bc
	add a,4
	jr dispatch_cycles_for_ret
	
cycle_overflow_for_ret:
	ld a,(dispatch_cycles_for_ret_smc)
	push de
	 exx
	 ex (sp),hl
	 push de
	  push bc
	   ex de,hl
	   sub 4
	   ld c,a
	   push ix
	    di
	    jp.lil schedule_event_helper
	
do_rom_bank_call:
	ex af,af'
	exx
	pop ix
	ex (sp),ix
	ld de,(ix)
rom_bank_check_smc_1 = $+1
	ld a,0
	cp d
	jr nz,banked_call_mismatch
	ld a,e
banked_call_mismatch_continue:
	ld de,(ix+3)
	lea ix,ix+5
	ex (sp),ix
	djnz do_call_common
	ld.lil sp,myADLstack
	pop bc
	ld sp,myz80stack-2
	push bc
	ld b,CALL_STACK_DEPTH
	jp do_call_common
	
dispatch_cycles_for_call:
	add a,iyl
	jr c,++_
_
	ld iyl,a
	exx
	ex af,af'
	jp (ix)
_
	inc iyh
	jr nz,--_
	push de
	 exx
	 ex (sp),hl
	 push de
	  push bc
	   ex de,hl
	   dec de
	   ld c,iyl
	   ld iyl,a
	   sub c
	   sub 6
	   ld c,a
	   push ix
	    di
	    jp.lil schedule_call_event_helper
	
banked_call_mismatch:
	di
	jp.lil banked_call_mismatch_helper
	
do_rom_bank_jump:
	ex af,af'
	pop ix
rom_bank_check_smc_2 = $+1
	ld a,0
	xor (ix+3)
	jr nz,banked_jump_mismatch
	ld a,(ix+4)
banked_jump_mismatch_continue:
	add a,iyl
	ld iyl,a
	jr c,++_
_
	ex af,af'
	jp (ix)
_
	inc iyh
	jr nz,--_
	push hl
	 push de
	  push bc
	   ld b,(ix)
	   ld c,(ix+4)
	   ld de,(ix+5)
	   ld ix,(ix+1)
	   jr schedule_jump_event_helper_trampoline
	
banked_jump_mismatch:
	di
	jp.lil banked_jump_mismatch_helper
	
cycle_overflow_for_jump:
	pop ix
	push hl
	 push de
	  push bc
	   ld b,(ix+1)
	   ld c,(ix-2)
	   ld a,b
	   xor $C3
	   jr z,_
	   and $E7
	   dec a
	   jr nz,++_
_
	   ld de,(ix+4)
	   ld ix,(ix+2)
schedule_jump_event_helper_trampoline:
	   push ix
	    di
	    jp.lil schedule_jump_event_helper
_
	   ld de,(ix-6)
	   inc ix
	   push ix
	    di
	    jp.lil schedule_subblock_event_helper
	   
schedule_event_finish:
	    ld (event_cycle_count),a
	    ld (event_gb_address),hl
#ifdef DEBUG
	    ld a,(event_address+1)
	    cp event_value >> 8
	    jr nz,$
#endif
	    lea hl,ix
	    ld (event_address),hl
	    ld a,(hl)
	    ld (event_value),a
	    ld (hl),RST_EVENT
schedule_event_finish_no_schedule:
	   pop ix
	  pop bc
	 pop de
	pop hl
	ex af,af'
	jp (ix)
	
	
do_event:
event_value = $+3
	ld (ix),0
	push hl
do_event_pushed:
	 ld hl,event_value
	 ld (event_address),hl
do_event_pushed_no_reset:
	 push de
	  xor a
event_cycle_loop:
event_cycle_count = $+2
	  lea hl,iy+0
	  or h
	  jr nz,not_expired

	  ld (event_save_sp),sp
	  di
	  ld sp,event_counter_checkers

	  ; At least one event expired
	  ld l,h
vblank_counter = $+1
	  ld de,0
	  sbc hl,de
	  ex de,hl
	  ret nz
	  jp.lil vblank_helper

event_counter_checkers_done:
	  ei
event_save_sp = $+1
	  ld sp,0

serial_counter = $+1
	  ld hl,0
	  add hl,de
	  ld (serial_counter),hl
timer_counter = $+1
	  ld hl,0
	  add hl,de
	  ld (timer_counter),hl
stat_counter = $+1
	  ld hl,0
	  add hl,de
	  ld (stat_counter),hl
lyc_counter = $+1
	  ld hl,0
	  add hl,de
	  ld (lyc_counter),hl
div_counter = $+1
	  ld hl,0
	  add hl,de
	  ld (div_counter),hl
	  ld hl,(vblank_counter)
	  add hl,de
	  ld (vblank_counter),hl
	  xor a
	  sbc hl,hl
	  sbc hl,de
	  ex de,hl
	  add iy,de
	  jr event_cycle_loop
	   
not_expired:
	  ld hl,IE
	  ld a,(hl)
	  ld l,IF - ioregs
intstate_smc:
	  and (hl)
	  jr nz,trigger_interrupt
	  cp iyh
	  jr z,event_reschedule
	 pop de
	pop hl
	ex af,af'
	jp (ix)
	   
event_reschedule:
	  push bc
	   ld de,(event_gb_address)
	   ld a,(event_cycle_count)
	   neg
	   ld c,a
	   push ix
	    di
	    jp.lil schedule_event_helper
	
trigger_interrupt:
	  push bc
	   rrca
	   jr c,trigger_vblank
	   rrca
	   jr c,trigger_stat
	   rrca
	   jr c,trigger_timer
	   rrca
	   jr c,trigger_serial
trigger_joypad:
	   res 4,(hl)
	   ld hl,dispatch_joypad
	   jr trigger_int_selected
trigger_serial:
	   res 3,(hl)
	   ld hl,dispatch_serial
	   jr trigger_int_selected
trigger_timer:
	   res 2,(hl)
	   ld hl,dispatch_timer
	   jr trigger_int_selected
trigger_stat:
	   res 1,(hl)
	   ld hl,dispatch_stat
	   jr trigger_int_selected
trigger_vblank:
	   res 0,(hl)
	   ld hl,dispatch_vblank
trigger_int_selected:
	
	   push hl
	    ld a,$AF ;XOR A
	    ld (intstate_smc),a
	    exx
event_gb_address = $+1
	    ld de,event_gb_address
	    ; If we're on a HALT, exit it
cpu_halted = $+1
	    and 0
	    ld a,(event_cycle_count)
	    ld c,a
	    di
	    jp.lil z,dispatch_int_helper
	    ld (cpu_halted),a
	    ld c,a
	    inc a
	    sub (ix+3)
	    lea ix,ix+6
	    inc de
	    jp.lil dispatch_int_helper

dispatch_int_continue:
	    call do_push_and_return
	   pop ix
	   add a,(ix+3)
dispatch_int_decoded:
	   ld (_+2),a
_
	   lea iy,iy+0
	   xor a
	   cp iyh
	   jr z,_
	  pop bc
	 pop de
	pop hl
	ex af,af'
	jp (ix)
_
	   inc de
	   ld d,a
	   ld a,ixl
	   sub (dispatch_vblank & $FF) - $20
	   add a,a
	   ld e,a
	   ld a,(ix+2)
	   cp decode_intcache >> 8
	   jr z,decode_intcache_from_overflow
	   ld a,(ix+3)
	   sub 5
	   ld c,a
	   ld ix,(ix+1)
	   push ix
	    di
	    jp.lil schedule_event_helper

dispatch_vblank:
	jp decode_intcache
	.db 0
dispatch_stat:
	jp decode_intcache
	.db 0
dispatch_timer:
	jp decode_intcache
	.db 0
dispatch_serial:
	jp decode_intcache
	.db 0
dispatch_joypad:
	jp decode_intcache
	.db 0
rst_cached_targets:
	.dl $00
	.dl $08
	.dl $10
	.dl $18
	.dl $20
	.dl $28
	.dl $30
	.dl $38
	
decode_intcache:
	ex af,af'
	push hl
	 push de
	  push bc
	   ld d,a
	   ld a,ixl
	   sub (dispatch_vblank & $FF) - $20
	   add a,a
	   ld e,a
decode_intcache_from_overflow:
	   di
	   call.il decode_intcache_helper
	   ld (ix+1),hl
	   ld (ix+3),a
	   jr dispatch_int_decoded
	
	
lyc_counter_checker:
	ld hl,(lyc_counter)
	ld a,h
	or l
	jr z,lyc_expired_handler
	add hl,de
	ret nc
	ex de,hl
	or a
	sbc hl,de
	ex de,hl
	ret
	
lyc_expired_handler:
	ld hl,LCDC
	bit 7,(hl)
	jr z,_
	ld l,IF & $FF
	set 1,(hl)
_
	ld hl,-CYCLES_PER_FRAME
	ld (lyc_counter),hl
	; Special case, DE cannot exceed CYCLES_PER_FRAME so this cannot replace it
	ret
	
stat_counter_checker_single:
	ld hl,(stat_counter)
	ld a,h
	or l
	jr nz,stat_not_expired_single
	ld hl,IF
	set 1,(hl)
stat_line_count_single_smc = $+1
	ld a,144
	dec a
	jr z,stat_counter_single_skip_vblank
	ld (stat_line_count_single_smc),a
	ld l,-CYCLES_PER_SCANLINE
	ld (stat_counter),hl
	add hl,de
	ret nc
	ld de,CYCLES_PER_SCANLINE
	ret
	
stat_counter_single_skip_vblank:
	ld a,144
	ld (stat_line_count_single_smc),a
	ld hl,-(CYCLES_PER_SCANLINE * 11)
	ld (stat_counter),hl
stat_not_expired_single:
	add hl,de
	ret nc
	ex de,hl
	or a
	sbc hl,de
	ex de,hl
	ret
	
	
stat_mode0_expired_handler:
	ld hl,IF
	set 1,(hl)
stat_line_count_double_smc = $+1
	ld a,144
	dec a
	jr z,stat_counter_double_skip_vblank
	ld l,-MODE_0_CYCLES
stat_update_line_counter_double:
	ld (stat_line_count_double_smc),a
	ld (stat_counter),hl
	call stat_double_swap_modes
stat_counter_checker_mode2:
	ld hl,(stat_counter)
	ld a,h
	or l
	jr nz,stat_not_expired_double
	ld hl,IF
	set 1,(hl)
	ld l,-(MODE_2_CYCLES + MODE_3_CYCLES)
	ld (stat_counter),hl
	call stat_double_swap_modes
stat_counter_checker_mode0:
	ld hl,(stat_counter)
	ld a,h
	or l
	jr z,stat_mode0_expired_handler
	.db $CA ;JP Z (skip next two bytes)
stat_double_swap_modes:
	inc sp
	inc sp
stat_not_expired_double:
	add hl,de
	ret nc
	ex de,hl
	or a
	sbc hl,de
	ex de,hl
	ret
	
stat_counter_double_skip_vblank:
	ld a,144
	ld hl,-(CYCLES_PER_SCANLINE * 10 + MODE_0_CYCLES)
	jr stat_update_line_counter_double

timer_counter_checker:
	ld hl,(timer_counter)
	ld a,h
	or l
	jr z,timer_expired_handler
	add hl,de
	ret nc
	ex de,hl
	or a
	sbc hl,de
	ex de,hl
	ret
	
timer_expired_handler:
	ld hl,IF
	set 2,(hl)
	ld l,TMA & $FF
	ld l,(hl)
timer_cycles_reset_factor_smc = $+1
	ld h,0
	sub h
	mlt hl
	add a,h
	ld h,a
	add hl,hl
	ld (timer_counter),hl
	add hl,de
	ret nc
	ex de,hl
	or a
	sbc hl,de
	ex de,hl
	ret

serial_counter_checker:
	ld hl,(serial_counter)
	ld a,h
	or l
	jr z,serial_expired_handler
	add hl,de
	ret nc
	ex de,hl
	or a
	sbc hl,de
	ex de,hl
	ret
	
serial_expired_handler:
	ld hl,SC
	res 7,(hl)
	dec hl
	ld (hl),h
	ld l,IF & $FF
	set 3,(hl)
	call disabled_counter_checker
disabled_counter_checker:
	ret
	
decode_mem:
	 ld a,(memroutine_next)
	 sub ixl
	 ld a,(memroutine_next+1)
	 sbc a,ixh
	 jr nc,_
	 ld a,(ix)
	pop ix
	pop ix
	lea ix,ix-2
	ld (ix),a
	ex af,af'
	push af
_
	 push hl
	  push de
	   call.il decode_mem_helper
	   ld (ix+1),de
	   ld (ix),$CD
	  pop de
	 pop hl
	pop af
	jp (ix)
	
decode_jump:
	ex af,af'
	exx
	push.l hl
	pop hl
	push bc
	 inc hl
	 inc hl
	 ld c,(hl)
	 inc hl
	 ld ix,(hl)
	 push hl
	  inc hl
	  inc hl
	  ld de,(hl)
	  di
	  jp.lil decode_jump_helper
decode_jump_return:
	 pop hl
	 ld (hl),ix
	 dec hl
	 dec hl
	 dec hl
	 dec hl
	 ld (hl),a
	 dec hl
	 ld (hl),$33
	 dec hl
	 ld (hl),$ED	;LEA IY,IY+offset
decode_jump_waitloop_return:
	pop bc
	push hl
	pop.l hl
	exx
	ex af,af'
	ret
	
decode_call:
	ex af,af'
	ex (sp),hl
	push bc
	 push de
	  inc hl
	  push hl
	   inc hl
	   inc hl
	   ld de,(hl)
	   dec de
	   di
	   call.il decode_call_helper
	  pop hl
	  dec hl
	  ld (hl),a
	  dec hl
	  dec hl
	  ld (hl),ix
	  dec hl
	  ld (hl),b
	 pop de
	pop bc
	ex (sp),hl
	ex af,af'
	ret
	
decode_call_cond:
	ex af,af'
	ex (sp),hl
	push bc
	 push de
	  push hl
	   inc hl
	   inc hl
	   ld de,(hl)
	   dec de
	   di
	   call.il decode_call_helper
	  pop hl
	  dec hl
	  ld (hl),a
	  dec hl
	  dec hl
	  ld (hl),ix
	  dec hl
	  dec hl
	  ; If a CALL opcode was returned instead of RST, this is a banked call
	  bit 1,b
	  jr nz,_
	  ; Modify the conditional entry point to use the banked call
	  ld de,(hl)
	  dec de
	  dec de
	  ld (hl),de
_
	  dec hl
	  ld (hl),$CD
	 pop de
	pop bc
	ex (sp),hl
	ex af,af'
	ret
	
do_rst:
	pop ix
	exx
	djnz _
	ld b,CALL_STACK_DEPTH
	ld.lil sp,myADLstack
	ld sp,myz80stack-2	
_
	pea ix+4
	ex af,af'
	ld de,(ix+2)
	di
	jp.lil do_rst_helper
	
do_rst_finish:
	ld ix,(ix)
	push ix
	call do_push_and_return
	ld ix,call_stack_ret
	ex (sp),ix
	add a,iyl
	jr c,++_
_
	ld iyl,a
	ex af,af'
	ei
	jp (ix)
_
	inc iyh
	jr nz,--_
	exx
	push de
	 exx
	 ex (sp),hl
	 push de
	  push bc
	   ex de,hl
	   dec de
	   ld c,iyl
	   ld iyl,a
	   sub c
	   sub 4
	   ld c,a
	   push ix
	    jp.lil schedule_rst_event_helper
	
do_banked_call_cond:
	pop ix
	pea ix+2
	ld ix,(ix)
	jp (ix)
	
	jr nz,do_banked_call_cond
do_call_nz:
	jr z,skip_cond_call
	jp r_call
	
	jr z,do_banked_call_cond
do_call_z:
	jr nz,skip_cond_call
	jp r_call
	
	jr nc,do_banked_call_cond
do_call_nc:
	jr c,skip_cond_call
	jp r_call
	
	jr c,do_banked_call_cond
do_call_c:
	jp c,r_call
skip_cond_call:
	pop ix
	lea ix,ix+7
	ex af,af'
	ld a,(ix-3)
	dec a
	add a,iyl
	ld iyl,a
	jr c,++_
_
	ex af,af'
	jp (ix)
_
	inc iyh
	jr nz,--_
	push hl
	 push de
	  push bc
	   ld a,(ix-3)
	   sub 4
	   ld c,a
	   ld de,(ix-2)
	   push ix
	    di
	    jp.lil schedule_event_helper
	
wait_for_interrupt_stub:
	ei
	halt
	ret.l
	
flush_handler:
	exx
flush_address = $+1
	ld de,0
	di
	jp.lil flush_normal
	
flush_mem_handler:
	exx
	pop bc
	di
	jp.lil flush_mem
	
coherency_handler:
	pop ix
	push hl
	 push de
	  push bc
	   pea ix+RAM_PREFIX_SIZE-3
	    ld ix,(ix)
	    di
	    jp.lil check_coherency_helper

coherency_return:
	   pop ix
	  pop bc
	 pop de
	pop hl
	jp (ix)
	   
do_swap:
	inc a
	jr nz,do_swap_generic
	ex af,af'
	rrca
	rrca
	rrca
	rrca
	or a
	ret
do_swap_generic:
	inc a
	jr z,do_swap_hl
	add a,$7E	;LD A,r
	ld (_),a
	add a,a
	add a,a
	add a,a
	sub $79		;LD r,A
	ld (++_),a
	ex af,af'
	push af
_
	 ld a,b
	 rrca
	 rrca
	 rrca
	 rrca
	 or a
_
	 ld b,a
	pop ix
	ld a,ixh
	ret
do_swap_hl:
	ex af,af'
	push af
	 call mem_read_any_before_write
	 rrca
	 rrca
	 rrca
	 rrca
	 or a
	 call mem_write_any_after_read
	pop ix
	ld a,ixh
	ret
	
do_bits:
	sub $30
	sub 8
	jr c,do_swap
	add a,$38-1	;Use L instead of (HL)
	cp $C0
	jp pe,do_bits_readonly
	ld (do_bits_smc),a
	call mem_read_any_before_write
	; Use L because we have to affect flags, bleh
	push hl
	 ld l,a
	 ex af,af'
	 ld h,a
do_bits_smc = $+1
	 rlc l
	 ld a,l
	 ex (sp),hl
	 call mem_write_any_after_read
	pop ix
	ld a,ixh
	ret
do_bits_readonly:
	ld (do_bits_readonly_smc),a
	call mem_read_any
	; Use L because we have to affect flags, bleh
	push hl
	 ld l,a
	 ex af,af'
do_bits_readonly_smc = $+1
	 bit 0,l
	pop hl
	ret
	
ophandler08:
	push af
	 push de
	  exx
	  push hl
	   exx
	   ex (sp),hl
	   ld de,(sp_base_address)
	   or a
	   sbc hl,de
	   ex de,hl
	   lea hl,ix
	   ld a,e
	   dec iy
	   call mem_write_any
	   inc hl
	   ld a,d
	   call mem_write_any_after_read
	  pop hl
	 pop de
	pop af
	ret
	
ophandler27:
	push af
	 ex (sp),hl
	 daa
	 bit 1,l
	 jr nz,_
	 ; If N was 0, behavior is same as Game Boy
	pop hl
	; Reset H and N flags, preserve C flag, set Z flag properly
	rla
	rr a
	ret
	
	; Emulate N=1 case manually
_
	 ld a,h
	 bit 4,l
	 jr z,_
	 sub $06
_
	 srl l
	 jr c,++_
	 sub $00
_
	pop hl
	ret
_
	 sub $60
	 jr c,--_
	 ; Set C flag and don't touch other flags
	 push af
	 pop hl
	 inc l
	 ex (sp),hl
	pop af
	ret
	
ophandler31:
	pop ix
	exx
	ld hl,(ix)
	lea ix,ix+2
	di
	jp.lil set_gb_stack
	
ophandler34:
	ex af,af'
	call mem_read_any_before_write
	ld ixl,a
	ex af,af'
	inc ixl
	jr _
	
ophandler35:
	ex af,af'
	call mem_read_any_before_write
	ld ixl,a
	ex af,af'
	dec ixl
_
	push af
	 call mem_write_any_after_read_ixl
	pop af
	ret
	
ophandler36:
	push af
	 ld a,ixl
	 call mem_write_any
	pop af
	ret
	
ophandler39:
	ex af,af'
	push de
	 exx
	 push hl
	  exx
	  ex (sp),hl
	  ld de,(sp_base_address)
	  or a
	  sbc hl,de
	  ex de,hl
	 pop hl
	 ex af,af'
	 add hl,de
	pop de
	ret
	
handle_waitloop_stat:
	jr handle_waitloop_stat
	
handle_waitloop_variable:
	ex af,af'
	push hl
handle_waitloop_main:
	 ; Skip straight to the counter expiration
	 xor a
	 ld iyh,a
	 sub (ix+2)
	 ld iyl,a
handle_waitloop_noskip:
	 ; Run an event using our precomputed lookup
	 ld hl,(ix+4)
	 ld (event_gb_address),hl
	 ld a,(ix+2)
	 ld (event_cycle_count),a
	 ld ix,(ix)
	 jp do_event_pushed
	
handle_waitloop_ly:
	ex af,af'
	push hl
	 push de
	  ; Get the (negative) number of cycles until the next event
	  ld a,(ix+2)
	  call get_cycle_offset
	  push de
	   ; Get the (negative) number of cycles until the next scanline
	   call get_scanline_from_cycle_offset
	   ld d,a
	   ld a,e
	   cp 153
	   ld a,d
	   jr nz,_
	   sub 1
	   jr c,++_
	   sub CYCLES_PER_SCANLINE - 1
_
	   sub CYCLES_PER_SCANLINE
_
	  pop de
	  ; Choose the smaller absolute value
	  inc d
	  jr nz,_
	  cp e
	  jr nc,_
	  ld a,e
_
	  ld e,a
	  ; Step by a multiple of the loop length
	  ld d,(ix+3)
	  ; Always advance at least one iteration
	  add a,d
	  jr c,++_
	  ; Advance as many iterations as possible without exceeding the cycle count
_
	  add a,d
	  jr nc,-_
	  sub d
_
	  sub e
	 pop de
	 ; Add in the cycles and check for overflow
	 add a,iyl
	 ld iyl,a
	 jr c,_
	 dec iyh
_
	 inc iyh
	 jr z,_
	 ld ix,(ix)
	pop hl
	ex af,af'
	jp (ix)
_
	 ; If the count has already expired, do an event immediately
	 add a,(ix+2)
	 jr c,handle_waitloop_noskip

	 ; Schedule an event using our precomputed lookup
	 push de
	  push bc
	   ld de,(ix+4)
	   ld a,(ix+2)
	   ld ix,(ix)
	   push ix
	    di
	    jp.lil schedule_event_helper
	
ophandlerEI:
	ex af,af'
	ld a,$A6 ;AND (HL)
	ld (intstate_smc),a
	pop ix
	push hl
	 ld a,(ix)
	 ld (_+2),a
_
	 lea iy,iy+0
	 neg
	 inc a
	 ld (event_cycle_count),a
	 ld hl,(ix+1)
	 ld (event_gb_address),hl
	 lea ix,ix+3
	 jp do_event_pushed_no_reset
	
ophandler76:
	ex af,af'
	pop ix
	push hl
	 ld hl,IF
	 ld a,(hl)
	 ld l,h
	 and (hl)
	 ld hl,(ix+1)
	 jr z,haltspin
	 ld a,(ix)
	 ld (_+2),a
_
	 lea iy,iy+0
	 neg	; A is non-zero, so this sets carry
	 inc a
	 lea ix,ix+3
	 inc hl
	 jr haltdone
haltspin:
	 dec hl
	 lea ix,ix-3
	 ld iy,0
haltdone:
	 ld (event_cycle_count),a
	 ld (event_gb_address),hl
	 sbc a,a
	 inc a
	 ld (cpu_halted),a
	 jp do_event_pushed_no_reset
	
	
trigger_event_fast_forward:
	scf
trigger_event:
	push hl
trigger_event_pushed:
	 push de
	  push bc
	   push af
event_address = $+1
	    ld hl,0
	    ld a,(event_value)
	    ld (hl),a
	   
	    ; Get the cycle offset, GB address, and JIT address after the current opcode
	    exx
	    ld a,b
	    exx
	    ld b,a
	    call get_mem_cycle_offset
	
	    ld (event_gb_address),hl
	    lea hl,ix
	    ld (event_address),hl
	    ld (event_cycle_count),a
	    ld c,a
	    ld a,(hl)
	    ld (event_value),a
	    ld (hl),RST_EVENT
	   pop af
	   jr c,event_fast_forward
	   ; If the end of this instruction is already past the target, don't rewind
	   ld a,d
	   or a
	   jr z,trigger_event_already_triggered
	   ld hl,(serial_counter)
	   add hl,de
	   ld (serial_counter),hl
	   ld hl,(timer_counter)
	   add hl,de
	   ld (timer_counter),hl
	   ld hl,(stat_counter)
	   add hl,de
	   ld (stat_counter),hl
	   ld hl,(lyc_counter)
	   add hl,de
	   ld (lyc_counter),hl
	   ld hl,(div_counter)
	   add hl,de
	   ld (div_counter),hl
	   ld hl,(vblank_counter)
	   add hl,de
	   ld (vblank_counter),hl
event_fast_forward:
	   xor a
	   ld iyh,a
	   sub c
	   ld iyl,a
trigger_event_already_triggered:
	  pop bc
	 pop de
	pop hl
	ex af,af'
	ret
	
ophandlerE2:
	ld ixh,$FF
	ld ixl,c
	jp mem_write_ports_always
	
ophandlerE8:
	exx
	ld c,a
	pop ix
	ld a,(ix)
	inc ix
	ld de,(sp_base_address)
	or a
	sbc hl,de
	ld e,a
	rla
	sbc a,a
	ld d,a
	ld a,l
	add hl,de
	add a,e
	call z,reset_z_flag_only
	ld a,c
	di
	jp.lil set_gb_stack
	
ophandlerE9:
	ex af,af'
	push hl
	 push de
	  push bc
	   ex de,hl
	   di
	   call.il lookup_code_cached
	   ei
	   scf
	   adc a,iyl
	   jr c,++_
_
	   ld iyl,a
	  pop bc
	 pop de
	pop hl
	ex af,af'
	jp (ix)
_
	   inc iyh
	   jr nz,--_
	   ld c,iyl
	   ld iyl,a
	   sbc a,c
	   ld c,a
	   inc de
	   dec de
	   push ix
	    di
	    jp.lil schedule_event_helper
	
ophandlerF1:
	exx
	ld.l e,(hl)
	inc.l hl
	ld d,flags_lut >> 8
	res 3,e
	ld a,(de)
	ld e,a
	ld.l d,(hl)
	inc.l hl
	push de
	pop af
	exx
	ret
	
ophandlerF2:
	ld ixh,$FF
	ld ixl,c
	ex af,af'
	call mem_read_ports_always
	ld a,ixl
	ret
	
ophandlerF3:
	ex af,af'
	ld a,$AF ;XOR A
	ld (intstate_smc),a
	ex af,af'
	ret
	
ophandlerF5:
	exx
	ld c,a
	dec.l hl
do_push_smc_5 = $+1
	ld.l (hl),a
	push af
	pop de
	ld d,flags_lut >> 8
	set 3,e
	ld a,(de)
	dec.l hl
do_push_smc_6 = $+1
	ld.l (hl),a
	ld a,c
	exx
	ret
	
ophandlerF8:
	ld ixl,a
	pop hl
	ld a,(hl)
	inc hl
	push hl
	exx
	push hl
	 exx
	pop hl
	push de
	 ld de,(sp_base_address)
	 or a
	 sbc hl,de
	 ld e,a
	 rla
	 sbc a,a
	 ld d,a
	 ld a,l
	 add hl,de
	 add a,e
	 call z,reset_z_flag_only
	pop de
	ld a,ixl
	ret
	
reset_z_flag_only:
	push af
	dec sp
	pop af
	res 6,a
	push af
	inc sp
	pop af
	ret
	
ophandlerF9:
	pop ix
	push hl
	 exx
	pop hl
	di
	jp.lil set_gb_stack
	
ophandlerRETI:
	ex af,af'
	ld a,$A6 ;AND (HL)
	ld (intstate_smc),a
	exx
	push bc
	 di
	 call.il pop_and_lookup_code_cached
	 ei
	pop bc
	; Count cycles before attempting to trigger an interrupt
	add a,4
	ld (_+2),a
_
	lea iy,iy+0
	cpl
	add a,5
	ld (event_cycle_count),a
	ld (event_gb_address),de
	exx
	push hl
	 jp do_event_pushed_no_reset
	
ophandlerRET:
	di
	dec sp
	dec sp
	ex af,af'
	exx
	push bc
	 call.il pop_and_lookup_code_cached
	 ei
	pop bc
	add a,4
	jp dispatch_cycles_for_ret
	
write_vram_handler:
	pop ix
	pea ix+2
	ld ix,(ix)
	jp mem_write_vram_always
	
write_cart_handler:
	pop ix
	pea ix+2
	ld ix,(ix)
	jp mem_write_cart_always
	
write_cram_bank_handler:
	pop ix
	pea ix+2
	exx
	ld de,(ix)
	ld.lil ix,(cram_bank_base)
	ex af,af'
write_cram_bank_handler_smc_1 = $+2
	add.l ix,de
	ex af,af'
write_cram_bank_handler_smc_2 = $+3
	ld.l (ix),a
	exx
	ret
	
read_rom_bank_handler:
	pop ix
	pea ix+2
	exx
	ld de,(ix)
	ld.lil ix,(rom_bank_base)
	ex af,af'
	add.l ix,de
	ex af,af'
	ld.l a,(ix)
	exx
	ret
	
read_cram_bank_handler:
	pop ix
	pea ix+2
	exx
	ld de,(ix)
	ld.lil ix,(cram_bank_base)
	ex af,af'
read_cram_bank_handler_smc = $+2
	add.l ix,de
	ex af,af'
	ld.l a,(ix)
	exx
	ret
	
readP1handler:
	ex af,af'
	call readP1
	ld a,ixl
	ret
	
readDIVhandler:
	ex af,af'
	call readDIV
	ld a,ixl
	ret
	
readTIMAhandler:
	ex af,af'
	call readTIMA
	ld a,ixl
	ret
	
readLYhandler:
	ex af,af'
	call readLY
	ld a,ixl
	ret
	
readSTAThandler:
	ex af,af'
	call readSTAT
	ld a,ixl
	ret
	
readNR52handler:
	ex af,af'
readNR52:
	ld a,(NR52)
	add a,a
	ld a,$70
	jr nc,readNR52_finish
	ld ix,audio_port_value_base
	push hl
	 sbc hl,hl
	 ld l,(ix+NR44-ioregs)
	 add hl,hl
	 ld l,(ix+NR34-ioregs)
	 add hl,hl
	 ld l,(ix+NR24-ioregs)
	 add hl,hl
	 ld l,(ix+NR14-ioregs)
	 add hl,hl
	 ld a,h
	pop hl
	jr readNR52_finish
	
readP1:
	ld a,(P1)
	or $CF
	ld ix,(keys)
	bit 4,a
	jr nz,_
	and ixl 
_
	bit 5,a
	jr nz,_
	and ixh
_
readNR52_finish:
	ld ixl,a
	ex af,af'
	ret
	
readSTAT:
	exx
	push.l hl
	 call get_mem_cycle_offset
	 call get_scanline_from_cycle_offset
	 ld d,a
	pop.l hl
	ld a,(STAT)
	or $87
	ld c,a
	ld a,(LCDC)
	add a,a
	jr nc,readSTAT_mode0
	ld a,(LYC)
	cp e
	jr z,_
	res 2,c
_
	ld a,e
	cp 144
	jr nc,readSTAT_mode1
	ld a,d
	sub MODE_2_CYCLES
	jr c,readSTAT_mode2
	sub MODE_3_CYCLES
	jr c,readSTAT_mode3
readSTAT_mode0:
	dec c
readSTAT_mode1:
	dec c
readSTAT_mode2:
	dec c
readSTAT_mode3:
	ld ixl,c
	exx
	ex af,af'
	ret
	
readLY:
	ld a,(LCDC)
	add a,a
	jr nc,readLY_force0
	exx
	push.l hl
	 call get_mem_cycle_offset
	 call get_scanline_from_cycle_offset
	pop.l hl
	or a
	ld a,e
	exx
	jr z,_
	cp 153
	jr z,readLY_force0
_
	ld ixl,a
	ex af,af'
	ret
	
readLY_force0:
	xor a
	jr -_
	
	;IX=GB address, reads into IXL
mem_read_ports:
	ex af,af'
	ld a,ixh
	cp $FE
	jr c,mem_read_bail
	jr z,mem_read_oam
	;IX=GB address, reads into IXL, AF'=GB AF
mem_read_ports_always:
	ld a,ixl
	add a,a
	jr c,mem_read_oam
	jr z,readP1
	cp TIMA*2 & $FF
	jr z,readTIMA
	cp LY*2 & $FF
	jr z,readLY
	cp DIV*2 & $FF
	jr z,readDIV
	cp STAT*2 & $FF
	jr z,readSTAT
	cp NR52*2 & $FF
	jp z,readNR52
mem_read_oam:
	ld ix,(ix)
	ex af,af'
	ret
	
readTIMA:
	call updateTIMA
	 ei
	 ld ixl,a
	pop.l hl
	exx
	ex af,af'
	ret
	
mem_read_any_before_write:
	dec iy
	;HL=GB address, reads into A, AF'=GB AF
mem_read_any:
	ld a,h
	cp $FE
	jr nc,mem_read_any_ports
	ex de,hl
	add a,a
	jr c,++_
	add a,a
	jr c,_
	ld.lil ix,(rom_start)
	add.l ix,de
	ld.l a,(ix)
	ex de,hl
	ret
_
	ld.lil ix,(rom_bank_base)
	add.l ix,de
	ld.l a,(ix)
	ex de,hl
	ret
_
	add a,a
	jr nc,_
	ld.lil ix,wram_base
	add.l ix,de
	ld.l a,(ix)
	ex de,hl
	ret
_
	add a,a
	jr c,_
	ld.lil ix,vram_base
	add.l ix,de
	ld.l a,(ix)
	ex de,hl
	ret
	
mem_read_bail:
	pop ix
mem_write_bail_a:
	lea ix,ix-8
	jp (ix)
	
_
	ld.lil ix,(cram_bank_base)
mem_read_any_rtc_smc = $+2
	add.l ix,de
	ld.l a,(ix)
	ex de,hl
	ret
	
readDIV:
	exx
	push.l hl
	 call get_mem_cycle_offset
	 ld hl,(div_counter)
	 add hl,de
	 add hl,hl
	 add hl,hl
	 ex de,hl
	 ld ixl,d
	pop.l hl
	exx
	ex af,af'
	ret
	
mem_read_any_ports:
	jr z,_
	ld a,l
	add a,a
	jr c,_
	push hl
	pop ix
	call mem_read_ports_always
	ex af,af'
	ld a,ixl
	ret
_
	ld a,(hl)
	ret
	
mem_write_any_cart:
	push hl
	pop ix
	jp mem_write_cart_swap
	
	;HL=GB address, IXL=data, destroys A,AF'
mem_write_any_after_read_ixl:
	ld a,ixl
mem_write_any_after_read:
	inc iy
	;HL=GB address, A=data, preserves AF, destroys AF'
mem_write_any:
	ex af,af'
	ld a,h
	cp $FE
	jr nc,mem_write_any_ports
	add a,a
	jr nc,mem_write_any_cart
	sub $40
	jr c,mem_write_any_vram
	ex de,hl
	sub $40
	jr c,mem_write_any_cram
	ld.lil ix,wram_base
	add.l ix,de
	ex de,hl
	ex af,af'
	ld.l (ix),a
	ret
mem_write_any_cram:
	ld.lil ix,(cram_bank_base)
mem_write_any_cram_smc_1 = $+2
	add.l ix,de
	ex de,hl
	ex af,af'
mem_write_any_cram_smc_2 = $+3
	ld.l (ix),a
	ret
	
mem_write_bail:
	pop ix
	ld a,(ix-8)
	cp RST_MEM
	jr z,mem_write_bail_a
	lea ix,ix-10
	pop af
	ex af,af'
	jp (ix)
	
	;IX=GB address, A=data, preserves AF, destroys AF'
mem_write_vram:
	ex af,af'
	ld a,ixh
	sub $20
	jp po,mem_write_bail
mem_write_vram_swap:
	ex af,af'
	;IX=GB address, A=data
mem_write_vram_always:
	di
	jp.lil write_vram_and_expand
	
mem_write_any_ports:
	push hl
	pop ix
	jr nz,mem_write_ports_swap
	jr mem_write_oam_swap
mem_write_any_vram:
	push hl
	pop ix
	jr mem_write_vram_swap
	
	;IX=GB address, A=data, preserves AF, destroys AF'
mem_write_ports:
	ex af,af'
	ld a,ixh
	inc a
	jr z,mem_write_ports_swap
	inc a
	jr nz,mem_write_bail
mem_write_oam_swap:
	ex af,af'
	ld (ix),a
	ret
	;IX=GB address, A=data, preserves AF, destroys AF'
mem_write_ports_always:
	ex af,af'
mem_write_ports_swap:
	ld a,ixl
	cp $7F
	jp pe,mem_write_oam_swap
	push hl
	 sub WX+1-ioregs
	 ld l,a
	 ld h,mem_write_port_routines >> 8
	 ld l,(hl)
	 ex (sp),hl
	 ret m
	pop af
	ex af,af'
	ret
	
	;IX=GB address, A=data, preserves AF, destroys AF'
mem_write_cart:
	ex af,af'
	ld a,ixh
	rla
	jp c,mem_write_bail
mem_write_cart_swap:
	ex af,af'
	;IX=GB address, A=data, preserves AF, destroys AF'
mem_write_cart_always:
	ex af,af'
	ld a,ixh
	sub $20
	jr c,mbc_0000
	sub $20
	jr c,mbc_2000
	sub $20
	jr c,mbc_4000
	
mbc_6000:
	ld a,(mbc_z80)
	cp 4 ;MBC3+RTC
	jr z,++_
	dec a
	jr nz,mbc_6000_denied
	ex af,af'
	push af
	 ex af,af'
	pop af
	rra
	ld a,$28
	jr nc,_
	ld a,$20
_
	ld (mbc1_ram_smc),a
mbc_6000_denied:
mbc_0000:
	ex af,af'
	ret
	
_
	di
	jp.lil mbc_rtc_latch_helper
	
mbc_4000:
	push bc
	 ld b,$60
	 ex af,af'
	 ld c,a
	 ex af,af'
	 ld a,(mbc_z80)
	 dec a
	 jr nz,_
mbc1_ram_smc:
	 jr z,mbc_ram
	 ld a,c
	 rrca
	 rrca
	 rrca
	 ld c,a
	 jr mbc_2000_finish
_
	 dec a
	 dec a
	 jr z,mbc_ram
	 dec a
	 jr nz,mbc_4000_denied
	 di
	 jp.lil mbc_rtc_helper
mbc_ram:
cram_size_smc = $
	 or a
	 sbc a,a
	 and c
	 rrca
	 rrca
	 rrca
	 and b
	 ld b,a
	 ld c,0
cram_base_0 = $+3
	 ld.lil ix,0
mbc_ram_any:
	 add.l ix,bc
	 ld.lil (cram_bank_base),ix
	 ; See if SP is pointing into the swapped bank
	 exx
	 ld de,(sp_base_address)
	 ld a,l
	 sub e
	 ld e,a
	 ld a,h
	 sbc a,d
	 ld d,a
	 sub $A0
	 cp $20
	 jr c,mbc_fix_sp
	 exx
mbc_4000_denied:
	pop bc
	ex af,af'
	ret
	
mbc_2000:
	push bc
	 ex af,af'
	 ld c,a
	 ex af,af'
mbc_z80 = $+1
	 ld b,1
	 djnz _
	 ld b,$1F
	 jr mbc_2000_finish
_
	 djnz _
	 ld b,$0F
	 jr mbc_2000_finish
_
	 ld b,$FF
mbc_2000_finish:
	 ld a,c
curr_rom_bank = $+1
	 ld c,1
	 xor c
	 and b
	 xor c
	 ld c,a
	 ld (curr_rom_bank),a
	 ld (rom_bank_check_smc_1),a
	 ld (rom_bank_check_smc_2),a
	 ld (rom_bank_check_smc_3),a
	 ld b,3
	 mlt bc
	 ld.lil ix,rombankLUT
	 add.l ix,bc
	 ld.l ix,(ix)
	 ld.lil (rom_bank_base),ix
	 ; See if SP is pointing into the swapped bank
	 exx
	 ld de,(sp_base_address)
	 ld a,l
	 sub e
	 ld e,a
	 ld a,h
	 sbc a,d
	 cp $C0
	 jp po,mbc_no_fix_sp
	 ; If so, update it
	 ld d,a
mbc_fix_sp:
	 lea.l hl,ix
	 ld.lil (z80codebase+sp_base_address),hl
	 add.l hl,de
mbc_no_fix_sp:
	 exx
mbc_2000_denied:
	pop bc
	ex af,af'
	ret
	

; Inputs: IY = current block cycle base
;         B = number of empty call stack entries
;         (bottom of stack) = JIT return address
;         AFBCDEHL' have been swapped
; Outputs: DE = (negative) cycle offset
;          HL = Game Boy address
;          IX = current JIT address
; Destroys HL,IX
get_mem_cycle_offset:
	; Get the address of the recompiled code: the bottom stack entry
	ld hl,myz80stack - 2 - ((CALL_STACK_DEPTH + 1) * CALL_STACK_ENTRY_SIZE) - 2
	ld e,CALL_STACK_ENTRY_SIZE
	ld d,b
	mlt de
	add hl,de
	ld ix,(hl)
	ld hl,(ix-2)
	ld a,(ix-3)
	or a
	jr z,resolve_mem_cycle_offset_prefix
	ld a,(hl)
	xor $C3
	and $FB
	jr nz,resolve_get_mem_cycle_offset_call
	dec hl
	ld a,(hl)
	dec hl
	dec hl
	ld hl,(hl)

; Inputs: IY = (negative) cycles until target
;         A = (negative) number of cycles to subtract
; Outputs: DE = (negative) cycle offset
;          May be positive if target lies within an instruction
get_cycle_offset:
	ld (get_cycle_offset_smc),a
get_last_cycle_offset:
get_cycle_offset_smc = $+2
	lea de,iy+0
	ret
	
	
resolve_mem_cycle_offset_prefix:
	ld c,$C9
	jr _
	 
resolve_get_mem_cycle_offset_call:
	ld c,h
	ld h,l
	ld l,$C3
_
	di
	jp.lil resolve_mem_cycle_offset_helper

	
get_mem_scanline_offset:
	exx
	push.l hl
	call get_mem_cycle_offset
	di
	
; Inputs: DE = (negative) cycles until target
;         May be non-negative if target falls within an instruction
; Outputs: A = cycle count within scanline
;          E = scanline index (0-153)
; Destroys: D, HL
get_scanline_from_cycle_offset:
	ld hl,(vblank_counter)
	add hl,de
	dec h
	ld de,(CYCLES_PER_SCANLINE * 144) + 256
	add hl,de
	jr c,get_scanline_from_cycle_count
	ld de,CYCLES_PER_FRAME
	add hl,de
	
; Inputs: HL = cycle count within frame
; Outputs: A = cycle count within scanline
;          E = scanline index (0-153)
; Destroys: D, HL
get_scanline_from_cycle_count:
scanline_cycle_count_cache = $+1
	ld de,0
	xor a
	sbc hl,de
	cp h
	jr nz,++_
	ld a,l
scanline_index_cache = $+1
	ld de,CYCLES_PER_SCANLINE * 256 + 0
	cp d
	ret c
	sub d
	cp d
	jr nc,_
	inc e
	ex de,hl
get_scanline_from_cycle_count_finish:
	ld e,l
	ld (scanline_index_cache),hl
	mlt hl
	ld (scanline_cycle_count_cache),hl
	ret
_
	mlt de
_
	add hl,de
	ld de,-(CYCLES_PER_SCANLINE * 128)
	add hl,de \ jr c,$+4 \ sbc hl,de \ adc hl,hl
	add hl,de \ jr c,$+4 \ sbc hl,de \ adc hl,hl
	add hl,de \ jr c,$+4 \ sbc hl,de \ adc hl,hl
	add hl,de \ jr c,$+4 \ sbc hl,de \ adc hl,hl
	add hl,de \ jr c,$+4 \ sbc hl,de \ adc hl,hl
	add hl,de \ jr c,$+4 \ sbc hl,de \ adc hl,hl
	add hl,de \ jr c,$+4 \ sbc hl,de \ adc hl,hl
	add hl,de \ jr c,$+4 \ sbc hl,de \ adc hl,hl
	ld a,h
	ld h,CYCLES_PER_SCANLINE
	jr get_scanline_from_cycle_count_finish
	
; Output: BCDEHL' are swapped
;         (SPL) = saved HL'
;         DE = current cycle offset
;         A = current TIMA value
;         (TIMA) updated to current value
;         Interrupts are disabled
updateTIMA:
	exx
	push.l hl
	 call get_mem_cycle_offset
	 ld a,(TAC)
	 and 4
	 ld a,(TIMA)
	 di
	 ret z
	 ld hl,(timer_counter)
	 add hl,de
	 ; Handle special case if cycle offset is non-negative
	 xor a
	 cp d
	 jr z,updateTIMAoverflow
updateTIMAcontinue:
updateTIMA_smc = $+1
	 jr $+8
	 add hl,hl
	 add hl,hl
	 add hl,hl
	 add hl,hl
	 add hl,hl
	 add hl,hl
	 add a,h
	 ld (TIMA),a
	 ret
	
updateTIMAoverflow:
	 ; Check if adding the cycle offset created a non-negative result
	 sbc hl,de
	 add hl,de
	 jr c,_
	 jr nz,updateTIMAcontinue
_
	 ; If so, offset the TIMA value by TMA
	 ld a,(TMA)
	 jr updateTIMAcontinue
	
	.block (-$-158)&$FF
	
_writeSC:
	ex af,af'
_writeSChandler:
	push af
	 or $7E
	 ld (SC),a
	 inc a
	 ld ix,disabled_counter_checker
	 jr nz,_
	 push hl
	  call trigger_event
	  ; Set this cycle count after setting up the trigger
	  ld hl,-1024
	  ld (serial_counter),hl
	 pop hl
	 ld ix,serial_counter_checker
_
	 ld (event_counter_checkers + 6),ix
	pop af
	ret
	
mem_write_port_handler_base = $-2
writeSChandler:
	jr _writeSChandler
writeNR10handler:
	call write_audio_handler
	.db NR10 - ioregs
writeNR11handler:
	call write_audio_handler
	.db NR11 - ioregs
writeNR12handler:
	call write_audio_handler
	.db NR12 - ioregs
writeNR13handler:
	call write_audio_handler
	.db NR13 - ioregs
writeNR14handler:
	call write_audio_handler
	.db NR14 - ioregs
writeNR21handler:
	call write_audio_handler
	.db NR21 - ioregs
writeNR22handler:
	call write_audio_handler
	.db NR22 - ioregs
writeNR23handler:
	call write_audio_handler
	.db NR23 - ioregs
writeNR24handler:
	call write_audio_handler
	.db NR24 - ioregs
writeNR30handler:
	call write_audio_handler
	.db NR30 - ioregs
writeNR31handler:
	call write_audio_handler
	.db NR31 - ioregs
writeNR32handler:
	call write_audio_handler
	.db NR32 - ioregs
writeNR33handler:
	call write_audio_handler
	.db NR33 - ioregs
writeNR34handler:
	call write_audio_handler
	.db NR34 - ioregs
writeNR41handler:
	call write_audio_handler
	.db NR41 - ioregs
writeNR42handler:
	call write_audio_handler
	.db NR42 - ioregs
writeNR43handler:
	call write_audio_handler
	.db NR43 - ioregs
writeNR44handler:
	call write_audio_handler
	.db NR44 - ioregs
writeNR50handler:
	call write_audio_handler
	.db NR50 - ioregs
writeNR51handler:
	call write_audio_handler
	.db NR51 - ioregs
	
writeSCYhandler:
	ld ix,SCY
	jr write_scroll_swap
	
writeSCXhandler:
	ld ix,SCX
	jr write_scroll_swap
	
writeWYhandler:
	ld ix,WY
	jr write_scroll_swap
	
writeWXhandler:
	ld ix,WX
	jr write_scroll_swap
	
writeDMAhandler:
	ld ix,DMA
	jr write_scroll_swap
	
writeBGPhandler:
	ld ix,BGP
	jr write_scroll_swap

write_audio_handler:
	ex af,af'
	ex (sp),hl
	ld ix,(hl)
	pop hl
	
#if $ & 255
	.error "mem_write_port_routines must be aligned: ", $ & 255
#endif
	
mem_write_port_routines:
write_audio:
	ld ixh,audio_port_value_base >> 8
	ld a,(ix + audio_port_masks - audio_port_values)
	cp $BF
	jr z,write_audio_enable
	ex af,af'
	push af
write_audio_enable_continue:
	 ld (ix),a
	 or (ix + audio_port_masks - audio_port_values)
	 ld ixh,ioregs >> 8
	 ld (ix),a
	pop af
	ret
	
write_audio_enable:
	ex af,af'
	push af
	 bit 7,(ix)
	 jr z,write_audio_enable_continue
	 or $80
	 jr write_audio_enable_continue
	
write_scroll_swap:
	ex af,af'
write_scroll:
	push ix
	 call get_mem_scanline_offset
	pop hl
	jp.lil scroll_write_helper
	
writeLCDChandler:
	ex af,af'
writeLCDC:
	call get_mem_scanline_offset
	ex de,hl
	call get_last_cycle_offset
	jp.lil lcdc_write_helper
	
writeTAChandler:
	ex af,af'
writeTAC:
	call updateTIMA
	jp.lil tac_write_helper
	
writeTIMAhandler:
	ex af,af'
writeTIMA:
	call updateTIMA
	ex af,af'
	ld (TIMA),a
	ex af,af'
_
	jp.lil tima_write_helper
	
writeDIVhandler:
	ex af,af'
writeDIV:
	call updateTIMA
	or a
	sbc hl,hl
	sbc hl,de
	ld (div_counter),hl
	jr -_
	
writeSTAThandler:
	ex af,af'
writeSTAT:
	call get_mem_scanline_offset
	jp.lil stat_write_helper
	
writeLYChandler:
	ex af,af'
writeLYC:
	call get_mem_scanline_offset
	jp.lil lyc_write_helper
	
writeIE:
	ex af,af'
writeIEhandler:
	push af
	 ex af,af'
	pop af
	and $1F
	ld (IE),a
	jr checkInt
	
writeIF:
	ex af,af'
writeIFhandler:
	push af
	 ex af,af'
	pop af
	or $E0
	ld (IF),a
checkInt:
	ld a,(intstate_smc)
	rra
	jr c,checkIntDisabled
checkIntPostEnable:
	push hl
	 ld hl,IF
	 ld a,(hl)
	 ld l,h
	 and (hl)
	 jp nz,trigger_event_pushed
	pop hl
checkIntDisabled:
write_port_ignore:
	ex af,af'
	ret
	
writeSC:
	jp _writeSC
	
write_port_direct:
	ex af,af'
	ld (ix),a
	ret
	
	.echo (mem_write_port_routines+256-(WX+2-ioregs))-$, " bytes remaining for port writes"
	.block (mem_write_port_routines+256-(WX+2-ioregs))-$

	.db writeIE - mem_write_port_routines
;00
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db writeSC - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db writeDIV - mem_write_port_routines
	.db writeTIMA - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db writeTAC - mem_write_port_routines
;08
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db writeIF - mem_write_port_routines
;10
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
;18
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
;20
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
;28
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
;30
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
;38
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
;40
	.db writeLCDC - mem_write_port_routines
	.db writeSTAT - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db writeLYC - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
;48
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
	
audio_port_value_base:
	.block 1
	
rtc_latched:
	.db 0	;seconds
	.db 0	;minutes
	.db 0	;hours
	.dw 0	;days
rtc_current:
	.db 0	;seconds
	.db 0	;minutes
	.db 0	;hours
	.dw 0	;days
rtc_last:
	.db 0   ;seconds
	.db 0   ;minutes
	.db 0   ;hours
	.dw 0   ;days
	
audio_port_values:
	.block NR52 - NR10
audio_port_masks:
	;NR10 - NR14
	.db $80, $3F, $00, $FF, $BF
	;unused, NR21 - NR24
	.db $FF, $3F, $00, $FF, $BF
	;NR30 - NR34
	.db $7F, $FF, $9F, $FF, $BF
	;unused, NR41 - NR44
	.db $FF, $FF, $00, $00, $BF
	;NR50 - NR51
	.db $00, $00
	
keys:
	.dw $FFFF
	
sp_base_address:
	.dl 0
memroutine_next:
	.dl 0
render_save_sps:
	.dw 0
	
	; One word of stack space for sprite rendering during vblank
	.dw 0
event_counter_checkers:
	.dw disabled_counter_checker	;LYC
	.dw disabled_counter_checker	;STAT
	.dw disabled_counter_checker	;Timer
	.dw disabled_counter_checker	;Serial
	.dw event_counter_checkers_done
	
	.assume adl=1
z80codesize = $-0
	.org z80code+z80codesize
	
	.echo "Z80 mode code size: ", z80codesize
	
jit_start = z80codesize
