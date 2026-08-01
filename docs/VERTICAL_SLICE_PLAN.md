# Vertical Slice Implementation Plan

**Scope:** The 10–15 minute playable chapter defined in `ADR-0002`.
**Standard:** Production quality. This is one finished chapter, not a tech demo.
**Non-goals:** Future acts, additional companions, extra progression systems, multiplayer.

---

## 1. Baseline — What Already Exists

Audited 2026-08-01. The project boots cleanly (`Boot → TavernHub`, no script errors).

### Reusable as-is
- `Hitbox` / `Hurtbox` / `DamageEvent` — clean, typed, signal-driven damage pipeline
- `PlayerStats` — Health / Breath / Resonance with regen and decay
- `CombatBuffer` — timestamped input ring with data-driven combo patterns
- `SaveService` — versioned JSON persistence
- `ProgressionManager` — mission stat tracking and XP

### Reusable with extension
- `PlayerController` / `PlayerCameraRig` / `PlayerStateMachine` — movement, spring-arm camera, dodge
- `StrikeController` / `SingController` — active-frame attacks, Resonance-scaled cone blast
- `ToneDeafAI` — NavAgent pathing, obstacle feelers, flocking separation, leash/memory.
  **The best code in the repo.** Its steering logic becomes a shared component for the
  whole enemy roster rather than being copy-pasted.
- `EnemyBase` — health, knockback, knockdown, hit reactions, death events
- `IroncladWardenAI` — outside the ADR roster, so it stops being spawned, but its
  armour/poise system is harvested for the Bone Bell Ringer. File retained, not deleted.

### Does not exist
Audio (entirely — `AudioManager` is three `print()` calls), lock-on, mini-map, fog of war,
compass, quest system, Encore meter, Sir Brass, cinematics, the cemetery level, Funeral
Altars, four of the five enemies, the Choirmaster, Inn NPCs, dialogue, the Encore
performance, run-state save/load, character models, animation, pause menu, gamepad support.

### Known defect
`deep_raycast_3d.gdextension` declares its libraries at `res://addons/deep_raycast_3d/`
but the DLLs sit at the project root, so the extension fails to load on every launch.
Nothing references it. Fixed in Phase 1.

---

## 2. Architecture

The brief requires combat, AI, UI, music, companions, cinematics and quests to stay
decoupled. The mechanism is a single global signal hub plus per-domain directors that
subscribe to it. **No gameplay system holds a direct reference to another gameplay
system.** UI, music and quests are pure observers.

```
                         ┌──────────────┐
     Combat ────emit────►│              │────►  MusicDirector   (layers, crossfades)
     Player ────emit────►│   EventBus   │────►  QuestDirector   (objectives, gates)
     Enemies ───emit────►│  (autoload)  │────►  HUD / Minimap   (display only)
     World ─────emit────►│              │────►  AudioManager    (SFX)
                         └──────────────┘
```

### Autoloads

| Autoload | Status | Responsibility |
|---|---|---|
| `EventBus` | **new** | Typed global signals. The single decoupling seam. No logic, no state. |
| `GameManager` | extend | Demo chapter state. Input registration moves out to `project.godot`. |
| `MusicDirector` | **new** | Owns the four combat stems, ambient bed, boss and tavern tracks. Subscribes to `EventBus`. Knows nothing about combat. |
| `AudioManager` | rewrite | Pooled 3D/2D SFX playback, bus routing. Currently a stub. |
| `QuestDirector` | **new** | Objective graph, completion gates, progress signals. Drives the demo's flow. |
| `SceneLoader` | extend | Fade transitions, spawn-point handoff. |
| `UIRoot` | **new** | Host for UI that must exist in every scene — pause menu now, dialogue box and objective toasts later. Prevents each global UI element becoming its own autoload. |
| `SaveService` | extend | Adds a run-state slot alongside existing progression. |
| `ProgressionManager` | keep | XP and mission stats. |
| `FirebaseConfig` / `CloudSyncService` | untouched | Existing offline-first cloud sync. Out of scope. |

Cinematics are deliberately **not** an autoload — a `CinematicPlayer` scene is instanced
by the level that needs it, driven by `AnimationPlayer` plus a `CinematicSequence`
resource. It belongs in the scene tree, not in global state.

### Scene layout

