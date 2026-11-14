; duel - two player score race
;
; The game logic only knows one player. Each frame both players' state is
; swapped into the regular variables in turn (duelLoadState / duelSaveState),
; player 2 uses the playfield at $0500. The nmi renders from the saved copies,
; see nmi/render_mode_duel.asm.
;
; Both players get the same piece sequence (per player copy of set_seed).
; The game ends when both players topped out, or as soon as the remaining
; player has more points than the one that topped out.

; zeropage address of each state byte, 0 terminated, once per player so it can
; be indexed with the same offset as duelState
duelZpTable:
.repeat 2
    .repeat 32, i
        .byte tetriminoX+i
    .endrepeat
        .byte score, score+1, score+2, score+3
        .byte binScore, binScore+1, binScore+2, binScore+3
        .byte spawnID, set_seed, set_seed+1, set_seed+2, nextPiece
        .byte renderFlags
        .byte 0, 0
.endrepeat

duelLoadState:
        ldx duelBase
@loop:  ldy duelZpTable,x
        beq @ret
        lda duelState,x
        sta a:$00,y
        inx
        bne @loop
@ret:   rts

duelSaveState:
        ldx duelBase
@loop:  ldy duelZpTable,x
        beq @ret
        lda a:$00,y
        sta duelState,x
        inx
        bne @loop
@ret:   rts

; called at the end of gameModeState_initGameState, both players start from
; the freshly initialised single player state
duelInit:
        lda #EMPTY_TILE
        ldx #$00
@clearPlayfield:
        sta playfield+$100,x
        inx
        bne @clearPlayfield
        ; x is 0
        stx duelState+D_STATUS
        stx duelState+DUEL_SIZE+D_STATUS
        stx duelDirty
        stx duelBase
        lda #$FE ; force next piece draw
        sta duelNextShown
        sta duelNextShown+1
        jsr duelSaveState
        lda #DUEL_SIZE
        sta duelBase
        jsr duelSaveState
        lda #$09
        sta renderMode
        rts

; x - offset into duelState
duelUpdatePlayer:
        stx duelBase
        jsr duelLoadState
        ldx #$00
        lda duelBase
        beq @player1
        inx
@player1:
        stx duelPlayer
        lda newlyPressedButtons_player1,x
        sta newlyPressedButtons
        lda heldButtons_player1,x
        sta heldButtons
        txa
        clc
        adc #>playfield
        sta playfieldAddr+1
        ldx duelBase
        lda duelState+D_STATUS,x
        bne @stageSprites
        inc fallTimer ; done in updateCountersAndNonPlayerState for single player
        jsr branchOnPlayStatePlayer1
        lda playState
        cmp #$0A
        bne @stageSprites
        ldx duelBase
        inc duelState+D_STATUS,x
@stageSprites:
        ; move the piece from the single player playfield to this player's
        lda oamStagingLength
        sta duelTmp
        jsr stageSpriteForCurrentPiece
        ldy duelPlayer
        ldx duelTmp
@moveSprite:
        cpx oamStagingLength
        bcs @spritesMoved
        lda oamStaging+2,x
        and #$FC
        ora duelSpritePalette,y
        sta oamStaging+2,x
        lda oamStaging+3,x
        clc
        adc duelSpriteXOffset,y
        sta oamStaging+3,x
        inx
        inx
        inx
        inx
        bne @moveSprite
@spritesMoved:
        jsr duelUpdateNextPiece
        jmp duelSaveState

duelSpritePalette:
        .byte $02,$01
duelSpriteXOffset:
        .byte <($10-$60),$A0-$60
duelDirtyBit:
        .byte $01,$02

; next pieces are background tiles, 2 current pieces + 2 next pieces as
; sprites could exceed 8 sprites per scanline
duelUpdateNextPiece:
@tile = duelTmp+1
@count = duelTmp+2
        ldx duelPlayer
        lda nextPiece
        ldy hideNextPiece
        beq @visible
        lda #$FF
@visible:
        cmp duelNextShown,x
        beq @ret
        sta duelNextShown,x
        pha
        txa
        asl
        asl
        asl
        sta duelTmp ; offset into duelNextBuf
        tay
        ldx #$08
        lda #$FF
@clear: sta duelNextBuf,y
        iny
        dex
        bne @clear
        pla
        bmi @setDirty
        tax
        lda tetriminoTileFromOrientation,x
        sta @tile
        txa
        asl
        asl
        tax
        lda #$04
        sta @count
@mino:  lda orientationTableY,x ; 0 or 1 for spawn orientations
        asl
        asl
        clc
        adc #$02
        adc orientationTableX,x ; -2 to 1
        clc
        adc duelTmp
        tay
        lda @tile
        sta duelNextBuf,y
        inx
        dec @count
        bne @mino
@setDirty:
        ldx duelPlayer
        lda duelDirty
        ora duelDirtyBit,x
        sta duelDirty
@ret:   rts

