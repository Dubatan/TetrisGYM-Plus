; duel - two player mode, switched on with duelModifier
;
; The game logic only knows one player. Each frame both players' state is
; swapped into the regular variables in turn (duelLoadState / duelSaveState),
; player 2 uses the playfield at $0500. The nmi renders from the saved copies,
; see nmi/render_mode_duel.asm.
;
; Both players start from the same state (playfield, trainer setup, random
; seeds) and get the same piece sequence (per player copy of set_seed).
; Score race: the game ends when both players are out (DUEL_BOTH), or as soon
; as the remaining player has more points (DUEL_LEAD).
; B-Type / Checkerboard: the first player to reach the goal wins, a player
; that tops out before loses.

; swapped zeropage state. op is called with the zeropage address and the
; offset into duelState
.macro duelZpState op
    .repeat 32, i
        op tetriminoX+i, i ; $40-$5F
    .endrepeat
    .repeat 4, i
        op score+i, 32+i
        op binScore+i, 36+i
    .endrepeat
        op spawnID, 40
        op set_seed, 41
        op set_seed+1, 42
        op set_seed+2, 43
        op nextPiece, 44
        op renderFlags, 45
        op allegro, 46
        op pendingGarbage, 47
        op crashState, 48
        op allegroIndex, 49
        op wasAllegro, 50
        op rng_seed, 51
        op rng_seed+1, 52
        op spawnCount, 53
        op lagState, 54
    .repeat 4, i
        op lineClearStatsByType+i, 55+i ; read by testCrash
    .endrepeat
.endmacro

.macro duelLoadByte addr, offset
        lda duelState+offset,x
        sta addr
.endmacro

.macro duelSaveByte addr, offset
        lda addr
        sta duelState+offset,x
.endmacro

.assert D_CRASH = 48, error, "D_CRASH does not match duelZpState"
D_ABSOLUTE = 59 ; linecapState, invisibleFlag, currentFloor, hardDropGhostY, presetIndex, spawnDelay
.assert D_INVISIBLE = D_ABSOLUTE+1, error, "D_INVISIBLE does not match"
.assert D_STATUS >= D_ABSOLUTE+6, error, "D_STATUS overlaps swapped state"

; shortcut: these modes are not available in a duel (single player HUD or
; state that is not swapped), the menu does not start them
; -> carry set if the current mode can be started
duelModeAllowed:
        sec
        lda duelModifier
        beq @ret
        lda practiseType
        cmp #MODE_TSPINS
        beq @no
        cmp #MODE_PARITY
        beq @no
        cmp #MODE_PACE
        beq @no
        cmp #MODE_TAPQTY
        beq @no
        sec
        rts
@no:    clc
@ret:   rts

; unrolled, a table driven loop took 5000 cycles per frame for both players
duelLoadState:
        ldx duelBase
        duelZpState duelLoadByte
        lda duelState+D_ABSOLUTE,x
        sta linecapState
        lda duelState+D_ABSOLUTE+1,x
        sta invisibleFlag
        lda duelState+D_ABSOLUTE+2,x
        sta currentFloor
        lda duelState+D_ABSOLUTE+3,x
        sta hardDropGhostY
        lda duelState+D_ABSOLUTE+4,x
        sta presetIndex
        lda duelState+D_ABSOLUTE+5,x
        sta spawnDelay
        rts

duelSaveState:
        ldx duelBase
        duelZpState duelSaveByte
        lda linecapState
        sta duelState+D_ABSOLUTE,x
        lda invisibleFlag
        sta duelState+D_ABSOLUTE+1,x
        lda currentFloor
        sta duelState+D_ABSOLUTE+2,x
        lda hardDropGhostY
        sta duelState+D_ABSOLUTE+3,x
        lda presetIndex
        sta duelState+D_ABSOLUTE+4,x
        lda spawnDelay
        sta duelState+D_ABSOLUTE+5,x
        rts