```
scenes/
├─ boot/            Boot, MainMenu
├─ player/          Player, PlayerCameraRig, CharacterVisual
├─ companions/      SirBrass
├─ enemies/         ToneDeaf, GraveCrawler, HollowChoir, BoneBellRinger, Choirmaster
├─ levels/
│  ├─ InnHub/       InnHub + NPCs
│  └─ ChurchGraveyard/   Entrance, Crypts, Graveyard, Mausoleum, ChurchCourtyard
├─ world/           FuneralAltar, ChurchBell, Torch, LoreCollectible
├─ ui/              HUD, Minimap, ObjectiveTracker, PauseMenu, DialogueBox, EncoreResults
├─ cinematics/      CinematicPlayer + five sequences
└─ vfx/             Spectral, impact, cleanse effects
```

### Data-driven content

Per `CONTRIBUTING.md` ("avoid hard-coding stats inside scene scripts"), these become
`Resource` files under `resources/`:
`EnemyStats`, `ComboDefinition`, `QuestObjective`, `DialogueLine`, `MusicLayerSet`,
`CinematicSequence`.

### Asset swap seam

Every character gets a `CharacterVisual` child node holding the mesh, skeleton and
`AnimationTree`, exposing a fixed animation API (`play_locomotion`, `play_attack`,
`play_hit`, `play_death`). Gameplay code only ever calls that API. Replacing a
placeholder mesh with a final rigged model is then a scene-file change that touches
no gameplay script.

---

## 3. Enemy Roster

Only the five enemies in `ADR-0002`. All extend `EnemyBase` and share the steering
component extracted from `ToneDeafAI`.

| Enemy | Role | Key mechanic | Placeholder mesh |
|---|---|---|---|
| **Tone Deaf** | Basic undead | Teaches combos. Slow, telegraphed, forgiving. | Kenney character + zombie skin |
| **Grave Crawlers** | Fast swarm | Low HP, high speed, leap attack. Bursts from graves. Teaches crowd control. | Quaternius Skeleton, scaled down |
| **Hollow Choir** | Support | Channels a buff on nearby undead. **Must be interrupted** — Sing breaks the channel. Teaches target prioritisation. | Quaternius Skeleton + robe |
| **Bone Bell Ringer** | Heavy | Slow shockwave attacks, poise armour. Teaches stagger and spacing. Reuses harvested Warden armour code. | Quaternius Skeleton, scaled up |
| **The Choirmaster** | Mini boss | Three phases: conducts the choir, rhythm-based attacks with musical tells, summons adds. Sir Brass assists in phase 3. | Quaternius Skeleton, large, robed |

---

## 4. Level — The Church Graveyard

Five interconnected regions per `ADR-0002`, with multiple routes, loops and shortcuts.
The church is visible from everywhere as the landmark.

```
        ┌─────────────────┐
        │ Church Courtyard│◄── Altar 4 · Bell · Boss arena
        └────┬───────┬────┘
             │       │
     ┌───────┴──┐ ┌──┴────────┐
     │Mausoleum │ │  Crypts   │
     │ Altar 3  │ │  Altar 1  │
     └───────┬──┘ └──┬────────┘
             │       │
        ┌────┴───────┴────┐
        │    Graveyard    │◄── Altar 2 · central hub, loops to all
        └────────┬────────┘
                 │
           ┌─────┴─────┐
           │ Entrance  │◄── safe, no altar, tutorial beat
           └───────────┘
```

Four Funeral Altars. Each is guarded by an enemy group; clearing the group allows the
altar to be cleansed. Cleansing all four rings the church bell, the choir echoes, Sir
Brass comments, and The Choirmaster appears. Dead ends hold lore collectibles.

**Visual target:** dark gothic, heavy fog, moonlight, warm torch pools, blue spectral
accents. Stylised low-poly, large readable silhouettes, no realism.

**Built from:** Kenney Graveyard Kit (graves, coffins, fences, crypts), Ultimate Modular
Ruins Pack (gothic arches, broken walls, dead trees, torches, statues), Quaternius
Medieval Village MegaKit (church shell — `Roof_Tower_RoundTiles` gives the bell tower),
Kenney Nature Kit (ground, rocks, paths).

Navigation uses a **baked** `NavigationRegion3D`, replacing the runtime grid navmesh in
`PrototypeArena.gd`, which cannot represent this geometry.

---

## 5. Phases

Each phase ends in a state that runs and can be played. Every phase adds its manual
tests to `docs/TEST_PLAN.md`.

### Phase 1 — Foundation
Proper `InputMap` in `project.godot` for keyboard/mouse **and gamepad** (replacing
`GameManager`'s runtime registration, which cannot be rebound and does not survive
export cleanly). `EventBus`. Audio bus layout. `AudioManager` rewritten with pooled
playback. `SceneLoader` fade transitions. Pause menu with settings and rebinding. Fix
the `gdextension` path defect.
**Done when:** the game pauses, transitions cleanly, plays a test sound, and is fully
playable on a controller.