; -> a: 0 - equal, 1 - player 1 has more points, 2 - player 2
duelCompareScores:
        ldx #$03
@loop:  lda duelState+D_BINSCORE,x
        cmp duelState+DUEL_SIZE+D_BINSCORE,x
        bne @different
        dex
        bpl @loop
        lda #$00
        rts
@different:
        lda #$01
        bcs @ret
        lda #$02
@ret:   rts

duelCheckEnd:
        lda duelState+D_STATUS
        ora duelState+DUEL_SIZE+D_STATUS
        beq @ret
        jsr duelCompareScores
        ldx duelState+D_STATUS
        beq @player2Out
        ldx duelState+DUEL_SIZE+D_STATUS
        bne duelEnd ; both out
        ldx duelModifier
        bne @ret
        ; only player 1 out, player 2 has to pass
        cmp #$02
        beq duelEnd
@ret:   rts
@player2Out:
        ldx duelModifier
        bne @ret
        cmp #$01
        beq duelEnd
        rts

; a - winner, 0 for draw
duelEnd:
        tax
        beq @draw
        lda duelWins-1,x
        cmp #99
        bcs @draw
        inc duelWins-1,x
@draw:
        stx duelTmp
        ldy duelTextOffsetPlayer1,x
        ldx #$00
@textPlayer1:
        lda duelText,y
        sta playfield+90,x ; row 9
        iny
        inx
        cpx #$0A
        bne @textPlayer1
        ldx duelTmp
        ldy duelTextOffsetPlayer2,x
        ldx #$00
@textPlayer2:
        lda duelText,y
        sta playfield+$100+90,x
        iny
        inx
        cpx #$0A
        bne @textPlayer2
        lda #$00
        sta duelState+D_VRAMROW
        sta duelState+DUEL_SIZE+D_VRAMROW
        sta duelState+D_COMPLETEDLINES
        sta duelState+DUEL_SIZE+D_COMPLETEDLINES
        lda #$01
        sta duelState+D_STATUS
        sta duelState+DUEL_SIZE+D_STATUS
        lda #$0A
        sta duelState+D_PLAYSTATE
        sta duelState+DUEL_SIZE+D_PLAYSTATE
        lda duelDirty
        ora #$80
        sta duelDirty
        lda #$04
        sta soundEffectSlot1Init
        lda #60
        sta sleepCounter
@wait:  jsr updateAudioWaitForNmiAndResetOamStaging
        lda sleepCounter
        bne @wait
        jsr duelStartPressed
        beq @wait
        ; back to level menu, see gameModeState_handleGameOver
        lda #EMPTY_TILE
        ldx #>playfield
        ldy #>playfield+1
        jsr memset_page
        lda #$00
        sta vramRow
        sta duelState+D_VRAMROW
        sta duelState+DUEL_SIZE+D_VRAMROW
        lda #$01
        sta playState
        jsr updateAudioWaitForNmiAndResetOamStaging
        lda #$03
        sta gameMode
        rts

; indexed by result: draw, player 1 wins, player 2 wins
duelTextOffsetPlayer1:
        .byte 20,0,10
duelTextOffsetPlayer2:
        .byte 20,10,0
duelText:
        .byte EMPTY_TILE,EMPTY_TILE,'W','I','N','N','E','R',EMPTY_TILE,EMPTY_TILE
        .byte EMPTY_TILE,EMPTY_TILE,'L','O','S','E','R',EMPTY_TILE,EMPTY_TILE,EMPTY_TILE
        .byte EMPTY_TILE,EMPTY_TILE,EMPTY_TILE,'D','R','A','W',EMPTY_TILE,EMPTY_TILE,EMPTY_TILE

; either player can pause, background is hidden like in qual mode
duelPause:
        jsr duelStartPressed
        beq @ret
        lda disablePauseFlag
        bne @ret
        lda #$05
        sta musicStagingNoiseHi
        lda #$16
        sta PPUMASK
        lda #$00
        sta renderMode
@loop:  jsr updateAudioWaitForNmiAndResetOamStaging
        lda #$6C
        sta spriteXOffset
        lda #$77
        sta spriteYOffset
        lda #$0A
        sta spriteIndexInOamContentLookup
        jsr stringSprite
        jsr duelStartPressed
        beq @loop
        lda #$1E
        sta PPUMASK
        lda #$00
        sta musicStagingNoiseHi
        lda #$09
        sta renderMode
@ret:   rts

duelStartPressed:
        lda newlyPressedButtons_player1
        ora newlyPressedButtons_player2
        and #BUTTON_START
        rts

; used with rendering disabled and from nmi
duelDrawWins:
        lda #$22
        sta PPUADDR
        lda #$90
        sta PPUADDR
        lda duelWins
        jsr @twoDigits
        lda #$22
        sta PPUADDR
        lda #$B0
        sta PPUADDR
        lda duelWins+1
@twoDigits:
        tax
        lda byteToBcdTable,x
        jmp twoDigsToPPU
