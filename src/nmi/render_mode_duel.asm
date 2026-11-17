; renderer for duel mode, reads the saved per player state (see modes/duel.asm)
;
; vblank budget on NTSC is ~2270 cycles including the sprite DMA (514), so the
; playfield copy is unrolled (8 rows ~950 cycles) and only one player's HUD is
; drawn per frame, one group of values at a time (worst case ~300 cycles)

DUEL_FIELD_ROW = 6
DUEL_FIELD_X_PLAYER1 = 2
DUEL_FIELD_X_PLAYER2 = 20

duelNmiBase = duelNmi
duelNmiPlayer = duelNmi+1
duelNmiLeft = duelNmi+2
duelNmiRight = duelNmi+3
duelNmiCount = duelNmi+4
duelNmiTile = duelNmi+5

; 4 rows, like render_playfield. playfield data only (fast path)
.macro duelCopyRowsFast base, field, vramLo
.repeat 4
        ldy duelState+base+D_VRAMROW
        cpy #$14
        bcs :++
        lda duelVramHi,y
        sta PPUADDR
        lda vramLo,y
        sta PPUADDR
        ldx multBy10Table,y
    .repeat 10, i
        lda field+i,x
        sta PPUDATA
    .endrepeat
        iny
        cpy #$14
        bcc :+
        ldy #$20
:       sty duelState+base+D_VRAMROW
:
.endrepeat
.endmacro

; same with the low stack line and invisible mode
.macro duelCopyRows base, field, vramLo
.repeat 4
        ldy duelState+base+D_VRAMROW
        cpy #$14
        bcc :+
        jmp :+++++
:
        lda duelVramHi,y
        sta PPUADDR
        lda vramLo,y
        sta PPUADDR
        lda #LOW_STACK_LINE
        cpy duelLowStackRow
        beq :+
        lda #EMPTY_TILE
        ldx duelState+base+D_INVISIBLE
        bne :+
        ldx multBy10Table,y
    .repeat 10, i
        lda field+i,x
        sta PPUDATA
    .endrepeat
        jmp :++
:   ; low stack line or invisible row
    .repeat 10
        sta PPUDATA
    .endrepeat
:       iny
        cpy #$14
        bcc :+
        ldy #$20
:       sty duelState+base+D_VRAMROW
:
.endrepeat
.endmacro

; a player whose state is loaded in the main loop (lag frame) is skipped, the
; main loop would overwrite the changes when it saves the state
render_mode_duel:
        lda duelLoaded
        bne :+
        jmp @player2
:       lda duelState+D_PLAYSTATE
        cmp #$04
        bne @player1Rows
        ldx #$00
        jsr duelLineClearingAnimation
        jmp @player2
@player1Rows:
        lda duelLowStackRow
        cmp #$FF
        bne :+
        lda duelState+0+D_INVISIBLE
        beq :++
:       jmp @player1Special
:
        duelCopyRowsFast 0, playfield, duelVramLoPlayer1
        jmp @player1RowsDone
@player1Special:
        duelCopyRows 0, playfield, duelVramLoPlayer1
@player1RowsDone:
@player2:
        lda duelLoaded
        cmp #DUEL_SIZE
        bne :+
        jmp @hud
:       lda duelState+DUEL_SIZE+D_PLAYSTATE
        cmp #$04
        bne @player2Rows
        ldx #DUEL_SIZE
        jsr duelLineClearingAnimation
        jmp @hud
@player2Rows:
        lda duelLowStackRow
        cmp #$FF
        bne :+
        lda duelState+DUEL_SIZE+D_INVISIBLE
        beq :++
:       jmp @player2Special
:
        duelCopyRowsFast DUEL_SIZE, playfield+$100, duelVramLoPlayer2
        jmp @player2RowsDone
@player2Special:
        duelCopyRows DUEL_SIZE, playfield+$100, duelVramLoPlayer2
@player2RowsDone:
@hud:
        ldx #$00
        ldy #$00
        lda frameCounter
        lsr
        bcc @renderHud
        ldx #DUEL_SIZE
        iny
@renderHud:
        jsr duelRenderHud

; same as single player, for either player's tetris
        lda #$3F
        sta PPUADDR
        lda #$0E
        sta PPUADDR
        ldx #$00
        lda duelState+D_COMPLETEDLINES
        cmp #$04
        beq @tetris
        lda duelState+DUEL_SIZE+D_COMPLETEDLINES
        cmp #$04
        bne @setPaletteColor
@tetris:
        lda frameCounter
        and #$03
        bne @setPaletteColor
        ldx #$30
        lda frameCounter
        and #$07
        bne @setPaletteColor
        lda #$09
        sta soundEffectSlot1Init
@setPaletteColor:
        lda disableFlashFlag
        bne @noFlash
        stx PPUDATA
@noFlash:
        jmp resetScroll

; x - offset into duelState
duelLineClearingAnimation:
        lda frameCounter
        ldy patchedFlag
        beq @unpatched
        sec
        sbc duelState+D_PHASE,x
@unpatched:
        and #$03
        bne @ret
        stx duelNmiBase
        lda #$FF
        ldy duelState+D_INVISIBLE,x
        beq @visible
        lda #BLOCK_TILES ; invisible mode shows blocks instead of empty
@visible:
        sta duelNmiTile
        ldy duelState+D_ROWY,x
        lda #$00
        cpx #$00
        beq @player1
        lda #DUEL_FIELD_X_PLAYER2-DUEL_FIELD_X_PLAYER1
