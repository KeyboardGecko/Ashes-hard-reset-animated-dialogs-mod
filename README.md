# [**Ashes: Hard Reset**](https://www.moddb.com/mods/ashes-2063) talking heads mod

<a href="https://youtu.be/8HwKkJ2bK_Y">
  <img src="https://img.youtube.com/vi/8HwKkJ2bK_Y/maxresdefault.jpg" width="600">
</a>

An enhancement mod expanding the standard Strife dialogue system of **GZDoom/UZDoom** for Ashes:HR.

## ✨ Mod features
- Animations for all dialogue portraits, similar to fallout 1 and 2.
- Idle animations.
- Smooth transitions between dialogue steps (no flickering).
- Updated dialog audio files.
- Dialog audios are put into channel 5 (previously CHAN_VOICE).
- Separate submenu in the game's main menu for dialogue settings, including dialog window size, dialog volume, etc.

## 👀 In this repo you'll find
- .PK3-file to use with latest Ashes: HR.
- The same exact .pk3, but unpacked.
- Animation making tool.

This animation mod can be used not only for Ashes: HR, but for any GZ/UZdoom game. Feel free to use it in your projects and leave feedback in issues.


---

## 🔹 How to Launch mod
1. Load the `.PK3` file **together with** Ashes: Hard Reset.PK3 into GZDoom or UZDoom (you can drag'n'drop both files into GZdoom.exe/UZDoom.exe).  
2. Enjoy the game.

---

## 🛠️ How to use Animation Making Tool
1. Start the tool.  
2. Create LANGUAGE_ANIM.txt lump in the root of your mod. Open it.
   No matter where LANGUAGE_ANIM.txt is, two folders will be created: graphics/dialog and sounds/voices. So it makes sense to put your LANGUAGE_ANIM.txt in the root of your mod, near LANGUAGE, MAPINFO, etc.
3. Create a character (`Project` - `add character`, or `Animation library` - `Character actions` - `Add character`)
   It will create graphics/dialog/<character> folder - that's where you put your animation frames.
   Take note of the following GZ/UZdoom quirks:
    - every frame should have length of 6 symbols max
    - every frame should have a distinct name across ALL the frames.
   The same goes for sounds/voices. Currently voice files are just put together, without any subfolders.
5. You ar now ready to create your animation. Put frames into graphics/dialog/<character> and sounds into sounds/voices.
6. Load audio file.
   Preferably **WAV** (the only format that draws the waveform correctly). UPD: loading .ogg now creates a .wav, which is used once to draw a waveform. You can safely remove it. 
9. Place **clipmarks** on the timeline ("B" hotkey).  
10. Add **labels** to clipmarks.  
11. Load images into clipmarks. All clipmarks with the same label will share the same images.  
12. Done. You'll get the hang of it as you use the tool. Don't forget to save the project. Explore the `Project` - `Settings` menu for more hotkeys.
<img width="1259" height="974" alt="image" src="https://github.com/user-attachments/assets/d68d1956-6a27-4d33-9285-c76741f6cc1c" />

---

## 📂 Things to Note
- Animation projects are all in `LANGUAGE_ANIM`. No more external JSON-files for every animation.
- App uses a dictionary to set labels to your frames (for example, you may want to use short names for frames, like L, M, etc. while files have names like MPYL, MPYM). If this dictionary is empty, app will load frame names as labels. Dictionary can be found in animaker_labels.json file.
- `Loop` button loops your animation. Mostly used for IDLE-animations.
- To make part of your animation unskippable, select some of the frames and press `UNSKIPPABLE` button. If you want it to play randomly - use `RANDOM` button and set the chance of animation appearing. You can also add additional soundfile to unskippable sequence with corresponding button.
  Example - IDLE-animation (loop, no audio) + additional segment with audio, 25% chance of appearing:
 <img width="800" height="450" alt="wham" src="https://github.com/user-attachments/assets/6812f8ba-226f-40a1-95de-456fdd902c1f" />

 
- Use `edit step variants` button in your frame to add some more randomization to your animations - set different durations or interchangeable frames. Again, useful for IDLE-animations.
- Background can be set for all animations of the character (`BACKGROUND` - `set character background`, then `INHERIT` in every animation by default). Or you can use a specific background for animation. Or none at all.
  <img width="1000" height="500" alt="image" src="https://github.com/user-attachments/assets/6084814b-9c24-41d2-bc36-c517191d737f" />

- **IDLE animations** are always created with the character. Be sure to fill them with frames.
