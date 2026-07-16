# ATHM LANGUAGE_ANIM v3

`LANGUAGE_ANIM.txt` is a dedicated ATHM data lump read directly through
`Wads.ReadLump`. It is not localization data and does not depend on
`StringTable` registration.

```ini
[default]

ATHM_FORMAT = "3";
ATHM_CHARACTERS = "JM,VNC";

ATHM_JM_ANIMATIONS = "IDLE,JM001";
ATHM_JM_VOICE_MATCH = "JM*";
ATHM_JM_BACKGROUND = "JM_BG";

ATHM_JM_IDLE_TRACK = "(JMDEF|JMBLNK)@(1000|2000)";
ATHM_JM_IDLE_LOOP = "true";
ATHM_JM_IDLE_DURATION_MS = "2400";

ATHM_JM_JM001_TRACK = "JMDEF@292;[JMEEE@169;JMS@161];(JMEE|JME)@(82|100)";
ATHM_JM_JM001_LOOP = "false";
ATHM_JM_JM001_DURATION_MS = "1200";
ATHM_JM_JM001_SOUND = "voices/JM001";
ATHM_JM_JM001_SOUND_OFFSET_MS = "150";
```

`VOICE_MATCH` owns voices which have no dedicated animation and therefore use
the character's `IDLE` track. It supports exact names (`JM001`), prefixes
(`JM*`), and inclusive numeric ranges (`GN021-GN037`). `SOUND` maps a voice to
a specific animation. `VARIANT_OF` inherits voice matching from another
character while keeping separate tracks and images.

If an animation has no `SOUND` assignment, it is intentionally silent. The
editor marks it as `<NOSOUND>`; playback is driven by the animation clock and
does not need a fake audio file.

`DURATION_MS` is an optional minimum master-timeline duration. If a resolved
random pass is shorter, its last frame is held until that minimum. If the pass
is longer, it finishes naturally and is never truncated. Without `DURATION_MS`,
every pass has its natural resolved length and a loop immediately rerolls after
the final segment. In the editor, the resize handle cannot go below the
currently selected pass or the end of its audio track. `SOUND_OFFSET_MS`
places the reference audio inside the editor timeline. GZDoom still starts
dialogue audio itself, so the offset is currently editor alignment metadata;
the ZScript runtime uses `DURATION_MS` but does not delay the game sound.

## Track grammar

- `FRAME@DURATION` is one deterministic segment.
- `(A|B)@100` randomly selects a frame.
- `A@(80|120)` randomly selects a duration.
- `[A@100;B@120]` is an atomic locked sequence.
- Top-level segments are separated by `;`.

In the editor, every step has one selected frame variant and one selected
duration variant. Those selections make preview playback stable and can be
changed with the step's variants button. They are saved in the editor project,
not in `LANGUAGE_ANIM`; the language file keeps the complete choice lists and
GZDoom resolves them randomly at runtime (and again on the next natural loop).

When playback has entered a locked sequence, conversation transitions are
queued until that sequence finishes. The exact reply is captured immediately,
so moving the selection while the sequence plays cannot change the queued
action. A 60-second safety timeout prevents a malformed lock from trapping the
conversation menu forever.

In the editor, frames can be locked one by one with the lock button in each
row. Adjacent locked frames are automatically saved as one `[...]` sequence;
locked frames separated by an unlocked frame remain separate sequences. The
timeline shows each adjacent sequence as an orange `LOCKED` range. The toolbar
button next to `LOOP` applies the same state to the current selection.

Selection follows desktop conventions: click selects one frame, Ctrl+click
toggles a frame, Shift+click selects from the anchor, and dragging empty
timeline space creates a marquee selection. Clicking empty space clears the
selection and seeks without starting a marquee action.

Ctrl+C copies selected frames in chronological order. Ctrl+V inserts them at
the first frame boundary at or after the playhead (or appends them at the end),
shifts following frames, and selects the inserted copies. Frame and duration
variants, preview choices, colors, and locked runs are preserved; audio and
image files are referenced by the destination animation rather than copied.

A future `outro{...}` construct may model an interruption-triggered exit
sequence; it is intentionally separate from a locked sequence.
