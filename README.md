
## Live multiplayer (free)
- **GitHub Pages:** https://adamcantcodelol.github.io/droid-siege/
- **Source + Windows release:** https://github.com/adamcantcodelol/droid-siege — [v1.0 Windows download](https://github.com/adamcantcodelol/droid-siege/releases/tag/v1.0)
- **Single-file HTML (download & open):** [DroidSiege.html](https://github.com/adamcantcodelol/droid-siege/releases/download/v1.0/DroidSiege.html) — double-click to play in any browser (`file://`), no install. Rebuild with `python3 tools/build_single_html.py`.
- **Play in browser:** https://droid-siege.moeller-basil.workers.dev/
- **Room-code relay (built in):** `wss://droid-siege.moeller-basil.workers.dev/ws`
  Host → Multiplayer → Host Game → share the 5-letter code. Friends Join with Code.
  No setup, no paid plan — Cloudflare Workers Free + Durable Objects.
- **Web pause:** Esc unlocks the browser mouse; the pause menu opens automatically. Use **Menu [P]**, or press **P** / **M**, then Resume to recapture the mouse.
  Advanced still lets you override the relay URL if you self-host.

# Droid Siege

A free, multiplayer third-person clone trooper shooter made in **Godot 4.7.2**. It supports co-op against droids (1-4 players) and Versus PvP (1v1 up to 2v2, or Free-for-All). All art is primitive meshes and CSG, and all sounds are generated tones, so there are no external assets.

## Ways to play
| Build | Where | Notes |
|---|---|---|
| `DroidSiege.exe` (Windows) | `DroidSiege-Windows.zip` | Single exe with the game data embedded. Unzip it and double-click. See `PLAY.txt`. |
| Web (HTML5) | `droid-siege-web/` (static files) | Works in Chrome/Edge/Firefox and on Chromebooks with nothing to install. It's single-threaded, so it works on plain static hosting (GitHub Pages, itch.io). |
| Godot editor | this folder | Import `project.godot` in Godot 4.7.x and press F5. |

## Modes
- **Co-op: Droid Siege.** Capture command posts ALPHA, BRAVO and CHARLIE **in any order** by standing in their rings. A HUD bar shows capture progress, and the flag rises with it. If there are more droids than troopers in a ring, it is **CONTESTED** and the capture pauses. After all three, survive 2 minutes until the gunship arrives. If everyone is down, the mission fails.
- **Versus: Team Deathmatch.** Red vs Blue clones, auto-balanced. Friendly fire is off. First team to 15 kills wins, or whoever leads after 8 minutes. You respawn 5 s after dying at your team's spawn. Hold **Tab** for the scoreboard.
- **Versus: Free-for-All.** Everyone against everyone. First to 10 kills wins.
- The host picks the mode in the lobby. Map (**Geonosis Canyon Outpost**, **Felucia Jungle Ruins** or **Kamino Storm Platform**: hand-designed levels built from CC0 kits, see CREDITS.md) and difficulty (**Recruit / Veteran / Commando**) are picked on the main menu.

## Enemies (co-op)
- **B1 battle droids** are weak and numerous.
- **B2 super droids** are tanky.
- **Droidekas** roll in, then deploy a front shield. Flank them, hit them while they roll, or use grenades, which do double damage to shields.

Droids use navmesh pathfinding around cover.

## Controls
Choose **Controls** on the main menu or in the pause menu. The choice is saved.

**Mouse + Keyboard:** WASD move, mouse look, left click fire, right click aim, Shift sprint, Space jump, R reload, G grenade, hold E to revive, Tab scoreboard (Versus), Esc pause.

**Trackpad / Keyboard Only** (for laptops without a mouse): WASD move, **Arrow keys or J/L turn, I/K look up/down**, **F or Ctrl fire** (trackpad taps also fire), **Q or Alt toggle aim**, Shift sprint, Space jump, R reload, G grenade, E revive, Esc pause. Options:
- Keyboard turn speed slider.
- Light **aim assist** that pulls toward the nearest visible target near the crosshair.
- **Auto-fire** when the crosshair is on a target (off by default).

Credits come from kills, captured posts, and wins. Spend them in the **Armory** on damage, fire rate, magazine size, armor, and grenades. Progress is saved to `user://droid_siege_save.json`.

## Multiplayer: room codes (default)
Players install nothing but the game, with no port forwarding.
1. Anyone clicks **Multiplayer → Host Game (get a room code)**. The lobby shows a code like `K7QXM`.
2. Friends click **Multiplayer**, type the code, and click **Join with Code**. This works from the Windows exe, the web build, and the editor, so they can mix.
3. The host picks the mode and presses **Start**. Late joiners drop into a running match at the drop point or their team spawn.

Room codes go through a tiny **WebSocket relay** (`relay/relay.js`, Node.js). It only forwards packets; the host's game stays authoritative for enemies, objectives, and PvP damage. Because it's plain WebSocket over HTTPS (wss, port 443), it works on networks that block UDP and direct IPs, such as school Wi-Fi and Chromebooks.

### The relay is NOT deployed yet: the one-time setup
Until a relay is running and its address is set, room codes show "No relay server set". To host it for free on **Render.com** (free plan, no credit card at the time of writing):
1. Push this folder to a GitHub repo.
2. On Render, create a **New → Blueprint**, pick the repo, and it uses `render.yaml`. Alternatively, create a **New → Web Service** with root dir `relay`, build `npm install`, and start `node relay.js`.
3. You get an address like `https://droid-siege-relay.onrender.com`. The game address is the same with `wss://`, for example `wss://droid-siege-relay.onrender.com`.
4. Put it in `scripts/game.gd`: `const RELAY_URL := "wss://droid-siege-relay.onrender.com"`. Then re-export the Windows and Web builds (`Project → Export`, or the commands below). After that, everyone just uses codes. Without re-exporting, players can instead paste the address once under **Multiplayer → Advanced → Relay server address**, and it's saved.

Notes:
- Render's free services sleep after ~15 minutes idle. The first connection then takes about 30–60 s to wake the relay.
- Any Node host that supports WebSockets works the same way (Koyeb, Railway, a home PC, etc.). Set the `PORT` env var if needed.
- Some school filters block unknown domains like `*.onrender.com`. If joining fails at school, the relay domain may need to be allowed.
- Test the relay locally with `cd relay && npm install && node relay.js` (port 9080), then set the address to `ws://127.0.0.1:9080`.

### Advanced options (under Multiplayer → Advanced)
- **Direct IP (desktop only, ENet/UDP 7777):** "Host Direct (no code)" and "Join Direct IP". This works on the same Wi-Fi without the relay. Across the internet without a relay you'd need port forwarding or a VPN tool like Tailscale/ZeroTier. That's optional and not needed with room codes.
- **Dedicated server:** run `godot --headless --path . -- --server --port=8080`, or put it behind any host that supports WebSockets. Join with its `wss://` address. Any trooper in the lobby can press Start.

## Web build: publish it
The exported files are in `droid-siege-web/` (`index.html` plus `.js/.wasm/.pck`). The build is single-threaded and needs no special headers, so it works on any static host:
- **itch.io:** zip the *contents* of `droid-siege-web/` (index.html at the root of the zip). Create a new project, set Kind to **HTML**, upload, and tick "This file will be played in the browser". Viewport 1280×720.
- **GitHub Pages:** put the files in a repo (or a `docs/` folder), then go to Settings → Pages → deploy from branch. Open `https://<user>.github.io/<repo>/`.
- In the browser, direct IP hosting is not possible. Browsers use room codes, which need the relay deployed, or the dedicated server.

## Building
```
godot --headless --path . --export-release "Web" ../droid-siege-web/index.html
godot --headless --path . --export-release "Windows Desktop" ../droid-siege-windows/DroidSiege.exe
```
The Godot 4.7.2 export templates (web + windows) need to be installed.

## Tests
`GODOT=/path/to/godot ./run_tests.sh` runs everything headless:
- Menu boot.
- Full co-op wins on both maps with nav and kill-feed checks.
- **walkcap:** the player walks into a ring with real physics and input, and capture progress and flag height rise.
- **kbtest:** keyboard turning, F-fire, and aim assist.
- Fail and damage-indicator check.
- ENet host/join and late join.
- **Room-code relay:** host gets a code, the client joins by code, and the mission syncs.
- Dedicated WebSocket server plus client.
- **PvP:** the host kills the client twice through the authoritative path, the client respawns, the team score updates, and self-damage is ignored.

## Project layout
- `scripts/game.gd`: autoload. Handles save/settings, ENet/WebSocket/relay networking, RPCs, sounds, and tests.
- `scripts/relay_peer.gd`: MultiplayerPeerExtension that tunnels Godot multiplayer through the relay.
- `scripts/world.gd`: level, co-op mission, versus logic, enemy sync.
- `scripts/player.gd`, `enemy.gd`, `hud.gd`, `crosshair.gd`, `main_menu.gd`, `bolt.gd`, `grenade.gd`
- `relay/relay.js` + `render.yaml`: room-code relay server and its free-hosting blueprint.

## Maps
All three maps are hand-laid-out in `scripts/maps.gd` using CC0 model kits (`models/`, credits in `CREDITS.md`) and built at load time by `scripts/map_builder.gd`:
- **Geonosis Canyon Outpost**: two mesas split the canyon into west / centre / east lanes (ramps up to sandbag sniper nests), rock arches over the lanes, bunkers guarding ALPHA, a smoking droid factory in the NE where droids pour out; landmarks: comms tower (ALPHA), gun emplacement (BRAVO), crashed gunship (CHARLIE).
- **Felucia Jungle Ruins**: giant fungi forest, four glowing ponds, a two-tier temple overlook in the north, broken walls and a colonnade; landmarks: ancient gate (ALPHA), giant glowing fungus (BRAVO), statue (CHARLIE).
- **Kamino Storm Platform**: rain-lashed deck over the ocean, Tipoca domes on stilts, raised central gantry with ramps, four cargo-container yards, a parked gunship platform (BRAVO).

Each map defines team spawns (Versus), droid entry points (co-op enemy waves spawn from these), and high-ground checks.
Performance: repeated props are batched into MultiMeshInstance3D (≈17-23 draw batches per map), collision is primitive boxes/cylinders, omni lights have no shadows and fade at 60 m, the sun uses 2-split shadows to 70 m, big solids carry box occluders.
`--test=mapcheck0/1/2` verifies the navmesh bakes and every post is reachable from the LZ, both team spawns, every droid entry point and the high ground.

## Weapons, enemies, graphics (latest)
- **Mech (AT-RT walker):** parked beside the drop point. Walk up and Press E to enter, E again to exit. Steers like on foot (mouse or arrows/J L), W/S drive, Shift faster, fire = heavy cannon (3x damage, no reload), takes 35% damage, no jump/grenades; chase cam. Ejects you if you go down. Enter/exit and pilot pose are synced in multiplayer.
- **Modes:** Co-op Droid Siege, Co-op Horde Survival (4 min hold-out, also solo), Co-op Hold the Line (take and hold one post, also solo), Versus Team Deathmatch (1v1-2v2), Versus Free-for-All, Versus King of the Hill (first to 60), Versus Capture the Flag (first to 3). Solo modes are picked next to the map on the main menu; lobby hosts pick any mode.
- **v1.2:** LAAT/i gunship extraction (flies in, door gunners cover the squad, board at the LZ, lift-off cinematic), flowing lava rivers and lava falls on Mustafar, enterable two-room buildings on every map, more detailed vehicles, and a big performance pass for low-end laptops (merged droid/vehicle/level meshes, no shadows or dynamic lights on Low, DPI-aware render scale with dynamic resolution, off-screen characters skipped).
- **Movement:** snappier accel/stop, heavier fall, coyote time + jump buffering, tap jump for a short hop.
- **View:** V toggles first person (saved). **Extraction:** when the timer ends the gunship lands at the LZ; everyone still standing must board (stand on the pad) within 30 s.
- **Weapons:** slot 1 DC-15A rifle, slot 2 DP-23 scatter blaster (8 pellets, 6-shell mag). Switch with **1 / 2**, the **mouse wheel**, or **X / C** (keyboard mode).
- **OOM Commander** (yellow droid, from wave 2): droids within 12 m of it fire 43% faster and hit 25% harder. Kill it first.
- **Characters:** animated CC0 Quaternius models (clone = soldier, B1/commander = robot, B2 = mech), team-tinted in Versus, animations synced.
- **Graphics setting** (Options → Graphics: Auto/Low/Medium/High). Auto = Low on web and integrated GPUs (Surface Pro 9), High on NVIDIA/discrete. Low: 70% render scale, 1-split shadows to 35 m, no glow/MSAA, 150 rain drops, small props culled at 45 m, no droid shadows, far animation LOD.
