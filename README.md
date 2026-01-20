# [**Ashes: Hard Reset**](https://www.moddb.com/mods/ashes-2063) talking heads mod

<a href="https://youtu.be/8HwKkJ2bK_Y">
  <img src="https://img.youtube.com/vi/VIDEO_ID/maxresdefault.jpg" width="600">
</a>

An enhancement mod expanding the standard Strife dialogue system of **GZDoom/UZDoom** for Ashes:HR.

## ✨ Mod features
- Animations for all dialogue portraits, similar to fallout 1 and 2.
- Idle animations.
- Smooth transitions between dialogue steps (no flickering).
- Updated dialog audio files.
- Dialog audios are put into channel 5 (previously CHAN_VOICE).
- Separate submenu in the game's main menu for dialogue settings - including dialog window size, dialog volume, etc.

## 👀 In this repo you'll find
- .PK3-file to use with latest Ashes: HR.
- The same exact .pk3, but unpacked.
- Animation making tool.

---

## 🔹 How to Launch mod
1. Load the `.PK3` file **together with** Ashes: Hard Reset.PK3 into GZDoom or UZDoom (you can drag'n'drop both files into GZdoom.exe/UZDoom.exe).  
2. Enjoy the game.

---

## 🛠️ How to use Animation Making Tool
1. Start the tool.  
2. Load audio file – preferably **WAV** (the only format that draws the waveform correctly). UPD: loading .ogg now creates a .wav, which is used once to draw a waveform. You can safely remove it. 
3. Place **clipmarks** on the timeline ("B" hotkey).  
4. Add **labels** to clipmarks.  
5. Load images into clipmarks. All clipmarks with the same label will share the same images.  
6. Done. You'll get the hang of it as you use the tool. Don't forget to save the project. Explore the `Settings` menu for more hotkeys.
<img width="1912" height="1018" alt="image" src="https://github.com/user-attachments/assets/5af99a1f-4f28-432f-972d-506321318f5d" />

---

## 📂 Things to Note
- Animation projects are saved in **JSON format** (look into `animation files` folder).  
- Export animations into the `LANGUAGE_ANIM` lump via "menu" - "Export to LANGUAGE_ANIM". ⚠️ Don’t forget to select **all JSONs** you want to include into your game. Put your new lump into the root of your .pk3.
- **IDLE animations** are empty by default – you’ll need to write them using basic method of typing with hands. See `LANGUAGE_ANIM` - IDLE animations for details.
