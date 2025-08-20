# GZDoom Strife Dialog Replacement Mod + Animation Making Tool

A mod replacing the standard Strife dialog system for **GZDoom**.

## ✨ Features
- Animations for dialog portraits, akin to fallout 1 and 2. 
- Smooth transitions between dialog steps (no flickering).
- Dialog audios are separated into channels 5 and 6 (from CHAN_VOICE).
- Idle animations (plays after current animation).
- Fallback image: if there's no animations, the PANEL image from strife dialog is used.
- Separate submenu in the game's main menu for fine-tuning.
- Separate animation making tool  

Originally intended for [**Ashes: Hard Reset**](https://www.moddb.com/mods/ashes-2063) – play it!

---

## 🔹 How to Test
1. Load the `.PK3` file **together with** Ashes HR PK3 into GZDoom.  
2. Start the game and talk to **Jimmy** (may use the console command "changemap MAP02" to speed up the process).

---

## 🛠️ Animation Making Tool
1. Start the tool.  
2. Upload an audio file – preferably **WAV** (the only format that draws the waveform correctly).  
3. Place **clipmarks** on the timeline.  
4. Add **labels** to clipmarks.  
5. Load images into clipmarks (all clipmarks with the same label will share the same images).  
6. Done. You'll get the hang of it as you use the tool. Don't forget to save the project. Explore the `Settings` menu for hotkeys.  

---

## 📂 Things to Note
- Animation projects are saved in **JSON format** (look into `animation files` folder).  
- Export animations into the `LANGUAGE_ANIM` lump via "menu" - "Export to LANGUAGE_ANIM".
 - You can find images for animation projects in 
⚠️ Don’t forget to select **all JSONs** you want to include into LANGUAGE_ANIM.  
- **IDLE animations** are empty by default – you’ll need to write them in using basic method of typing with hands. See `LANGUAGE_ANIM` for details.
- Animation images are stored in: graphics/dialog/JM.
  Create the "clear faces" folder in the same folder your project files are, put images there, then open any project file.

