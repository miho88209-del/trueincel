# The Last Can of Beans

A funny 3D Western survival game for the browser. You're a broke cowboy riding out one stormy night in Coffin Rock Canyon with a judgmental horse named Biscuit, a tin cup, and one dented can of beans. Gather firewood at sundown, scavenge the abandoned wagon, cook dinner, find shelter when the storm rolls in, and keep the fire, and yourself, alive until sunrise.

A night lasts about **9 minutes** (7:00 PM → 6:00 AM). It runs in **English, Français, and Русский**.

The game is plain HTML/CSS/JavaScript with [Three.js](https://threejs.org) r187 included locally in `vendor/`. All models, terrain, and textures are generated in code, and all sound is synthesized with WebAudio. There is nothing to install or build, and it needs no internet connection.

## Launch (Linux)

You need Python 3 (preinstalled on almost every Linux distribution). From this folder, run:

```bash
python3 -m http.server 8000
```

Or use the included script, which does the same thing:

```bash
./start.sh
```

Then open **http://localhost:8000/** in an up-to-date Chrome/Chromium or Firefox. Click **Ride**, or press **Enter**.

- If port 8000 is taken, use another one: `python3 -m http.server 8080` (or `PORT=8080 ./start.sh`), then open `http://localhost:8080/`.
- If `localhost` doesn't resolve on your system, use `http://127.0.0.1:8000/`.
- Opening `index.html` directly as a file will **not** work, because browsers block ES modules from `file://`. Use the server.
- Stop the server with **Ctrl+C**.

## Controls

| Input | Action |
| --- | --- |
| **W A S D** | Walk (relative to the camera) |
| **Mouse** | Look around (click the game to capture the mouse; or drag with the button held) |
| **Mouse wheel** | Camera distance |
| **Shift** (hold) | Hurry (burns food faster) |
| **E** | Interact: gather wood, feed the fire, strike a match, search the wagon, rig the canvas, pet Biscuit, pick things up |
| **F** | Cook / eat: put the beans on the fire, eat them, or eat food from your pack |
| **Q** | Throw your tin cup where the camera is looking |
| **C** (hold) | Crouch: hold your hat in a gust, shield a match from the rain |
| **Esc** / **P** | Pause menu (language, mouse sensitivity, invert Y, volume, restart) |
| **M** | Mute |
| **Enter** / **R** | Ride again from the end screen (R also restarts from the pause menu) |
| **← / →** | Turn the camera without a mouse |

When you can interact with something, a key prompt appears at the bottom of the screen. On-screen markers point to camp, the wagon, the rock overhang, and anything the wind or a raccoon ran off with.

## Language

Pick **English / Français / Русский** on the title screen or in the pause menu (Esc). The change applies immediately, including menus, the HUD, prompts, tutorial tips, jokes, and the end screens. Your choice is remembered in the browser (`localStorage`). The first launch is in English.

## How to survive

- **Warmth.** Falls away from the fire, faster at night, in the storm, when you're wet, hatless, or starving. At zero you freeze and the run ends.
- **Dryness.** Rain soaks you unless you're sheltered. Wading the dry wash during the storm soaks you fast. Wet clothes make the cold bite much harder. You dry off by the fire.
- **Fire.** Burns down steadily, faster in the rain. Dry wood burns well. Wood gathered in the rain is wet: it burns weak and smoky. In the rain, a match struck without crouching may fizzle.
- **Belly.** Empties over the night. Hot beans are the best meal in the territory. Peaches and prickly pears help too.

### The canyon

- **Camp** sits at the south end, with your fire, bedroll, and Biscuit at the hitching post.
- **Coffin Rock** is the big mesa in the middle. A **slot canyon (the dry wash)** cuts straight through it. That's the shortcut north, but once the storm starts it fills with water and can **flash-flood**. Listen for the rumble.
- The **east trail** goes around the mesa past dead trees and cactus. It's longer, but stays out of the wash.
- The **rock overhang** on the west wall is the only dry place in the storm, and its woodpile stays dry.
- The **abandoned wagon** at the north end has matches, a can of peaches, a blanket, boards to burn, and its **canvas**, which you can rig over your fire to keep it, and you, dry.

### Things that go sideways (on purpose)

- Heating your beans makes them smell. A **raccoon** shows up: watch for the rustling sagebrush. Walk at it to shoo it, or **throw your tin cup [Q]** to distract it. If it grabs the can, run it down.
- Wander off while the beans cook and **Biscuit** will get ideas. If he eats your beans, he gets gassy, and his toots fan the fire (and scare raccoons).
- Eat the beans yourself and *you* get gassy. Toot by the fire and you lose your eyebrows.
- **Wind gusts** steal your hat unless you crouch. No hat means a colder night until you chase it down.
- Desperate? Burn Mabel's love letters.

## Performance

The game targets any machine with working WebGL. If the first seconds of play run slowly, it automatically switches off the expensive shadows and lowers the resolution. To force the light mode from the start, open **http://localhost:8000/?quality=low**.

## Files

```
index.html        page, HUD, title / pause / end screens
style.css         UI styling
js/main.js        3D world, characters, game systems, camera, HUD
js/audio.js       procedural sound (wind, rain, fire, thunder, guitar, toots)
js/i18n.js        language runtime (stores your choice in localStorage)
js/lang/*.js      English, French, Russian strings
vendor/           Three.js r187 (MIT, see vendor/THREE_LICENSE)
start.sh          convenience launcher (python3 -m http.server)
```

Testing hook: append `?speed=10` to the URL to run the night faster.