### Phase 2 — Combat Feel
`LockOnController` with target acquisition, switching and camera integration. Combo
chains extended and driven by animation rather than tweens. Dodge tuning, dodge-cancel,
i-frame windows. Hitstop, camera shake, impact VFX, hit-flash. `CharacterVisual` +
`AnimationTree` with the Kenney placeholder rig.
**Done when:** a fight against three Tone Deaf feels good with no other systems present.

### Phase 3 — Enemy Roster
Steering extracted to a shared component. `EnemyStats` resources. Grave Crawlers,
Hollow Choir, Bone Bell Ringer implemented. Tone Deaf retuned. Group spawning and
encounter definitions.
**Done when:** a mixed group of all four demands different tactics.

### Phase 4 — Encore, Companion, Music
`EncoreMeter` on the player, fed from `EventBus` combat events. `MusicDirector` with the
four-stem layered system, bar-quantised layer reveals, ambient/combat crossfade. Sir
Brass: summon → trumpet attack → dismiss, no permanent follower.
**Done when:** building Encore audibly adds instruments and summoning Sir Brass is a
spectacle. *Depends on stems from `AUDIO_SPEC.md` — built and testable against silent
placeholders until they arrive.*

### Phase 5 — The Cemetery
All five regions built and dressed. Baked navmesh. Lighting, fog, torch pools, spectral
VFX. Funeral Altars with cleanse interaction. Church bell trigger. Lore collectibles.
**Done when:** the level is explorable, atmospheric, and reads as a real place.

### Phase 6 — Navigation & Quests
`QuestDirector` with the objective graph. Objective tracker UI. Mini-map with fog of war
that clears through exploration and clearing groups. Compass. Church pinned as a
permanent landmark.
**Done when:** a player who has never seen the level can navigate it without being told
where to go.

### Phase 7 — Boss & Cinematics
The Choirmaster: three phases, rhythm-based attacks with readable musical tells, choir
summoning, Sir Brass assist. `CinematicPlayer` and the five required sequences —
opening, boss introduction, boss defeat, return to tavern, encore.
**Done when:** the mission has a real climax and the cinematics carry the story without
exposition dumps.

### Phase 8 — Inn Hub, Encore & Ship
Inn rebuilt with Tavern Keeper, Merchant, Blacksmith, Quest Giver and a wandering Sir
Brass. Dialogue system. Mission acceptance. The Encore performance sequence. Run-state
save/load (altar progress, region, Encore state) so the demo survives a quit. Full
playthrough passes, balance, bug fixing, Windows export.
**Done when:** the definition of done is met — a player completes the demo start to
finish with no developer intervention.

---

## 6. Assets Needed From You

### Required now
**Kenney Graveyard Kit** — [kenney.nl/assets/graveyard-kit](https://kenney.nl/assets/graveyard-kit)
(also on [itch.io](https://kenney-assets.itch.io/graveyard-kit)). 90 models, CC0, free.
Download the **GLTF** version and place it at `godot/assets/environment/graveyard-kit/`.
This is the only environment asset missing — graves, coffins, crypts, fences and props.
Needed for Phase 5.

### Required before Phase 4 completes
**Music stems and SFX** per `docs/AUDIO_SPEC.md`. The system is built against that
contract and runs with silent placeholders, so this does not block development — but
the demo cannot ship without it, since layered music is a core pillar.

### Not needed
No church model — built modularly from the MegaKit you already own. No character models
— placeholders with a clean swap seam, per your decision.

### Nice to have, not blocking
A rigged Riff Wilde `.glb` matching the concept sheets (humanoid rig, Y-up, ~2 m,
idle/walk/run/attack/dodge/hit/death). He is on screen for the entire demo, so he does
more for the visual target than anything else. Ask and I will write the exact rig spec.

Every imported asset gets a row in `docs/ASSET_REGISTER.md` before import, per
`AGENT_RULES.md`.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Music stems arrive late or don't stack | Strict contract in `AUDIO_SPEC.md`; system built and testable against silent placeholders from Phase 4 |
| Placeholder art undercuts "finished chapter" feel | Lighting, fog, VFX and animation carry the visual target; swap seam keeps model upgrades cheap |
| Boss fight is the highest-risk system and lands late | Choirmaster reuses proven `EnemyBase` and steering; phases built incrementally |
| Scope creep | `ADR-0002` is the boundary. Anything not in it is refused or logged for later. |
| Runtime navmesh cannot express the cemetery | Replaced with a baked `NavigationRegion3D` in Phase 5 |

---

*Created 2026-08-01. Supersedes the Phase 1–8 structure in `build_plan.md`, which covered
the earlier prototype milestones (now complete).*
