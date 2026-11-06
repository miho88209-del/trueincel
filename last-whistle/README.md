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

## Source project

**Engine:** Godot **4.7.2-stable** (standard build, not .NET), build hash `ed1daf0bf`, Forward+ renderer. The project uses only GDScript and has no plugins, addons, GDExtensions or other dependencies. It should also open in later 4.7.x releases, but 4.7.2 is the tested version.

### Open and run in the editor

1. Download Godot 4.7.2 from <https://godotengine.org/download/archive/4.7.2-stable/> (Windows: `Godot_v4.7.2-stable_win64.exe`).
2. Unzip the source package. The folder that contains `project.godot` is the project root.
3. In the Project Manager, click **Import**, select that `project.godot` (or the ZIP itself), then **Import & Edit**.
4. The first open takes a minute while Godot imports the audio and fonts into its `.godot/` cache, which is regenerated automatically and not shipped.
5. Press **F5** (Run Project). The main scene is `scenes/menu.tscn`.

Almost everything is built in code at runtime: the world, models, materials, shaders and UI. The two `.tscn` scenes are entry points that attach `scripts/menu.gd` and `scripts/world.gd`, so open those scripts to edit the game.

| Path | Contents |
|---|---|
| `project.godot`, `export_presets.cfg` | Project settings (autoloads `Settings`, `Loc`, `Sfx`, `Game`) and the "Windows Desktop" export preset |
| `scenes/` | `menu.tscn` (main scene) and `world.tscn` |
| `scripts/world.gd` | Route sites, story notes, streaming, objectives, music states, checkpoints, intro, endings |
| `scripts/train.gd` | Locomotive, tender, carriage, cab controls, steam/fuel model, movement, train sounds |
| `scripts/player.gd` | First-person controller, riding the moving train, ladders, interaction, axe, lantern |
| `scripts/creature.gd` | The forest threat |
| `scripts/chunk.gd`, `track.gd` | Streamed 80 m terrain/forest/track sections and the route definition |
| `scripts/props.gd`, `mk.gd`, `mats.gd` | Procedural low-poly models, PBR materials and the ground/grass/paper shaders (shader code is inline in these scripts and `menu.gd`) |
| `scripts/menu.gd`, `settings_panel.gd`, `hud.gd`, `settings.gd`, `audio.gd`, `game.gd` | Menu, settings, HUD and global services |
| `scripts/loc.gd`, `i18n/*.json` | Localisation service and the string tables (`en`, `es`, `ru`, `zh`) |
| `scripts/autotest.gd` | Automated playthrough used to verify the game |
| `audio/` | All sound effects (`.wav`) and music/ambience loops (`.ogg`), generated by `tools/gen_audio.py` |
| `fonts/` | Game fonts and their licences, including the subset Chinese fonts |
| `icon.png` | Application icon |
| `tools/gen_audio.py` | Synthesizes every file in `audio/` |
| `tools/subset_fonts.py` | Rebuilds `fonts/MaShanZheng-zh.ttf`, `fonts/NotoSerifSC-zh.ttf` and `fonts/PTMono-Regular.ttf` from the full fonts in `tools/font_sources/` |
| `tools/font_sources/` | Full, unsubset source fonts (OFL) used by `subset_fonts.py` |

### Regenerate assets (optional)

Both tools need Python 3.10 or newer.

```
pip install numpy scipy fonttools
python3 tools/gen_audio.py              # all audio, then a verification table; needs ffmpeg with libvorbis on PATH
python3 tools/gen_audio.py --only whistle,chuff --no-verify   # just some files
python3 tools/subset_fonts.py           # after editing i18n/zh.json
```

Godot re-imports changed files the next time the editor gains focus.

### Automated tests

The tests play the real game in a window and need a working GPU, so don't use `--headless`. From the project root:

```
godot --path . -- --autotest
```

On Windows, use `Godot_v4.7.2-stable_win64_console.exe` instead of `godot` so the results print to the console.

- **Full run:** plays through the menu, settings and saving, language switching, intro, note, ladder, furnace, steam, travel, riding the carriage, the first fallen tree, the axe, the creature (watch, stalk, freeze, approach, strike), coal pickup and delivery, healing, the whistle, arrival at Greyhaven, the victory screen, retry from the last stop, and death.
- **Results:** it prints `[AUTOTEST] PASS ...` / `FAIL ...` lines and a final `[AUTOTEST] SUMMARY pass=N fail=M`. The exit code is 0 only if nothing failed. The last verified result is `pass=38 fail=0`.
- **Screenshots:** saved to `%APPDATA%\Godot\app_userdata\The Last Whistle\shots`, or to the folder in the `LW_SHOTS` environment variable.
- **Other modes:**
  - `-- --autotest=lang`: screenshots of each language.
  - `-- --autotest=tour`: screenshots of each landmark.
- **Settings:** the tests change and save settings, including quality and language. Afterwards, use **Settings → reset to defaults** and pick your language again.

### Export the Windows build

1. **Templates:** in the editor, open **Editor → Manage Export Templates → Download and Install** (version 4.7.2.stable). Offline, use **Install from File** with `Godot_v4.7.2-stable_export_templates.tpz` from the same download page.
2. **Export:** choose **Project → Export → Windows Desktop → Export Project**, then save as `build/windows/TheLastWhistle.exe`. Or from the command line:

   ```
   godot --headless --path . --export-release "Windows Desktop" build/windows/TheLastWhistle.exe
   ```

The preset embeds all data in the `.exe` and also writes `TheLastWhistle.console.exe`, a debug launcher that shows errors in a console. The Windows build can be exported from Windows, Linux or macOS.

## Credits

The game design, story, code, models, textures, sounds and music are original and generated procedurally for this project.

Fonts:

- *Caveat* by Impallari Type, SIL Open Font License (`fonts/OFL.txt`)
- *Special Elite* by Astigmatic, Apache License 2.0 (`fonts/LICENSE.txt`)
- *PT Mono* by ParaType, SIL Open Font License (`fonts/OFL-PTMono.txt`), for Cyrillic typewriter text
- *Ma Shan Zheng* by Ma ShanZheng, SIL Open Font License (`fonts/OFL-MaShanZheng.txt`), subset, for Chinese handwriting
- *Noto Serif SC* by Google, SIL Open Font License (`fonts/OFL-NotoSerifSC.txt`), subset, for Chinese print text

Engine: [Godot Engine](https://godotengine.org), MIT license.
