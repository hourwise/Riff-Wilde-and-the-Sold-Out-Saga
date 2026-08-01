# Test Plan

Manual and automated tests for the vertical slice. Update as features are added.

---

## Phase 0: Project Setup

| Test | Type | Status | Description |
|---|---|---|---|
| Godot imports cleanly | Manual | ✅ | Open project in Godot Editor; no import warnings |
| .gitignore works | Manual | ✅ | `git status` ignores `.godot/`, exports, local files |
| Input map works | Manual | ✅ | `Input.is_action_just_pressed("strike")` prints to console |
| Autoloads instantiate | Auto | ✅ | All four autoloads print init messages on startup |

## Phase 1: Player Movement

| Test | Type | Status | Description |
|---|---|---|---|
| State machine transitions | Manual | ✅ | Prints "State changed: Idle -> Move" on WASD |
| Camera rotates smoothly | Manual | ✅ | Mouse-look rotates camera without jitter |
| Camera-relative movement | Manual | ✅ | W always moves away from camera view |
| Dodge works | Manual | ✅ | Shift performs swift dodge; respects cooldown |
| Arena geometry solid | Manual | ✅ | No clipping through walls/floors; no falling out of bounds |

## Phase 2: Strike Combat

| Test | Type | Status | Description |
|---|---|---|---|
| Hitbox/Hurtbox overlap | Auto | ✅ | Mock overlap emits signal with correct damage params |
| Strike hitbox visible in debug | Manual | ✅ | Red hitbox area appears only during swing frames |
| Dummy reacts to strike | Manual | ✅ | Dummy logs health reduction on every hit |

## Phase 3: Sing Combat & Stats

| Test | Type | Status | Description |
|---|---|---|---|
| HUD bars update | Manual | ✅ | HP, Breath, Resonance bars fill/empty accurately |
| Sing blast pushes dummy | Manual | ✅ | Sing knockback > Strike knockback |
| Sing fails on empty Breath | Manual | ✅ | Attack blocked when Breath depleted |
| Resonance scales Sing | Manual | ✅ | Higher Resonance = greater knockback/damage |

## Phase 4: Combo System

| Test | Type | Status | Description |
|---|---|---|---|
| Input buffer logs/times out | Manual | ✅ | Inputs register and clear after combo window |
| Intro Combo detected | Auto | ✅ | Strike → Strike → Sing triggers "Combo Matched: Intro Combo" |
| Crescendo Finisher hits all | Manual | ✅ | 360° blast damages all dummies in range |

## Phase 5: Enemy AI

| Test | Type | Status | Description |
|---|---|---|---|
| Tone Deaf chase & attack | Manual | ✅ | Enemies navigate, wind up, damage player, die |
| Encounter cleared notification | Manual | ✅ | Clearing pack shows notification, doesn't freeze controls |
| Warden blocks Strikes | Auto | ✅ | Strike doesn't damage health while armor active |
| Sing breaks Warden armor | Auto | ✅ | High-power Sing breaks armor; Strike damages after |
| Status bars render correctly | Manual | ✅ | HP bars follow enemies; Warden armor bar hides on break |

## Phase 6: Tavern & Game Loop

| Test | Type | Status | Description |
|---|---|---|---|
| Quest Board interact prompt | Manual | ✅ | "[E] Interact" appears near board; E opens mission panel |
| Mission launch switches state | Auto | ✅ | Tavern → Mission loads PrototypeArena |
| Area completion triggers extraction | Auto | ✅ | Scouting + all enemies → extraction → return to Tavern |
| Encore results display | Auto | ✅ | XP awarded; Tavern results panel shows after extraction |

## Phase 7: Persistence

| Test | Type | Status | Description |
|---|---|---|---|
| Save persists XP/skills | Auto | ✅ | Reload restores XP and unlocked skills |
| Session survives restart | Manual | ⬜ | Earn XP, close app, reopen — XP matches |

## Phase 7.2: Firebase Cloud Sync

