# The Last Whistle

A short, atmospheric first-person survival-horror journey for Windows, made in Godot 4.7.2.

You wake alone in a cold, fog-bound forest beside an old steam locomotive. The other passengers of the 7:10 from Ashford are gone. Feed the firebox, get the engine moving, and bring the train 4.7 km down the line to the town of **Greyhaven**. Something tall with a paper face is waiting in the trees. It only moves when you look away.

A full run takes about 15–25 minutes.

**Languages:** English, Español, Русский and 简体中文. Choose one in **Settings → language**; the change applies immediately and is saved. On the first launch the game picks your Windows display language if it is one of these.

## Launch (Windows)

1. Unzip `TheLastWhistle-windows.zip` anywhere.
2. Double-click `TheLastWhistle.exe`. It is a single file with everything embedded, and there is nothing to install.
3. Windows SmartScreen may warn about an unsigned app. Click **More info → Run anyway**.

If the game doesn't start, try `TheLastWhistle.console.exe`. It opens a console window that shows any error messages.

You need a 64-bit Windows 10 or 11 PC with a graphics card that supports Vulkan or Direct3D 12. Most GPUs from 2016 onward do. Otherwise the game falls back to OpenGL 3.3 automatically, with simpler fog.

## Controls

| Action | Input |
|---|---|
| Move / sprint / jump | **W A S D** / **Shift** / **Space** |
| Look | Mouse |
| Interact (shovel coal, levers, whistle, pick up, read) | **E** |
| Close the regulator (throttle) | **Q** while aiming at it |
| Swing the axe | **Left mouse button** |
| Cover or uncover the lantern | **F** |
| Pause menu / close a note | **Esc** |
| Climb a ladder | Walk into it holding **W**, or aim at it and press **E**. **S** climbs down. |

## How to play

- **Starting the engine:** climb the ladder into the cab. Aim at the firebox and press **E** to shovel coal from the tender. Wait for the STEAM needle to climb. Release the **brake** (lever on the left wall), then open the **regulator** (right of the firebox, **E**/**Q**, notches 0–4).
- **Fuel:** a higher regulator notch is faster but burns coal much faster per kilometre. If you close the regulator, the train coasts and saves coal. The HUD shows the distance to Greyhaven, the coal in the tender, the fire level and your speed.
- **Fallen trees** block the line. A red signal and an on-screen warning come before each one. Brake in time: hitting a tree at speed derails the train. Take the axe from the cab wall and chop the tree clear.
- **Coal is scarce.** Abandoned shacks, a wrecked carriage, a signal box, a barn and a ruin near each stop hold coal sacks, bandages and notes. The farther places hold more, but you spend longer off the train. Carry the coal back and tip it into the tender (**E** at the coal bunker).
- **The Stillman** only hunts while you are off the train during a stop. When the woods go quiet, look at it: it can't move while you watch it. Blowing the whistle from the cab drives it off. Hitting it with the axe makes it retreat for a while.
- **Endings:** reach the platform at Greyhaven to survive. You lose if you die, derail, or end up stranded with no fire, no coal and none left nearby. From a defeat you can retry from the last stop, restart the journey, or return to the menu.

Settings are saved to `%APPDATA%\Godot\app_userdata\The Last Whistle\settings.cfg`:

- quality presets, shadows, post-processing, ambient occlusion, volumetric fog, anti-aliasing, view distance, grass density and render scale
- display mode, resolution and V-Sync
- master, music, effects and ambience volume
- mouse sensitivity, field of view and invert Y
- language

## Project

The `last-whistle/` folder is a standard Godot 4.7.2 project. To open it, start Godot 4.7.2 and import `last-whistle/project.godot`. Everything is generated in code:

| Path | Contents |
|---|---|
| `scripts/world.gd` | Route sites, story notes, streaming, objectives, music states, checkpoints, intro, endings |
| `scripts/train.gd` | Locomotive, tender, carriage, cab controls, steam/fuel model, movement, train sounds |
| `scripts/player.gd` | First-person controller, riding the moving train, ladders, interaction, axe, lantern |
| `scripts/creature.gd` | The forest threat |
| `scripts/chunk.gd`, `track.gd` | Streamed 80 m terrain/forest/track sections and the route definition |
| `scripts/props.gd`, `mk.gd`, `mats.gd` | Procedural low-poly models and PBR materials/shaders |
| `scripts/menu.gd`, `settings_panel.gd`, `hud.gd`, `settings.gd`, `audio.gd`, `game.gd` | Menu, settings, HUD and global services |
| `scripts/loc.gd`, `i18n/*.json` | Localisation service and the string tables (`en`, `es`, `ru`, `zh`) |
| `scripts/autotest.gd` | Automated playthrough used to verify the build |
| `tools/subset_fonts.py` | Rebuilds the small Chinese fallback fonts from the characters in `i18n/zh.json`. Run it after editing Chinese text (`python3 tools/subset_fonts.py`, needs fonttools) |
| `tools/gen_audio.py` | Synthesizes every sound and music track in `audio/` (`python3 tools/gen_audio.py`, needs numpy, scipy and ffmpeg) |

### Rebuild the Windows executable

Install Godot 4.7.2 and its export templates, then run from `last-whistle/`:

```
godot --headless --export-release "Windows Desktop" build/windows/TheLastWhistle.exe
```

### Automated check

```
godot --path . -- --autotest
```

This plays through the menu, settings, language switching, intro, ladder, furnace, travel, a stop, the axe, the creature, coal, the whistle, arrival, retry and death. It prints `PASS`/`FAIL` lines and saves screenshots to the user data folder, or to the folder set by the `LW_SHOTS` environment variable. `-- --autotest=lang` captures the menu, settings, a note, the HUD and the pause menu in every language.

## Credits

The game design, story, code, models, textures, sounds and music are original and generated procedurally for this project.

Fonts:

- *Caveat* by Impallari Type, SIL Open Font License (`fonts/OFL.txt`)
- *Special Elite* by Astigmatic, Apache License 2.0 (`fonts/LICENSE.txt`)
- *PT Mono* by ParaType, SIL Open Font License (`fonts/OFL-PTMono.txt`), for Cyrillic typewriter text
- *Ma Shan Zheng* by Ma ShanZheng, SIL Open Font License (`fonts/OFL-MaShanZheng.txt`), subset, for Chinese handwriting
- *Noto Serif SC* by Google, SIL Open Font License (`fonts/OFL-NotoSerifSC.txt`), subset, for Chinese print text

Engine: [Godot Engine](https://godotengine.org), MIT license.
