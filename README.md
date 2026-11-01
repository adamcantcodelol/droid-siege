# Droid Siege

A free, co-op (1-4 players) third-person clone trooper shooter made in **Godot 4** (built and tested with Godot 4.7.2). All art is made from primitive meshes and CSG, and all sounds are generated tones, so there are no external assets.

## The mission
1. Your squad drops at the landing zone.
2. Capture **Command Posts ALPHA, BRAVO and CHARLIE** in order by standing inside the glowing ring. If more droids than troopers are in the ring, the capture stalls.
3. After all three are captured, **survive for 2 minutes** until the gunship arrives.
4. If every trooper is downed at the same time, the mission fails.

You earn credits for each droid destroyed, +150 per post, and +500 for extraction (you keep half if the mission fails). Spend them in the **Armory** on Blaster Damage, Fire Rate, Power Cell (magazine size), Armor Plating, and Thermal Detonators. Progress is saved to `user://droid_siege_save.json`.

### Enemies
- **B1 Battle Droid:** weak and numerous, and strafes while shooting.
- **B2 Super Droid:** slow, tanky, and hits hard.
- **Droideka:** rolls in fast as a ball, which is the time to shoot it. Once it deploys, its shield blocks every shot from the front. Flank it and shoot from behind, or break the shield. Grenades do double damage to the shield.

## Open and play
1. Install Godot 4.x (standard version, not .NET) from https://godotengine.org. It's free.
2. Open Godot, click **Import**, and select `project.godot` in this folder.
3. Press **F5** (Play).

## Controls
| Action | Key |
|---|---|
| Move | WASD / arrows |
| Sprint | Shift |
| Jump | Space |
| Look | Mouse |
| Fire | Left mouse |
| Aim down sights (zoom, more accurate) | Right mouse |
| Reload | R |
| Throw grenade | G |
| Revive downed squadmate | Hold E near them (2.5 s) |
| Pause / mouse sensitivity / leave | Esc |

A downed trooper bleeds out after 30 seconds. Health regenerates after 5 seconds without taking damage.

## Multiplayer (host and join by IP)
- **Host:** Main menu, then Multiplayer, then **Host Game** (default UDP port 7777). The lobby shows your IP addresses. When your squad is in, press **Start Mission**.
- **Join:** Main menu, then Multiplayer, enter the host's IP, then **Join Game**.
- **Same Wi-Fi/LAN:** use the host's LAN IP (for example 192.168.x.x). The host may need to allow Godot through the firewall (UDP 7777).
- **Over the internet, for free, with Tailscale:** install Tailscale (https://tailscale.com, free personal plan) on every player's PC and sign in to the same tailnet, or have the host share their machine with friends. Then join the host's **100.x.y.z** Tailscale IP. You don't need port forwarding. ZeroTier works the same way.
- Everyone needs the same version of the project folder.
- The host runs the enemy AI and objectives (server-authoritative). Each player simulates their own movement. Players can't join a mission that's already running; they join from the lobby.

## Headless tests
`GODOT=/path/to/godot ./run_tests.sh` imports the project and runs the following:
- `--test=menu`: boots the main menu.
- `--test=smoke`: runs a full singleplayer mission with an autopilot (all 3 captures, extraction, win, credits saved).
- `--test=smokefail`: checks that being downed fails the mission.
- `--test=server` + `--test=client`: hosts on localhost:7778, connects a client, starts the mission, and checks that enemy and player sync and client damage requests work.

## Project layout
- `scripts/game.gd`: autoload. Handles save/upgrades, ENet networking, the RPC relay, generated sounds, and the test harness.
- `scripts/world.gd`: builds the level procedurally and runs the mission, waves, and enemy sync.
- `scripts/player.gd`, `enemy.gd`, `hud.gd`, `main_menu.gd`, `bolt.gd`, `grenade.gd`
