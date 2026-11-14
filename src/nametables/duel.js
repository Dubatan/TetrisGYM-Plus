const {
    writeRLE,
    blankNT,
    drawAttrs,
} = require('./nametables');

// duel (2 player) screen; positions must match src/nmi/render_mode_duel.asm

const buffer = blankNT();

const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-';
const text = (x, y, str) => [...str].forEach((d, i) => {
    if (d !== ' ') buffer[y * 32 + x + i] = chars.indexOf(d);
});

// playfield frame, interior is 10x20 at (x+1, 6)
const frame = (x) => {
    const [TL, T, TR, L, R, BL, B, BR] = [0x70, 0x30, 0x71, 0x31, 0x32, 0x72, 0x33, 0x73];
    for (let i = 1; i <= 10; i++) {
        buffer[5 * 32 + x + i] = T;
        buffer[26 * 32 + x + i] = B;
    }
    for (let j = 6; j <= 25; j++) {
        buffer[j * 32 + x] = L;
        buffer[j * 32 + x + 11] = R;
    }
    buffer[5 * 32 + x] = TL;
    buffer[5 * 32 + x + 11] = TR;
    buffer[26 * 32 + x] = BL;
    buffer[26 * 32 + x + 11] = BR;
};

frame(1);
frame(19);

text(13, 2, 'SCORE');
text(13, 3, 'LINES');
text(13, 4, 'LEVEL');
text(14, 7, 'NEXT');
text(15, 9, '1P');
text(15, 13, '2P');
text(13, 20, '1P');
text(14, 18, 'WINS');
text(13, 21, '2P');

// 2 - player 1 field / next, 1 - player 2 field / next
drawAttrs(buffer, [`
    3333333333333333
    3333333333333333
    3333333333333333
    3222223333111113
    3222223333111113
    3222223223111113
    3222223333111113
    3222223113111113
`, `
    3222223333111113
    3222223333111113
    3222223333111113
    3222223333111113
    3222223333111113
    3333333333333333
    3333333333333333
    0000000000000000
`]);

writeRLE(
    __dirname + '/duel_nametable.bin',
    buffer,
);
