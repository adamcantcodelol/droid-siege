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
- The host picks the mode in the lobby. Map (**Geonosis Outpost** or **Felucia Night Raid**) and difficulty (**Recruit / Veteran / Commando**) are picked on the main menu.

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