| Test | Type | Status | Description |
|---|---|---|---|
| Connectivity check | Auto | ⬜ | Unreachable server prints warning, game proceeds offline |
| Cloud sync uploads scores | Manual | ⬜ | Complete mission, verify document updated in Firebase Console |

---

# Vertical Slice (ADR-0002)

## VS Phase 1: Foundation

Automated: `godot --headless --path godot --script res://tools/smoke_test_phase1.gd`
(75 checks — input bindings, audio buses, autoloads, pause suspension, settings round-trip).

| Test | Type | Status | Description |
|---|---|---|---|
| Input actions defined in project.godot | Auto | ✅ | All 17 actions exist with bindings; none registered at runtime |
| Bindings match any device | Auto | ✅ | Every event has `device = -1`; a non-`-1` device silently never fires |
| Audio bus tree present | Auto | ✅ | 9 buses; MusicCombat/MusicAmbient/MusicBoss route into Music |
| Autoload order correct | Auto | ✅ | EventBus → SaveService → GameManager → AudioManager → … |
| EventBus holds no state | Auto | ✅ | Guards the decoupling contract — no variables may be declared on it |
| Pause suspends the tree | Auto | ✅ | Opening the pause menu sets `get_tree().paused` |
| Overlapping suspends are safe | Auto | ✅ | Closing the menu while a cinematic holds suspension does not resume play |
| Settings persist | Auto | ✅ | Write → reload → value survives in `user://settings.cfg` |
| Clean startup | Auto | ✅ | No errors, warnings or leaked instances on boot and scene change |
| Gamepad movement | Manual | ⬜ | Left stick moves camera-relative; right stick looks; deadzones feel right |
| Gamepad combat | Manual | ⬜ | X strikes, Y sings, B dodges, A interacts, Start pauses |
| Pause key toggles menu | Manual | ⬜ | Esc/Start opens and closes; gameplay freezes and resumes |
| Settings apply live | Manual | ⬜ | Volume sliders audibly change while open; sensitivity applies on resume |
| Mouse capture restored | Manual | ⬜ | Cursor is free in the menu and recaptured on resume, not in the boot screen |
| Scene fade transition | Manual | ⬜ | Boot → Inn fades to black and back; no frozen or flashing frame |
| Return to Inn from pause | Manual | ⬜ | "Return to the Inn" unpauses and loads the hub correctly |

## VS Phase 2: Combat Feel

Automated: `godot --headless --path godot --script res://tools/smoke_test_phase2.gd`
(28 checks — chain timing validity, dodge i-frame window, hitstop restore, lock-on lifecycle).

| Test | Type | Status | Description |
|---|---|---|---|
| Chain buffer windows reachable | Auto | ✅ | Each step's `buffer_open` is inside its duration, or the chain degrades to single hits |
| Chain has wind-up and active frames | Auto | ✅ | Every step is readable and can connect |
| Chain damage escalates | Auto | ✅ | Finisher hits hardest |
| Dodge i-frames are a window | Auto | ✅ | Vulnerable start-up and recovery; i-frames strictly inside the dodge |
| Hitstop restores time scale | Auto | ✅ | `Engine.time_scale` returns to 1.0 after the freeze |
| Lock-on acquires and releases | Auto | ✅ | Toggles on/off and announces both on EventBus |
| Lock-on drops dead targets | Auto | ✅ | Camera never keeps framing a corpse |
| Camera stays third person | Auto | ✅ | Camera is not a direct spring-arm child and stays behind the player, at rest and while shaking |
| Locked movement is target-relative | Auto | ✅ | With the camera turned 90° away, forward still approaches the target and strafe circles at steady range |
| Camera faces the locked target | Auto | ✅ | Rig forward points at the target, not 180° away at its back |
| View steerable while locked | Auto | ✅ | Look input swings the view within a clamped offset, then recentres on the target |
| Locked dodge escapes | Auto | ✅ | Dodging with no input backsteps away from the target |
| Facing survives a rotated body | Auto | ✅ | With the player body at 45° (as the Inn places it), mesh faces travel and target, and the camera still aims at the target. Verified to fail without the fix (dot 0.707 = 45° off) |
| Combo chain flows | Manual | ⬜ | Three strikes chain smoothly; inputs during a swing are not eaten |
| Dodge cancels attack | Manual | ⬜ | Dodging during recovery interrupts the swing immediately |
| Hitstop feels weighty | Manual | ⬜ | Finisher freezes noticeably harder than a light hit; no stalling on rapid hits |
| Camera shake scales | Manual | ⬜ | Light hits subtle, finisher strong, taking damage strongest |
| Hit flash reads | Manual | ⬜ | Enemies flash white on every hit, visible at distance |
| Lock-on framing | Manual | ⬜ | Camera holds the target; Riff strafes and stays facing it |
| Locking on does not lurch | Manual | ⬜ | Locking on while running forward does not redirect Riff at the enemy; W/S approach and retreat, A/D circle |
| Locked view remains free | Manual | ⬜ | Mouse/right stick can glance up to 55° aside to check flanks, then eases back onto the target |
| Circling under pressure | Manual | ⬜ | A/D circles a locked enemy fast enough to avoid being surrounded; other enemies stay visible |
| Lock-on target switching | Manual | ⬜ | Right-stick or mouse flick switches to the enemy on that side only |
| Locked backstep | Manual | ⬜ | Dodging with no input while locked steps away from the target |
| Reticle tracks | Manual | ⬜ | Reticle sits on the target, pops in on acquire, hides when behind camera |

