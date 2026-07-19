# ATHM Animaker

ATHM Animaker is a Windows desktop editor for the animated dialogue system used
by the **Ashes: Hard Reset** GZDoom mod.

The editor works directly with `LANGUAGE_ANIM.txt` format 4. JSON is not used as
an intermediate project format.

## Features

- Create a new `LANGUAGE_ANIM.txt` project or open an existing one.
- Add, rename, and remove characters and animations.
- Browse animations through the Animation Library. Selecting a character opens
  its `IDLE` animation when available.
- Edit frame timing on a zoomable timeline.
- Move frames individually or as a selection.
- Copy, cut, and paste timeline frames.
- Define multiple frame variants and duration variants for a step.
- Preview random frame and duration choices.
- Set an explicit animation duration independently of the main audio duration.
- Move the main audio clip inside a longer animation timeline.
- Replace or remove main audio without discarding existing frame timing.
- Enable looping for idle and other repeating animations.
- Lock adjacent frames into unskippable sequences.
- Create optional locked sequences with a configurable playback chance.
- Attach independently positioned audio to optional locked sequences.
- Display waveforms for both main audio and optional sequence audio.
- Assign a character background, inherit it per animation, override it, or
  explicitly disable it.
- Detect missing frames, backgrounds, main sounds, and optional block sounds.
- Preserve short editor labels such as `f`, `s`, or `m` without writing those
  aliases into the mod data.
- Undo and redo timeline and audio edits.
- Restore the last opened `LANGUAGE_ANIM.txt`, character, and animation on the
  next launch.

## Project layout

Animaker expects the following layout relative to `LANGUAGE_ANIM.txt`:

```text
mod-root/
|-- LANGUAGE_ANIM.txt
|-- LANGUAGE_ANIM.txt.bak
|-- SNDINFO
|-- graphics/
|   `-- dialog/
|       |-- AND/
|       |   |-- ANDDEF.png
|       |   |-- ANDBLK.png
|       |   `-- ANDBG.png
|       `-- <CHARACTER_ID>/
|           `-- ...
`-- sounds/
    `-- voices/
        |-- AND01.ogg
        |-- andcln.ogg
        `-- ...
```

Character frames and backgrounds are loaded from:

```text
graphics/dialog/<CHARACTER_ID>/
```

Main dialogue sounds and optional sequence sounds are loaded from:

```text
sounds/voices/
```

File base names are used as resource names. For example, `ANDDEF.png` is the
frame `ANDDEF`, and `AND01.ogg` is the sound `AND01`.

When an optional sequence sound is saved, Animaker adds a missing alias to
`SNDINFO` without removing existing content.

The old `characters/<ID>/images`, `characters/<ID>/sounds`, and JSON project
layouts are not used.

## Editor label aliases

Animaker can use short labels while editing. For example, a frame backed by
`ANDDEF.png` can be shown as `d` in the editor. When the animation is saved,
`ANDDEF` is written to `LANGUAGE_ANIM.txt`.

These aliases are stored in:

```text
animaker_labels.json
```

The file belongs to Animaker and is intentionally kept outside the mod project.
Deleting it does not damage `LANGUAGE_ANIM.txt`; only the short editor labels
are lost.

## Basic workflow

1. Start Animaker.
2. Choose **Open LANGUAGE_ANIM.txt**, or use **Project > New LANGUAGE_ANIM**.
3. Select a character and animation in the Animation Library.
4. Place the required images in `graphics/dialog/<CHARACTER_ID>/`.
5. Place voice files in `sounds/voices/`, or select them through the editor.
6. Add and position frames on the timeline.
7. Edit frame and duration variants where required.
8. Use the lock buttons on frame cards to create unskippable ranges.
9. Configure optional chance and optional audio for random locked sequences.
10. Set the loop and background behavior.
11. Save the current animation with the disk button or `Ctrl+S`.

Saving updates the currently edited animation in `LANGUAGE_ANIM.txt` and
creates `LANGUAGE_ANIM.txt.bak`. When switching away from a modified animation,
Animaker asks whether its changes should be saved.

## Timeline and audio

The upper timeline track represents the full animation duration. Its edge can
be dragged to change the duration.

The main audio track is independent:

- loading or replacing audio does not clear frame timing;
- it can be moved when the animation is longer than the audio;
- the animation cannot be shortened past the end of the audio;
- animations without audio remain fully editable and previewable.

Optional locked-sequence audio is shown on a separate track. Its waveform moves
with the clip and is clipped to the sequence boundaries.

Supported audio inputs:

- WAV
- OGG Vorbis and OGG Opus
- MP3
- FLAC
- M4A/AAC and ALAC
- raw AAC

Original files remain in their source format. For playback analysis and
waveform generation, compressed audio is decoded to a temporary PCM WAV file.

Animaker includes a custom audio-only FFmpeg 8.1.2 build. A system FFmpeg
installation and an `ffmpeg` entry in `PATH` are not required.

## Backgrounds

Background images use the same character directory as foreground frames:

```text
graphics/dialog/<CHARACTER_ID>/
```

A character may define a default background. Each animation may then:

- inherit the character background;
- select a different image;
- use `@none` to disable the background.

Backgrounds are rendered with the same positioning and size as foreground
frames, so an existing frame-sized image can also be used as a background.

## `LANGUAGE_ANIM.txt` format

Animaker writes format 4:

```ini
[default]

