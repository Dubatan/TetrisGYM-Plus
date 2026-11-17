; spin trainer (spinModifier: T, Z, S, L, J, I or random)
;
; A slot is cut into a filled floor, the piece only fits by rotating at the
; bottom: NES Tetris has no wall kicks. T and Z fill the slot cleanly, S, L, J
; and I leave a covered gap where the piece was before it rotated.
; The slot is made for the piece in play. Like with T, a failed spin is
; retried with the same piece, random mode picks a new piece after a success.

advanceGameTSpins:
        ; new slot when the piece does not match (slot left from another mode)
        lda playState
        cmp #1
        bne @typeOk
        lda tetriminoX
        cmp #TETRIMINO_X_HIDE
        beq @typeOk
        ldx currentPiece
        lda tetriminoTypeFromOrientation,x
        ldx spinVariant
        cmp spinVariantType,x
        beq @typeOk
        lda #0
        sta tspinX ; generated below
        sta vramRow
@typeOk:
        ; track the tspin quantity on the first tspin attempt
        ldx spinVariant
        lda spinVariantType,x
        asl
        tay ; statsByType offset of the slot's piece
        lda tspinQuantity
        bne @qtyEnd
        lda tetriminoX
        cmp #$EF
        beq @qtyEnd
        lda statsByType,y
        sta tspinQuantity
@qtyEnd:
        ; reset score if tspinQuantity doesnt match
        lda score
        bne @scrub
        lda score+1
        bne @scrub
        lda score+2
        bne @scrub
        jmp @continue
@scrub:
        lda tspinQuantity
        beq @continue
        cmp statsByType,y
        beq @continue

        jsr clearPoints

        lda renderFlags
        ora #RENDER_SCORE
        sta renderFlags
@continue:

advanceGameTSpins_actual:
        ; see if the piece has reached the right position
        lda #8
        sec
        sbc tspinX
        cmp tetriminoX
        bne @notSuccessful
        lda #18
        sec
        sbc tspinY
        cmp tetriminoY
        bne @notSuccessful
        ; check the orientation
        ldx spinVariant
        lda currentPiece
        cmp spinVariantTarget,x
        bne @notSuccessful

        ; set successful tspin vars
        lda #$3
        sta playState
        lda #0
        sta tspinX
        sta vramRow ; shorter to do it here than in rendering

        ; add score
        lda #$2
        sta completedLines
        jsr addPointsRaw

        ; TODO: copy score to top
        lda #$20
        sta spawnDelay
        lda #TETRIMINO_X_HIDE
        sta tetriminoX

@notSuccessful:
        ; check if a tspin is setup
        lda tspinX
        ; cmp #0 ; lda sets z flag
        bne renderTSpin

generateNewTSpin:
        ldx #rng_seed
        jsr generateNextPseudorandomNumber
        lda rng_seed
        tax
        ; lower nybble
        and #$7
        sta tspinX
        ; high nybbleish
        txa
        ror
        ror
        ror
        ror
        and #3
        sta tspinY
        ; some other bit
        txa
        and #1
        sta tspinType

        lda #0
        sta tspinQuantity

        ; slot for the piece in play, or the next one while it is hidden after
        ; a successful spin. random mode picks that next piece now
        ldx currentPiece
        lda tetriminoX
        cmp #TETRIMINO_X_HIDE
        beq @next
        cpx #$13
        bcc @piece
@next:
        lda spinModifier
        cmp #SPIN_RANDOM
        bcc @nextPiece
        jsr spinRandomPiece
        sta nextPiece
@nextPiece:
        ldx nextPiece
@piece:
        lda tetriminoTypeFromOrientation,x
        tax
        lda spinVariantForType,x
        bne @notT
        ora tspinType ; T: overhang on either side
@notT:
        sta spinVariant
        cmp #SPIN_VARIANT_I
        bne renderTSpin
        lda tspinX ; the I slot is 4 wide, keep it inside the playfield
        cmp #7
        bcc renderTSpin
        lda #6
        sta tspinX

renderTSpin:
        jsr clearPlayfield

        ldx spinVariant
        lda tspinY
        clc
        adc spinVariantFloor,x
        jsr drawFloor

        ; piece position (8 - tspinX, 18 - tspinY) as playfield index
        lda #18
        sec
        sbc tspinY
        tax
        lda multBy10Table,x
        clc
        adc #8
        sec
        sbc tspinX
        sta tmp1

        ; cut the slot
        ldx spinVariant
        ldy spinVariantCells,x
@cell:
        lda spinCells,y
        cmp #SPIN_CELLS_END
        beq @done
        clc
        adc tmp1
        tax
        lda #EMPTY_TILE
        sta playfield,x
        iny
        bne @cell
@done:
        rts

; random mode: called before the first pieces of a game are chosen
spinsInitGame:
        lda spinModifier
        cmp #SPIN_RANDOM
        bcc @ret
        jsr spinRandomPiece
        tax
        lda tetriminoTypeFromOrientation,x
        tax
        lda spinVariantForType,x
        sta spinVariant ; pickTetriminoT deals this piece
        lda #0
        sta tspinX ; slot made on the first frame
@ret:   rts

; -> a: spawn orientation of any piece but O
spinRandomPiece:
        jsr pickRandomTetrimino
        cmp #$0A
        beq spinRandomPiece
        rts

SPIN_CELLS_END = $80
SPIN_VARIANT_I = 6

; per variant: T (open right), T (open left), Z, S, L, J, I
spinVariantTarget: ; orientation the piece must end in
        .byte $02, $02, $08, $0B, $0E, $07, $12
spinVariantType: ; piece type, see tetriminoTypeFromOrientation
        .byte 0, 0, 2, 4, 5, 1, 6
spinVariantFloor: ; floor rows above the piece's row, plus 2
        .byte 3, 3, 3, 3, 3, 3, 4
spinVariantCells:
        .byte spinCellsT0-spinCells, spinCellsT1-spinCells, spinCellsZ-spinCells
        .byte spinCellsS-spinCells, spinCellsL-spinCells, spinCellsJ-spinCells
        .byte spinCellsI-spinCells
; variant for each piece type T, J, Z, O, S, L, I (O never spawns here)
spinVariantForType:
        .byte 0, 5, 2, 0, 3, 4, 6
; spawn orientation for each piece type T, J, Z, O, S, L, I
spinSpawnForType:
        .byte $02, $07, $08, $0A, $0B, $0E, $12

; open cells relative to the piece position (row * 10 + column): the piece in
; its final orientation, plus the cells of the orientation it rotates from and
; their way down. everything else in the floor is filled
spinCells:
spinCellsT0: ; enters as T right, A
        .byte <-1, 0, 1, 10, <-10, <-9, SPIN_CELLS_END
spinCellsT1: ; enters as T left, B
        .byte <-1, 0, 1, 10, <-10, <-11, SPIN_CELLS_END
spinCellsZ: ; enters vertical
        .byte <-1, 0, 10, 11, <-9, 1, <-10, SPIN_CELLS_END
spinCellsS: ; enters vertical, leaves a gap under the right end
        .byte 0, 1, 9, 10, <-10, 11, <-9, SPIN_CELLS_END
spinCellsL: ; enters as L left, B, leaves a gap
        .byte <-1, 0, 1, 9, <-11, <-10, 10, SPIN_CELLS_END
spinCellsJ: ; enters as J right, A, leaves a gap
        .byte <-1, 0, 1, 11, <-10, <-9, 10, SPIN_CELLS_END
spinCellsI: ; enters vertical, leaves a gap below
        .byte <-2, <-1, 0, 1, <-20, <-10, 10, SPIN_CELLS_END
