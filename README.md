# The Last Can of Beans

A funny 3D Western survival game for the browser. You're a broke cowboy riding out one stormy night in Coffin Rock Canyon with a judgmental horse named Biscuit, a tin cup, and one dented can of beans. Gather firewood at sundown, scavenge the abandoned wagon, cook dinner, find shelter when the storm rolls in, and keep the fire, and yourself, alive until sunrise.

A night lasts about **9 minutes** (7:00 PM → 6:00 AM). It runs in **English, Français, and Русский**.

The game is plain HTML/CSS/JavaScript with [Three.js](https://threejs.org) r187 included locally in `vendor/`. All models, terrain, and textures are generated in code, and all sound is synthesized with WebAudio. There is nothing to install or build, and it needs no internet connection.

## Launch (Linux)

You need Git and Python 3 (preinstalled on almost every Linux distribution). Run:

```bash
git clone -b hoplite/tenos-e3cc2bbf https://github.com/miho88209-del/trueincel.git
cd trueincel
python3 -m http.server 8000
```

If you already have the folder, just run the last command from inside it.

Then open **http://localhost:8000/** in an up-to-date Chrome/Chromium or Firefox. Click **Ride**, or press **Enter**.

- If port 8000 is taken, use another one: `python3 -m http.server 8080`, then open `http://localhost:8080/`.
- If `localhost` doesn't resolve on your system, use `http://127.0.0.1:8000/`.
- Opening `index.html` directly as a file will **not** work, because browsers block ES modules from `file://`. Use the server.
- Stop the server with **Ctrl+C**.

## Multiplayer (ride with a friend)

One player hosts. The host clones the game and starts the multiplayer server instead of `http.server`:

```bash
git clone -b hoplite/tenos-e3cc2bbf https://github.com/miho88209-del/trueincel.git
cd trueincel
python3 server.py
```

(`./start.sh` does the same.) It needs nothing but Python 3, and prints two addresses:

```
  You:                    http://localhost:8000/
  Friends on your network: http://192.168.1.23:8000/
```

- **Host:** open `http://localhost:8000/`.
- **Friend:** open the "Friends on your network" address in Chrome/Chromium or Firefox on their Linux PC. They don't need to download or install anything.
- Both of you type a name on the title screen and click **Ride**. The first rider hosts the night; anyone who joins later drops into the same night.

**What you share:** the clock and the storm, the campfire (fuel, canvas, beans on the fire), firewood, cactus pears, the wagon's loot, Biscuit, the raccoon, and the thrown cup. **What's yours:** warmth, belly, dryness, your hat, and what you carry. You see each other's cowboys with name tags (a ❄ means your friend is freezing).

- If you freeze, your friend keeps playing. Press **R** to ride back into the same night. If the host freezes or leaves, the other rider takes over the world automatically.
- Pausing doesn't stop the night in multiplayer.
- Keep the game tab open while you play. Minimizing the host's browser can slow the night for everyone.

**Friend not on the same network?** The host's computer has to be reachable from the friend's computer:

- **Easiest:** install [Tailscale](https://tailscale.com/download/linux) (or ZeroTier) on both PCs and join the same network. The friend then opens `http://<host's Tailscale IP>:8000/`.
- **Or:** forward TCP port 8000 on the host's router to the host's PC, then give the friend `http://<your public IP>:8000/`. Stop the server (**Ctrl+C**) when you're done: anyone who can reach that port can join.

If the friend can't connect on the same network, the host's firewall may be blocking the port. On Ubuntu, run `sudo ufw allow 8000/tcp`. To use another port, run `python3 server.py 8080`. The server only shares the game folder, and hidden files such as `.git` are never served.

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
server.py         game server with multiplayer (Python 3 standard library only)
start.sh          launcher for server.py
js/net.js         multiplayer connection (stays solo without server.py)
```

Testing hook: append `?speed=10` to the URL to run the night faster.