## VS Phase 3: Enemy Roster

Automated: `godot --headless --path godot --script res://tools/smoke_test_phase3.gd`
(53 checks — stats sanity, scene structure, and each enemy's defining mechanic).

| Test | Type | Status | Description |
|---|---|---|---|
| Stats resources sane | Auto | ✅ | Every enemy has health, a non-zero telegraph, and leashes further than it detects |
| Scene structure complete | Auto | ✅ | All four have Hurtbox, steering, nav agent, lock-on anchor and stats assigned |
| Choir channel interrupts | Auto | ✅ | Any damage cancels the song — the counterplay exists |
| Choir song empowers allies | Auto | ✅ | A completed channel raises nearby enemies' damage multiplier |
| Bell Ringer shrugs off chip | Auto | ✅ | Damage below the poise threshold does not stagger |
| Bell Ringer poise breaks | Auto | ✅ | Committing past the threshold staggers it |
| Crawler leaps at mid-range | Auto | ✅ | Leaps to close 3–6.5m, verified with the player pinned |
| Crawler does not leap point blank | Auto | ✅ | Swipes instead of jumping over the player |
| Enemies are animation-driven | Auto | ✅ | Every enemy resolves a real AnimationPlayer from its model |
| Animation clip names resolve | Auto | ✅ | No configured clip is missing — a misspelled name leaves the enemy sliding in a T-pose, silently |
| Models sit on the ground | Manual | ⬜ | No floating or sunken enemies; scale matches the collision capsule |
| Animations read at speed | Manual | ⬜ | Run cycles match movement speed without foot sliding; attacks land with the telegraph |
| Mixed encounter reads | Manual | ⬜ | Crawlers, Choir and Ringer together demand different answers, not the same one |
| Silhouettes distinguishable | Manual | ⬜ | Low/wide crawler, tall/thin choir, bulky ringer readable at distance and in fog |
| Telegraphs readable | Manual | ⬜ | Each wind-up flash is visible in time to react; Ringer's is longest |
| Choir is worth prioritising | Manual | ⬜ | Ignoring the Choir noticeably raises incoming damage; silencing it is felt |
| Shockwave punishes standing still | Manual | ⬜ | Ringer's arc can be sidestepped or escaped behind |

## Phase 8: Polish & Export

| Test | Type | Status | Description |
|---|---|---|---|
| Audio spectrum drives VFX | Manual | ⬜ | Sing/lute hits cause lights/meshes to pulse with audio |
| Windows export runs standalone | Manual | ⬜ | .exe runs on machine without Godot installed |

---

*Last updated: 2026-07-04*
