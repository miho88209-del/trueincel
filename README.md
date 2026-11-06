# The Last Can of Beans

A funny Western survival game for the browser. You're a broke cowboy riding out one stormy night in Coffin Rock Canyon with a judgmental horse named Biscuit, a tin cup, and one dented can of beans. Gather firewood at sundown, decide whether to risk a run to the abandoned wagon as the storm rolls in, then keep the fire, your warmth, and your belly alive until sunrise.

A run lasts about **9 minutes** (7:00 PM → 6:00 AM). Everything is plain HTML, CSS, and JavaScript. All art is drawn in code on a canvas and all sound is synthesized with WebAudio, so there are no downloads, build steps, or dependencies beyond Python 3.

## Launch (Linux)

From this folder, run:

```bash
python3 -m http.server 8000
```

Or use the included script, which does the same thing:

```bash
./start.sh
```

Then open **http://localhost:8000/** in Chrome or Firefox. Click the page or press **Enter** to start. If port 8000 is taken, use another one (e.g. `python3 -m http.server 8080`, or `PORT=8080 ./start.sh`) and open that port. If your system's `localhost` misbehaves, `http://127.0.0.1:8000/` is the same game.

Stop the server with **Ctrl+C**.

## Controls

| Key | Action |
| --- | --- |
| **A / D** or **← / →** | Walk |
| **Shift** (hold) | Hurry (burns food faster) |
| **E** | Use: gather wood, feed fire, strike a match, search wagon, pet Biscuit, pick things up |
| **B** | Put your beans on the fire to heat |
| **F** | Eat (the beans on the fire, or food from your pack) |
| **C** | Throw your tin cup (raccoons love shiny things) |
| **S** or **↓** (hold) | Crouch: hold your hat in a gust, shield a match from the rain |
| **P** / **Esc** | Pause |
| **M** | Mute |
| **R** | Restart instantly (also Enter on the end screen) |

On-screen prompts show what each key does wherever you're standing, and tips appear as you play.

## How to survive

- **Warmth** drops away from the fire, faster at night, in rain, without your hat, or on an empty belly. If it hits zero, you freeze, and the run is over.
- **Fire** burns down steadily, faster in the storm. Feed it logs (E). If it goes out, you need a match *and* fuel. In the rain, an uncrouched match may fizzle.
- **Belly** empties over the night. Hot beans are the best meal in the territory. Cold beans, prickly pears, and mystery jerky also count.
- **Sundown is the safe time to gather.** The near side of the canyon doesn't have enough wood for the whole night.
- The **abandoned wagon** (far east, past the dry wash) has supplies and boards to burn. After the storm starts, the **wash flash-floods**. Heed the rumble, or get swept back with soaked clothes and no firewood.

## Things that can go sideways (on purpose)

- Heating your beans makes them smell. A **raccoon** shows up (watch the rustling sage and glowing eyes). Shoo it by walking at it, or **throw your tin cup** to distract it. If it grabs the can, chase it down.
- Wander more than a stone's throw from the fire while the beans cook and **Biscuit** will get ideas. If he eats your beans, he gets gassy, and his toots fan the flames (and scare raccoons).
- Eat the beans yourself and you get gassy too. Toot near the fire and you lose your eyebrows. Toot near the raccoon and it runs.
- **Wind gusts** blow your hat off unless you crouch. No hat means a colder night until you chase it down. Tumbleweeds roll by on the wind and make decent kindling.
- Desperate? You can burn Mabel's love letters.

## Files

```
index.html     page + title/end screens
style.css      UI styling
js/audio.js    procedural sound (wind, rain, fire, thunder, guitar, toots)
js/game.js     game logic and canvas rendering
start.sh       convenience launcher (python3 -m http.server)
```

Testing hook: append `?speed=10` to the URL to run the night faster.