@player1:
        pha
        clc
        adc leftColumns,y
        sta duelNmiLeft
        pla
        clc
        adc rightColumns,y
        sta duelNmiRight
        lda #$04
        sta duelNmiCount
@nextRow:
        ldy duelState+D_COMPLETEDROW,x
        beq @rowDone
        lda duelVramHi,y
        sta PPUADDR
        lda duelVramLoPlayer1,y
        clc
        adc duelNmiLeft
        sta PPUADDR
        lda duelNmiTile
        sta PPUDATA
        lda duelVramHi,y
        sta PPUADDR
        lda duelVramLoPlayer1,y
        clc
        adc duelNmiRight
        sta PPUADDR
        lda duelNmiTile
        sta PPUDATA
@rowDone:
        inx
        dec duelNmiCount
        bne @nextRow
        ldx duelNmiBase
        inc duelState+D_ROWY,x
        lda duelState+D_ROWY,x
        cmp #$05
        bmi @ret
        inc duelState+D_PLAYSTATE,x
@ret:   lda #$00
        sta duelState+D_VRAMROW,x
        rts

; x - offset into duelState, y - player
duelRenderHud:
        cpx duelLoaded
        bne :+
        rts
:       stx duelNmiBase
        sty duelNmiPlayer
        lda duelState+D_FLAGS,x
        and #RENDER_LEVEL
        beq @noLevel
        lda #$20
        sta PPUADDR
        lda duelLevelLo,y
        sta PPUADDR
        lda duelState+D_LEVEL,x
        jsr renderByteBCD
        ldx duelNmiBase
        lda duelState+D_LEVEL,x
        jsr levelToPaletteIndex
        ldy duelNmiPlayer
        lda #$3F
        sta PPUADDR
        lda duelBgPaletteLo,y
        sta PPUADDR
        lda colorTable0,x
        sta PPUDATA
        lda colorTable1,x
        sta PPUDATA
        lda colorTable2,x
        sta PPUDATA
        lda #$3F
        sta PPUADDR
        lda duelBgPaletteLo,y
        ora #$10 ; sprite palette
        sta PPUADDR
        lda colorTable0,x
        sta PPUDATA
        lda colorTable1,x
        sta PPUDATA
        lda colorTable2,x
        sta PPUDATA
        ldx duelNmiBase
        lda duelState+D_FLAGS,x
        and #<~RENDER_LEVEL
        sta duelState+D_FLAGS,x
        rts

@noLevel:
        lda duelState+D_FLAGS,x
        and #RENDER_LINES|RENDER_SCORE
        beq @noScore
        lda #$20
        sta PPUADDR
        lda duelLinesLo,y
        sta PPUADDR
        lda duelState+D_LINESBCDHIGH,x
        jsr twoDigsToPPU
        lda duelState+D_LINES,x
        jsr twoDigsToPPU
        lda #$20
        sta PPUADDR
        lda duelScoreLo,y
        sta PPUADDR
        lda duelState+D_SCORE+3,x
        jsr twoDigsToPPU
        lda duelState+D_SCORE+2,x
        jsr twoDigsToPPU
        lda duelState+D_SCORE+1,x
        jsr twoDigsToPPU
        lda duelState+D_SCORE,x
        jsr twoDigsToPPU
        ; crash mode SHOW: crash face next to the score
        lda crashModifier
        cmp #CRASH_SHOW
        bne @noCrashIcon
        lda duelState+D_CRASH,x
        cmp #$F0
        bne @noCrashIcon
        lda #$20
        sta PPUADDR
        lda duelCrashLo,y
        sta PPUADDR
        lda #$D8
        sta PPUDATA
@noCrashIcon:
        lda duelState+D_FLAGS,x
        and #<~(RENDER_LINES|RENDER_SCORE)
        sta duelState+D_FLAGS,x
        rts

@noScore:
        lda duelDirty
        and duelDirtyBit,y
        beq @noNext
        eor duelDirty
        sta duelDirty
        tya
        asl
        asl
        asl
        tax
        lda #$21
        sta PPUADDR
        lda duelNextLo,y
        sta PPUADDR
    .repeat 4, i
        lda duelNextBuf+i,x
        sta PPUDATA
    .endrepeat
        lda #$21
        sta PPUADDR
        lda duelNextLo,y
        ora #$20 ; next row
        sta PPUADDR
    .repeat 4, i
        lda duelNextBuf+4+i,x
        sta PPUDATA
    .endrepeat
        rts

@noNext:
        lda duelDirty
        bpl @ret
        and #$7F
        sta duelDirty
        jmp duelDrawWins
@ret:   rts

; nametable positions, see nametables/duel.js
duelLevelLo:
        .byte $89,$94 ; row 4
duelLinesLo:
        .byte $68,$74 ; row 3
duelScoreLo:
        .byte $44,$54 ; row 2
duelCrashLo:
        .byte $4C,$5C ; row 2, right of the score
duelNextLo:
        .byte $4E,$CE ; rows 10 & 14, column 14
duelBgPaletteLo:
        .byte $09,$05

duelVramHi:
.repeat 20, i
        .byte >($2000 + (DUEL_FIELD_ROW+i)*32)
.endrepeat
duelVramLoPlayer1:
.repeat 20, i
        .byte <($2000 + (DUEL_FIELD_ROW+i)*32 + DUEL_FIELD_X_PLAYER1)
.endrepeat
duelVramLoPlayer2:
.repeat 20, i
        .byte <($2000 + (DUEL_FIELD_ROW+i)*32 + DUEL_FIELD_X_PLAYER2)
.endrepeat
