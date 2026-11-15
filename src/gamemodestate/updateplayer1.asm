gameModeState_updatePlayer1:
        lda duelModifier
        beq @singlePlayer
        ldx #$00
        jsr duelUpdatePlayer
        inc gameModeState ; 5
        rts
@singlePlayer:
        lda #$04
        sta playfieldAddr+1
        ; copy controller from mirror
        lda newlyPressedButtons_player1
        sta newlyPressedButtons
        lda heldButtons_player1
        sta heldButtons

        jsr checkDebugGameplay
        jsr practiseAdvanceGame
        jsr practiseGameHUD
        jsr branchOnPlayStatePlayer1
        jsr stageSpriteForCurrentPiece
        jsr stageSpriteForNextPiece

        inc gameModeState ; 5
        rts
