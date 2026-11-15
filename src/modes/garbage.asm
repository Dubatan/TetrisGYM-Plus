prepareNextGarbage:
        branchTo garbageModifier, \
            garbageAlwaysTetrisReady, \
            garbageNormal, \
            garbageSmart, \
            garbageHard, \
            garbageTypeC
            ; garbageTypeC = infinite dig

garbageTypeC:
        jsr findTopBulky
        adc #$20 ; offset from starting position
@loop:
        sta tmp3

        jsr random10
        adc tmp3
        tay
        jsr swapMino
        tya

        sta tmp3
        cmp #$c0
        bcc @loop
        rts

; playfield access is (playfieldAddr),y for the duel player 2 playfield

findTopBulky:
        lda #$0
@loop:
        sta tmp3 ; line

        tay
        lda #0
        sta tmp2 ; line block qty
        ldx #9
@loopLine:
        lda (playfieldAddr), y
        cmp #EMPTY_TILE
        beq @noBlock
        inc tmp2
@noBlock:
        iny
        dex
        bne @loopLine
        lda tmp2
        cmp #4 ; requirement
        bpl @done

        lda tmp3
        adc #$A
        cmp #$b8
        bcc @loop
@done:
        tya
        rts

swapMino:
        ldx #EMPTY_TILE
        lda (playfieldAddr), y
        cmp #EMPTY_TILE
        bne @full
        ldx #BLOCK_TILES+3
@full:
        txa
        sta (playfieldAddr), y
        rts

garbageNormal:
        jsr randomHole
        jmp randomGarbage

garbageSmart:
        jsr smartHole
        jmp randomGarbage

; -> x: index of the first block
findTop:
        ldy #$0
@loop:
        lda (playfieldAddr), y
        cmp #EMPTY_TILE
        bne @done
        iny
        cpy #$b8
        bcc @loop
@done:
        tya
        tax
        rts

randomGarbage:
        jsr findTop
        cpx #130
        bcc @done

        lda garbageDelay
        ; cmp #0 ; lda sets z flag
        bne @delay

        jsr random10
        and #3
        sta pendingGarbage
        jsr random10
        and #$7
        adc #$2+1
        sta garbageDelay
@delay:
        dec garbageDelay
@done:
        rts

garbageHard:
        jsr findTop
        cpx #100
        bcc @nothing

        lda spawnCount
        and #1
        bne @nothing
        jsr randomHole
        inc pendingGarbage
@nothing:
        rts

smartHole:
        ldy #199
@loop:
        lda (playfieldAddr), y
        cmp #EMPTY_TILE
        beq @done
        dey
        cpy #190
        bcs @loop
@done:
        tya
        sbc #190
        sta garbageHole
        rts

randomHole:
        jsr random10
        sta garbageHole
        rts

garbageAlwaysTetrisReady:
        ; right well
        lda #9
        sta garbageHole

        lda #0
        sta tmp1 ; garbage to add

        ldy #190
        jsr checkTetrisReady
        ldy #180
        jsr checkTetrisReady
        ldy #170
        jsr checkTetrisReady
        ldy #160
        jsr checkTetrisReady

        lda tmp1
        sta pendingGarbage
        rts

checkTetrisReady:
        ldx #9
@loop:
        lda (playfieldAddr), y
        cmp #EMPTY_TILE
        bne @filled
        inc tmp1 ; add garbage
        ldx #1
@filled:
        iny
        dex
        bne @loop
        rts
