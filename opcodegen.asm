; Allocate at 256-byte aligned cursor memory

opgenroutines:
opgenJP:
	call opgen_emitbranch
	inc hl
	ret

opgenJR:
opgen_emitbranch:
	ld a,RST_BRANCH
	ld (de),a
opgen_emitPC:
	inc hl
	ld a,(base_address)
	cpl
	add a,l
	inc de
	ld (de),a
	ld a,(base_address+1)
	cpl
	adc a,h
	inc de
	ld (de),a
	ret

opgenE9:
	ex de,hl
	ld (hl),$C3
	inc hl
	ld (hl),ophandlerE9 & $FF
	inc hl
	ld (hl),ophandlerE9 >> 8
	ex de,hl
	ret
	
opgenE0:
	jp opgenFFwrite
	
opgenEA:
	jp opgenCONSTwrite
	
opgenF0:
	jp opgenFFread
	
opgenFA:
	jp opgenCONSTread
	
opgenJRcond:
	call opgen_emitbranch
	jr opgen_next_skip
	
opgenJPcond:
	call opgen_emitbranch
	inc hl
	jr opgen_next_skip
	
opgenCALLcond:
	ld a,c
	xor $C4 ^ $28
	ld (de),a
	inc de
	ld a,5
	ld (de),a
	inc de
opgenCALL:
	call opgen_emitbranch
	inc hl
	inc hl
_opgenRST:
	call opgen_emitPC
	dec hl
	inc de
	jr opgen_next_fast
	
opgenRST:
	call opgen_emitbranch
	jr _opgenRST
	
opgenMEM:
	ld a,RST_MEM
	ld (de),a
	inc de
	ldi
	inc de
	jr opgen_next_fast
	
opgenPUSH:
	ldi
	ld a,RST_PUSH
	ld (de),a
	inc de
	jr opgen_next_fast
	
opgenPOP:
	ld a,RST_POP
	ld (de),a
	inc de
	jr opgen1byte
	
opgen33:
opgen3B:
	ex de,hl
	ld (hl),$5B	; .LIL
	inc hl
	ld (hl),$FD	; IY
	inc hl
	res 4,c
	ld (hl),c	; INC/DEC
opgen_next_swap_skip:
	ex de,hl
opgen_next_skip:
	inc de
opgen0byte:
	inc hl
opgen_next:
	ld bc,opgentable
	jr opgen_next_fast
	
opgenCB:
	ldi
	ld a,(hl)
	and $07
	cp $06
	jr nz,opgen1byte
opgenswap:
	dec de
	ld a,RST_BITS
	ld (de),a
	inc de
	jr opgen1byte
	
opgenRET:
	ld a,c
	ld (de),a
	ret
	
opgen08:
	ld a,ophandler08 >> 8
	ld c,ophandler08 & $FF
	jr opgenroutinecall2byte
	
opgen31:
	ld a,ophandler31 >> 8
	ld c,ophandler31 & $FF
	jr opgenroutinecall2byte
	
opgenE8:
	ld a,ophandlerE8 >> 8
	ld c,ophandlerE8 & $FF
	jr opgenroutinecall1byte
	

opgenF8:
	ld a,ophandlerF8 >> 8
	ld c,ophandlerF8 & $FF
	jr opgenroutinecall1byte
	
opgen3byte_low:
	inc b
opgen3byte:
	ldi
opgen2byte:
	ldi
opgen1byte:
	ldi
opgen_next_fast:
	ld c,(hl)
	ld a,(bc)
	ld ixl,a
	jp (ix)
	
opgen34:
	ld a,ophandler34 >> 8
	ld c,ophandler34 & $FF
	jr opgenroutinecall
	
opgen35:
	ld a,ophandler35 >> 8
	ld c,ophandler35 & $FF
	jr opgenroutinecall
	
opgen36:
	ld a,ophandler36 >> 8
	ld c,ophandler36 & $FF
	jr opgenroutinecall1byte
	
opgen39:
	ld a,ophandler39 >> 8
	ld c,ophandler39 & $FF
	jr opgenroutinecall
	
opgen76:
	ld a,ophandler76 >> 8
	ld c,ophandler76 & $FF
	jr opgenroutinecall
	
opgenE2:
	ld a,ophandlerE2 >> 8
	ld c,ophandlerE2 & $FF
	jr opgenroutinecall
	
opgenF2:
	ld a,ophandlerF2 >> 8
	ld c,ophandlerF2 & $FF
	jr opgenroutinecall
	
opgenF3:
	ld a,ophandlerF3 >> 8
	ld c,ophandlerF3 & $FF
	jr opgenroutinecall
	
opgenF9:
	ld a,ophandlerF9 >> 8
	ld c,ophandlerF9 & $FF
	jr opgenroutinecall
	
opgenRETI:
	jr _opgenRETI
opgenEI:
	jr _opgenEI
opgenINVALID:
	jr _opgenINVALID
	
	.echo "Opgen routine size: ", $ - opgenroutines
	
opgenroutinecall2byte:
	ex de,hl
	ld (hl),$CD
	inc hl
	ld (hl),c
	inc hl
	ld (hl),a
	inc hl
	inc de
	ex de,hl
	jr opgen2byte
	
opgenroutinecall1byte:
	ex de,hl
	ld (hl),$CD
	inc hl
	ld (hl),c
	inc hl
	ld (hl),a
	inc hl
	inc de
	ex de,hl
	jr opgen1byte
	
_opgenEI:
	; Check the next opcode for special cases
	inc hl
	ld a,(hl)
	dec hl
	cp $76	;HALT
	jr z,_
	and $EF
	cp $C9	;RET/RETI
	ld a,ophandlerEI >> 8
	ld c,ophandlerEI & $FF
	jr nz,opgenroutinecall
_
	ld a,ophandlerEI_delayed >> 8
	ld c,ophandlerEI_delayed & $FF
	
opgenroutinecall:
	ex de,hl
	ld (hl),$CD
	inc hl
	ld (hl),c
	inc hl
	ld (hl),a
	inc hl
	inc de
	ex de,hl
	jr opgen_next_fast
	
_opgenRETI:
	ex de,hl
	ld (hl),$C3 ;JP ophandlerRETI
	inc hl
	ld (hl),ophandlerRETI & $FF
	inc hl
	ld (hl),ophandlerRETI >> 8
	ex de,hl
	ret
	
_opgenINVALID:
	ex de,hl
	ld (hl),$CD
	inc hl
	ld (hl),ophandlerINVALID & $FF
	inc hl
	ld (hl),ophandlerINVALID >> 8
	ex de,hl
	ret
	