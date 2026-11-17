// tests for the TetrisGYM Plus features (duel, patched)

use crate::{labels, playfield, util};
use rustico_core::nes::NesState;

fn start_game(emu: &mut NesState, setup: impl Fn(&mut NesState)) {
    for _ in 0..3 {
        emu.run_until_vblank();
    }
    setup(emu);
    emu.memory.iram_raw[labels::get("gameMode") as usize] = 4;
    emu.registers.pc = labels::get("mainLoop");
    for _ in 0..11 {
        emu.run_until_vblank();
    }
}

fn set(emu: &mut NesState, label: &str, value: u8) {
    emu.memory.iram_raw[labels::get(label) as usize] = value;
}

fn get(emu: &NesState, label: &str) -> u8 {
    emu.memory.iram_raw[labels::get(label) as usize]
}

/// patched mode: level colours are level mod 10 at every level
pub fn test_patched_palettes() {
    let mut emu = util::emulator(None);
    start_game(&mut emu, |emu| set(emu, "patchedFlag", 1));

    let mut normal = Vec::new();
    for level in 0..256usize {
        set(&mut emu, "levelNumber", level as u8);
        set(&mut emu, "renderFlags", labels::get("RENDER_LEVEL") as u8);
        emu.run_until_vblank();
        let bg_palette = emu.ppu.palette[9..12].to_vec();
        assert_eq!(bg_palette, emu.ppu.palette[25..28].to_vec());
        if level < 10 {
            normal.push(bg_palette);
        } else {
            assert_eq!(bg_palette, normal[level % 10], "level {}", level);
        }
    }
}

/// patched mode: start level 18 transitions at 190 lines instead of 130
pub fn test_patched_levelup() {
    for (patched, lines, level_after) in [
        (0, 0x29, 19), // original: 129 -> 130 lines transitions early
        (1, 0x29, 18),
        (1, 0x89, 19), // patched: 189 -> 190 lines
    ] {
        let mut emu = util::emulator(None);
        start_game(&mut emu, |emu| {
            set(emu, "patchedFlag", patched);
            set(emu, "levelNumber", 18);
            set(emu, "startLevel", 18);
        });
        // single line clear, straight into playState_updateLinesAndStatistics
        set(&mut emu, "lines", lines);
        emu.memory.iram_raw[labels::get("lines") as usize + 1] = 1;
        set(&mut emu, "levelNumber", 18);
        set(&mut emu, "completedLines", 1);
        set(&mut emu, "playState", 5);
        emu.run_until_vblank();
        assert_eq!(get(&emu, "levelNumber"), level_after, "patched {} lines 1{:02x}", patched, lines);
    }
}

/// duel: nmi finishes inside vblank with both playfields and the hud redrawn,
/// for the fast path and the low stack / invisible path
pub fn test_duel_nmi() {
    let mut emu = util::emulator(None);
    start_game(&mut emu, |emu| set(emu, "duelModifier", 2));

    assert_eq!(get(&emu, "renderMode"), 9, "duel renderer not active");

    let state = labels::get("duelState") as usize;
    let size = labels::get("DUEL_SIZE") as usize;
    let vram_row = labels::get("D_VRAMROW") as usize;
    let flags = labels::get("D_FLAGS") as usize;
    let invisible = labels::get("D_INVISIBLE") as usize;
    let full = vec!["##########"; 20].join("\n");
    playfield::set_str_addr(&mut emu, 0x400, &full);
    playfield::set_str_addr(&mut emu, 0x500, &full);

    for frame in 0..60 {
        let special = frame >= 30;
        set(&mut emu, "duelLowStackRow", if special { 10 } else { 0xFF });
        for player in 0..2 {
            let base = state + player * size;
            emu.memory.iram_raw[base + vram_row] = (frame % 5) as u8 * 4;
            emu.memory.iram_raw[base + flags] = (labels::get("RENDER_LINES") | labels::get("RENDER_SCORE")) as u8;
            emu.memory.iram_raw[base + invisible] = (special && player == 1) as u8;
        }
        set(&mut emu, "duelDirty", 0x83);
        while emu.registers.pc != labels::get("renderComplete") {
            emu.step();
            if emu.ppu.current_scanline == 261 {
                panic!("duel render took too long! frame {}", frame);
            }
        }
        emu.run_until_vblank();
    }
}

/// duel: both players get the same piece sequence
pub fn test_duel_pieces() {
    let mut emu = util::emulator(None);
    start_game(&mut emu, |emu| {
        set(emu, "duelModifier", 2);
        set(emu, "levelNumber", 18);
    });

    let state = labels::get("duelState") as usize;
    let size = labels::get("DUEL_SIZE") as usize;
    // currentPiece is inside the $40-$5F block, so its duelState offset is relative to tetriminoX
    let current = (labels::get("currentPiece") - labels::get("tetriminoX")) as usize;

    let mut seq = [Vec::new(), Vec::new()];
    for _ in 0..2000 {
        // player 1 soft drops, player 2 does not: they get out of step
        util::set_controller(&mut emu, 'D');
        emu.run_until_vblank();
        for player in 0..2 {
            let piece = emu.memory.iram_raw[state + player * size + current];
            if piece != 0x13 && seq[player].last() != Some(&piece) {
                seq[player].push(piece);
            }
        }
    }
    let n = seq[0].len().min(seq[1].len());
    assert!(n > 8, "too few pieces: {}", n);
    // consecutive equal pieces collapse to one entry, compare as far as both got
    assert_eq!(seq[0][..n], seq[1][..n]);
}

fn press_p2(emu: &mut NesState, buttons: u8) {
    let mut flipped = 0u8;
    for i in 0..8 {
        flipped |= ((buttons >> i) & 1) << (7 - i);
    }
    emu.p2_input = flipped;
}