; called in gameModeState_initGameState before the first frame is rendered
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
        stx duelState+D_GOAL
        stx duelState+DUEL_SIZE+D_GOAL
        stx duelDirty
        lda #$FE ; force next piece draw
        sta duelNextShown
        sta duelNextShown+1
        ldx #$FF
        lda practiseType
        cmp #MODE_LOWSTACK
        bne @noLowStack
        lda #19
        sec
        sbc lowStackRowModifier
        tax
@noLowStack:
        stx duelLowStackRow
        jsr duelSaveBoth
        lda #$09
        sta renderMode
        rts

; called at the end of gameModeState_initGameState, after the trainers set up
; player 1's playfield. player 2 starts with an identical copy
duelInitFinish:
        ldx #$00
@copyPlayfield:
        lda playfield,x
        sta playfield+$100,x
        inx
        bne @copyPlayfield
duelSaveBoth:
        lda #$00
        sta duelBase
        jsr duelSaveState
        lda #DUEL_SIZE
        sta duelBase
        jmp duelSaveState

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
        ; hard drop ghost: with both pieces and both ghosts more than 8 sprites
        ; can share a scanline. the ghosts go to the end of oam so only they
        ; drop out, and swap priority every frame so neither is gone for good
        lda oamStagingLength
        sec
        sbc duelTmp
        cmp #$20
        bne @noGhost
        lda frameCounter
        eor duelPlayer
        lsr
        ldy #$E0
        bcc @ghostSlot
        ldy #$F0
@ghostSlot:
        ldx duelTmp
@moveGhost:
        lda oamStaging+$10,x
        sta oamStaging,y
        lda #$FF
        sta oamStaging+$10,x
        inx
        iny
        tya
        and #$0F
        bne @moveGhost
        lda duelTmp
        clc
        adc #$10
        sta oamStagingLength
@noGhost:
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
        ldy practiseType
        cpy #MODE_HARDDROP ; select is sonic drop, next piece always shown
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
        ; b-type / checkerboard goal, both on the same frame is a draw
        lda duelState+DUEL_SIZE+D_GOAL
        asl
        ora duelState+D_GOAL
        beq @noGoal
        cmp #$03
        bne duelEnd
        lda #$00
        beq duelEnd
@noGoal:
        lda duelState+D_STATUS
        ora duelState+DUEL_SIZE+D_STATUS
        beq @ret
        lda practiseType
        cmp #MODE_TYPEB
        beq @race
        cmp #MODE_CHECKERBOARD
        bne @score
@race:  ; whoever is out first loses
        lda #$00 ; both out
        ldx duelState+D_STATUS
        beq @player1Wins
        ldx duelState+DUEL_SIZE+D_STATUS
        bne duelEnd
        lda #$02
        bne duelEnd
@player1Wins:
        lda #$01
        bne duelEnd
@score:
        jsr duelCompareScores
        ldx duelState+D_STATUS
        beq @player2Out
        ldx duelState+DUEL_SIZE+D_STATUS
        bne duelEnd ; both out
        ldx duelModifier
        cpx #DUEL_BOTH
        beq @ret
        ; only player 1 out, player 2 has to pass
        cmp #$02
        beq duelEnd
@ret:   rts
@player2Out:
        ldx duelModifier
        cpx #DUEL_BOTH
        beq @ret
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
        sta duelState+D_INVISIBLE ; show the result in invisible mode
        sta duelState+DUEL_SIZE+D_INVISIBLE
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
        ldy #>(playfield+$100)
        jsr memset_page
        lda #$00
        sta vramRow
        sta duelState+D_VRAMROW
        sta duelState+DUEL_SIZE+D_VRAMROW
        lda #$01
        sta playState
        jsr updateAudioWaitForNmiAndResetOamStaging
        lda practiseType
        cmp #MODE_KILLX2
        bne @levelMenu
        ; double killscreen has no level menu, start the next game directly
        lda #29
        sta levelNumber
        lda #$FF ; gameModeState_next increments this to 0, initGameBackground
        sta gameModeState
        rts
@levelMenu:
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
