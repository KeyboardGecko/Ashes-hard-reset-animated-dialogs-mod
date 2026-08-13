# MFA automatic lipsync

The editor can generate a normal, editable ATHM track from the current audio
and an exact transcript. It uses Montreal Forced Aligner (MFA) to align words
and phones, then maps the phones to the nine base ATHM poses:

`DEF`, `M`, `F`, `O`, `U`, `S`, `N`, `EI`, and `A`.

## Portable runtime

No separate Python, Conda, or MFA installation is required. The Windows build
contains Micromamba and uses it to create an isolated MFA environment on the
first Auto Lipsync run.

The first run requires an internet connection and can take several minutes.
ATHM downloads the MFA runtime plus the acoustic model and dictionary for the
selected language. Later runs reuse the local installation. Selecting another
language downloads only that language's models.

Runtime files are stored outside the mod and application directories:

```text
%LOCALAPPDATA%\ATHM\mfa\
```

The download is several hundred megabytes and the installed runtime can use
about 1 GB or more. ATHM removes Micromamba's package download cache after a
successful model installation.

## Usage

1. Open an animation and load its audio.
2. Press **AUTO LIPSYNC**. Allow the initial runtime download to finish if
   this is the first use.
3. Paste the exact spoken transcript.
4. Check the character prefix and language.
5. Press **Generate and replace track**.
6. Review the generated frames and edit them with the normal timeline tools.

The generated frame name is the upper-case character prefix plus its pose,
for example `VNC` + `DEF` becomes `VNCDEF`. Generated names must fit ATHM's
six-character frame-name limit.

The operation replaces the current track, but is recorded as one history step
and can be reverted with Undo.

## Transcript guidelines

- Write what the actor actually says, not necessarily the subtitle.
- Spell numbers and symbols as spoken words.
- Replace placeholders with the spoken value.
- Add game-specific names to an MFA-compatible custom dictionary when needed.
- Remove stage directions unless the corresponding sound is spoken.

MFA is a forced aligner, not speech-to-text: it derives the expected phones
from the transcript and finds their boundaries in the audio. A wrong or
incomplete transcript can therefore shift a whole section of the result.