ATHM_FORMAT = "4";
ATHM_CHARACTERS = "AND";

ATHM_AND_ANIMATIONS = "IDLE,AND01";
ATHM_AND_VOICE_MATCH = "AND*";
ATHM_AND_BACKGROUND = "ANDBG";

ATHM_AND_IDLE_TRACK = "ANDDEF@(2000|3000);ANDBLK@125";
ATHM_AND_IDLE_LOOP = "true";

ATHM_AND_AND01_TRACK = "ANDDEF@100;(ANDA|ANDO)@(80|120);[ANDT1@60;ANDT2@500];?25<andcln@100>[ANDKY1@80;ANDKY2@300]";
ATHM_AND_AND01_LOOP = "false";
ATHM_AND_AND01_SOUND = "AND01";
ATHM_AND_AND01_SOUND_OFFSET_MS = "50";
```

Track notation:

| Syntax | Meaning |
| --- | --- |
| `FRAME@100` | One frame for 100 ms |
| `(A\|B)@100` | Random frame variant |
| `A@(80\|120)` | Random duration variant |
| `[A@80;B@120]` | Unskippable sequence |
| `?25[A@80;B@120]` | Optional unskippable sequence with a 25% chance |
| `?25<sound@100>[A@80;B@120]` | Optional sequence with sound and a 100 ms sound offset |

The editor is the preferred way to modify this notation because it also
validates names, ranges, durations, and resource references.

## Default keyboard shortcuts

Shortcuts are ignored while typing in a text field or using a dialog.

| Shortcut | Action |
| --- | --- |
| `Space` | Play or pause |
| `B` | Add a frame at the playhead |
| `Left` / `Right` | Seek by 4 ms |
| `Shift+Left` / `Shift+Right` | Seek by 15 ms |
| `+` / `-` | Increase or decrease playback rate |
| `Delete` / `Backspace` | Delete selected frames |
| `Ctrl+C` | Copy selected frames |
| `Ctrl+X` | Cut selected frames |
| `Ctrl+V` | Paste frames at the playhead |
| `Ctrl+Z` | Undo |
| `Ctrl+Y` or `Ctrl+Shift+Z` | Redo |
| `Ctrl+S` | Save the current animation |

Core playback and editing shortcuts can be changed in **Project > Settings**.

## Running from source

### Requirements

- Windows x64
- Flutter stable with Windows desktop support and Dart 3.8.1 or newer
- Visual Studio with the **Desktop development with C++** workload
- Windows Developer Mode if requested by Flutter for plugin symlinks

FFmpeg does not need to be installed separately.

### Run

```powershell
flutter pub get
flutter run -d windows
```

### Analyze and test

```powershell
flutter analyze
flutter test
```

### Build

```powershell
flutter build windows
```

The release bundle is written to:

```text
build/windows/x64/runner/Release/
```

Distribute the complete `Release` directory, not only `animaker.exe`, because
Flutter assets, native libraries, and the bundled FFmpeg are stored beside the
executable.

## Bundled FFmpeg

The Windows build contains a stripped, static, audio-only FFmpeg 8.1.2
executable under:

```text
data/tools/ffmpeg.exe
```

Its license, source reference, checksum, and exact build configuration are
installed under:

```text
data/licenses/ffmpeg/
```

The bundled FFmpeg configuration is LGPL 2.1-or-later and excludes networking,
device capture, and video processing.
