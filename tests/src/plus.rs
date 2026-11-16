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
