stageSpriteForCurrentPiece:
        lda #$0
        sta pieceTileModifier
        jsr stageSpriteForCurrentPiece_actual

        lda practiseType
        cmp #MODE_HARDDROP
        beq ghostPiece
        rts

ghostPiece:
        lda playState
        cmp #3
        bpl @noGhost
        lda tetriminoY
        sta tmp3
        ; drop distance is the fewest free cells below any of the four minos.
        ; same result as moving down until isPositionValid fails, but several
        ; times faster (two players' ghosts per frame lagged in duel mode)
        ldy tetriminoY
        lda multBy10Table,y
        clc
        adc tetriminoX
        sta generalCounter ; playfield index of the piece
        lda currentPiece
        asl a
        asl a
        tax
        lda #$04
        sta generalCounter3
        lda #$FF
        sta generalCounter2 ; drop distance
@mino:
        ldy orientationTableY,x
        lda multBy10Table,y
        clc
        adc generalCounter
        clc
        adc orientationTableX,x
        tay ; rows above the playfield wrap to 236-255, like in isPositionValid
        lda #$00
        sta generalCounter4 ; free cells below this mino
@cell:
        tya
        clc
        adc #$0A
        tay
        cmp #200
        bcc @read
        cmp #236
        bcc @minoDone ; below the bottom row
@read:
        lda (playfieldAddr),y
        bpl @minoDone ; tiles do not set negative flag
        inc generalCounter4
        bne @cell
@minoDone:
        lda generalCounter4
        cmp generalCounter2
        bcs @notLess
        sta generalCounter2
@notLess:
        inx
        dec generalCounter3
        bne @mino
        lda tetriminoY
        clc
        adc generalCounter2
        sta tetriminoY
        ; save value for use by hard/sonic drop in next frame
        sta hardDropGhostY
        ; check if equal to current position
        cmp tmp3
        beq @noGhost

        lda frameCounter
        and #1
        asl
        asl
        adc #$0D
        sta pieceTileModifier
        jsr stageSpriteForCurrentPiece_actual
        lda tmp3
        sta tetriminoY
@noGhost:
        rts

tileModifierForCurrentPiece:
@currentTile = generalCounter5
        lda pieceTileModifier
        beq @tileNormal
        and #$80
        bne @tileSingle
; @tileMultiple:
        lda @currentTile
        clc
        adc pieceTileModifier
        rts
@tileSingle:
        lda pieceTileModifier
        rts
@tileNormal:
        lda @currentTile
        rts

stageSpriteForCurrentPiece_actual:
@currentTile = generalCounter5
        lda tetriminoX
        cmp #TETRIMINO_X_HIDE
        beq stageSpriteForCurrentPiece_return
        asl a
        asl a
        asl a
        adc #$60
        sta generalCounter3
        clc
        lda tetriminoY
        rol a
        rol a
        rol a
        adc #$2F
        sta generalCounter4
        ldx currentPiece
        lda tetriminoTileFromOrientation,x
        sta @currentTile
        txa
        asl a
        asl a
        tax
        ldy oamStagingLength
        lda #$04
        sta generalCounter2
@stageMino:
        lda orientationTableY,x
        asl a
        asl a
        asl a
        clc
        adc generalCounter4
        sta oamStaging,y
        sta originalY
        inc oamStagingLength
        iny
        jsr tileModifierForCurrentPiece ; used to just load from orientationTable
        ; lda orientationTable, x
        sta oamStaging,y
        inc oamStagingLength
        iny
        lda #$02
        sta oamStaging,y
        lda originalY
        cmp #$2F
        bcs @validYCoordinate
        inc oamStagingLength
        dey
        lda #$FF
        sta oamStaging,y
        iny
        iny
        lda #$00
        sta oamStaging,y
        jmp @finishLoop

@validYCoordinate:
        inc oamStagingLength
        iny
        lda orientationTableX,x
        asl a
        asl a
        asl a
        clc
        adc generalCounter3
        sta oamStaging,y
@finishLoop:
        inc oamStagingLength
        iny
        inx
        dec generalCounter2
        bne @stageMino
stageSpriteForCurrentPiece_return:
        rts

stageSpriteForNextPiece:
        lda hideNextPiece
        bne @maybeDisplayNextPiece

@displayNextPiece:
        lda #$C8
        sta spriteXOffset
        lda #$77
        sta spriteYOffset
        ldx nextPiece
        lda tetriminoTypeFromOrientation,x
        clc
        adc #$6 ; piece sprites start at index 6
        sta spriteIndexInOamContentLookup
        jmp loadSpriteIntoOamStaging

@maybeDisplayNextPiece:
        lda practiseType
        cmp #MODE_HARDDROP
        beq @displayNextPiece
        lda debugFlag
        bne @displayNextPiece
        rts