/// duel: select hides the next piece only for the player who pressed it
pub fn test_duel_select() {
    let mut emu = util::emulator(None);
    start_game(&mut emu, |emu| set(emu, "duelModifier", 2));

    let state = labels::get("duelState") as usize;
    let size = labels::get("DUEL_SIZE") as usize;
    let hide = |emu: &NesState, player: usize| {
        // offset of hideNextPiece in duelZpState (src/modes/duel.asm)
        emu.memory.iram_raw[state + player * size + 59]
    };
    assert_eq!((hide(&emu, 0), hide(&emu, 1)), (0, 0));

    press_p2(&mut emu, crate::input::SELECT);
    emu.run_until_vblank();
    press_p2(&mut emu, 0);
    for _ in 0..3 {
        emu.run_until_vblank();
    }
    assert_eq!((hide(&emu, 0), hide(&emu, 1)), (0, 1), "player 2 select");

    util::set_controller(&mut emu, 'T');
    emu.run_until_vblank();
    util::set_controller(&mut emu, '.');
    for _ in 0..3 {
        emu.run_until_vblank();
    }
    assert_eq!((hide(&emu, 0), hide(&emu, 1)), (1, 1), "player 1 select");
}

/// duel: the result text stays visible with the low stack line on its row
pub fn test_duel_result_lowstack() {
    let mut emu = util::emulator(None);
    start_game(&mut emu, |emu| {
        set(emu, "duelModifier", 2);
        set(emu, "practiseType", labels::get("MODE_LOWSTACK") as u8);
        set(emu, "lowStackRowModifier", 10); // line on row 9, where the result goes
    });
    assert_eq!(get(&emu, "duelLowStackRow"), 9);

    // both players out on the same frame: draw
    let state = labels::get("duelState") as usize;
    let size = labels::get("DUEL_SIZE") as usize;
    let status = labels::get("D_STATUS") as usize;
    emu.memory.iram_raw[state + status] = 1;
    emu.memory.iram_raw[state + size + status] = 1;
    for _ in 0..10 {
        emu.run_until_vblank();
    }
    assert_eq!(get(&emu, "duelLowStackRow"), 0xFF);
    // row 9 of player 1 is drawn at nametable row 6 + 9, column 2
    let text: Vec<u8> = (0..10).map(|x| emu.ppu.read_byte(&mut *emu.mapper, 0x2000 + 15 * 32 + 2 + x)).collect();
    assert_eq!(text[3..7], [0x0D, 0x1B, 0x0A, 0x20], "DRAW expected, got {:02x?}", text);
}

fn nametable(emu: &mut NesState, address: u16, len: u16) -> Vec<u8> {
    (0..len).map(|i| emu.ppu.read_byte(&mut *emu.mapper, address + i)).collect()
}

/// patched mode: classic scoring shows 8 digits, score and top score past 16 million
pub fn test_patched_eight_digits() {
    for (patched, scoring) in [(1, 0), (0, labels::get("SCORING_EIGHTDIGIT") as u8)] {
        let mut emu = util::emulator(None);
        start_game(&mut emu, |emu| {
            set(emu, "patchedFlag", patched);
            set(emu, "scoringModifier", scoring);
            // top score 16,700,760 (bcd, most significant byte first)
            let top = labels::get("highscores") as usize + 8;
            emu.memory.iram_raw[top..top + 4].copy_from_slice(&[0x16, 0x70, 0x07, 0x60]);
        });
        assert_eq!(get(&emu, "scoringEffective"), labels::get("SCORING_EIGHTDIGIT") as u8);

        // score 23,456,789 (bcd, least significant byte first)
        let score = labels::get("score") as usize;
        emu.memory.iram_raw[score..score + 4].copy_from_slice(&[0x89, 0x67, 0x45, 0x23]);
        set(&mut emu, "renderFlags", labels::get("RENDER_SCORE") as u8);
        for _ in 0..3 {
            emu.run_until_vblank();
        }

        // row 5 and 8, columns 23-30
        assert_eq!(nametable(&mut emu, 0x20B7, 8), [1, 6, 7, 0, 0, 7, 6, 0], "top score, patched {}", patched);
        assert_eq!(nametable(&mut emu, 0x2117, 8), [2, 3, 4, 5, 6, 7, 8, 9], "score, patched {}", patched);
        // box: right wall moved to column 31, left wall removed
        assert_eq!(nametable(&mut emu, 0x211F, 1), [0x36]);
        assert_eq!(nametable(&mut emu, 0x2077, 1), [0xFF]);
    }
}

/// patched mode with hz display: nmi still finishes inside vblank with the
/// 8 digit score, 4 digit lines and level drawn on the same frame
pub fn test_patched_nmi() {
    let mut emu = util::emulator(None);
    start_game(&mut emu, |emu| {
        set(emu, "patchedFlag", 1);
        set(emu, "hzFlag", 1);
        set(emu, "levelNumber", 18);
    });
    let flags = (labels::get("RENDER_LINES") | labels::get("RENDER_LEVEL") | labels::get("RENDER_SCORE")
        | labels::get("RENDER_HZ") | labels::get("RENDER_STATS")) as u8;
    let lines = labels::get("lines") as usize;
    emu.memory.iram_raw[lines] = 0x99;
    emu.memory.iram_raw[lines + 1] = 0x19; // 1999, 4 digit lines
    set(&mut emu, "linesBCDHigh", 0x19);
    for frame in 0..60 {
        set(&mut emu, "renderFlags", flags);
        while emu.registers.pc != labels::get("renderComplete") {
            emu.step();
            if emu.ppu.current_scanline == 261 {
                panic!("render took too long! frame {}", frame);
            }
        }
        emu.run_until_vblank();
    }
}
