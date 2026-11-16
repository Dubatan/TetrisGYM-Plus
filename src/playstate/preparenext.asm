playState_prepareNext:
        lda practiseType
        cmp #MODE_CHECKERBOARD
        bne @checkBType
        lda completedRow+3
        cmp #$13
        bne endOfEndingCode
        jmp typeBEndingStuff

        ; bTypeGoalCheck
@checkBType:
        cmp #MODE_TYPEB
        bne endOfEndingCode
        lda lines
        bne endOfEndingCode

        jsr typeBEndingStuff

addBTypeBonus:
        ; patch levelNumber with score multiplier
        ldx levelNumber
        stx tmp3 ; and save a copy
        lda levelDisplayTable, x
        and #$F
        clc
        adc typeBModifier
        sta levelNumber
        beq @typeBScoreDone
        dec levelNumber

        ; patch some stuff
        lda #$5
        sta completedLines
        jsr addPointsRaw

        ; restore level
@typeBScoreDone:
        lda tmp3
        sta levelNumber

        rts
endOfEndingCode:

        lda linecapState
        cmp #LINECAP_HALT
        bne @linecapHaltEnd
        ldx #<haltEndingGraphic
        ldy #>haltEndingGraphic

        lda crashState ; LINECAP_HALT set in testCrash
        cmp #$F0
        bne @nonCrash
        ldx #<crashGraphic
        ldy #>crashGraphic
@nonCrash:
        jmp copyGraphic

@linecapHaltEnd:
        jsr practisePrepareNext
        inc playState
        rts

typeBEndingStuff:
        lda duelModifier
        beq @noDuel
        ; duel: this player reached the goal, see duelCheckEnd
        ldx duelBase
        lda #$01
        sta duelState+D_GOAL,x
@noDuel:
        ldx #<typebSuccessGraphic
        ldy #>typebSuccessGraphic
copyGraphic:
        jsr copyGraphicToPlayfield

typeBEndingStuffEnd:
        ; play sfx
        lda #$4
        sta soundEffectSlot1Init

        lda duelModifier
        beq @single
        ; duel: no sleep, the other player keeps playing
        lda #$0A ; playState_checkStartGameOver
        sta playState
        rts
@single:

        lda renderFlags ; Flag needed to reveal hidden score
        ora #$4
        sta renderFlags
        lda #$0A ; playState_checkStartGameOver
        sta playState
        lda #$30
        jmp sleep_gameplay_nextSprite

sleep_gameplay_nextSprite:
        sta sleepCounter
        jsr stageSpriteForNextPiece
@loop:  jsr updateAudioWaitForNmiAndResetOamStaging
        jsr stageSpriteForNextPiece
        lda sleepCounter
        bne @loop
        rts

copyGraphicToPlayfield:
        lda #$09 ; default row
copyGraphicToPlayfieldAtCustomRow:
        stx generalCounter
        sty generalCounter2
        tax
        lda multBy10Table,x
        clc
        adc #$02 ; indent
        sta playfieldAddr ; restored to 0 below. player 2 playfield in duel mode
        ldy #$00
@copySuccessGraphic:
        lda (generalCounter),y
        beq @graphicCopied
        sta (playfieldAddr),y
        iny
        bne @copySuccessGraphic
@graphicCopied: ; 0 in accumulator
        sta playfieldAddr
        sta vramRow
        rts

; $28 is ! in game tileset
lowStackNopeGraphic:
        .byte   "N","O","P","E",$FF,$28,$00
haltEndingGraphic:
        .byte   $FF,'G','G',$FF,$28,$00
typebSuccessGraphic:
        .byte   'N','I','C','E',$FF,$28,$00
crashGraphic:
        .byte   'C','R','A','S','H',$28,$00
