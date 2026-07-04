# Riff Wilde and the Sold-Out Saga — Source of Truth Build Plan

**Game title:** Riff Wilde and the Sold-Out Saga  
**Document purpose:** This is the master planning file for the game. Treat this as the source of truth for the codebase, tech stack, development order, agent prompts, services, security setup, and scope control.

---

## 0. One-Sentence Vision

A single-player, third-person arcade-action fantasy RPG where Riff Wilde, a swaggering warrior-bard, uses a massive lute-bludgeon, sonic telekinesis, rhythm-inspired combos, and darkly comic tavern performances to smash through a gothic fantasy world.

---

## 0.1 Protagonist Identity

**Player character:** Riff Wilde.

Riff introduces himself with self-appointed stage titles at various points in the game. Canon title pool:

- The Maestro of Mayhem
- The Sultan of Smash
- The Heartbreaker of Kingdom TBD

The kingdom name is intentionally unset until the world map and tavern hub naming are locked.

---

## 1. Scope Decision

### Final Recommended Starting Scope

Do **not** start with multiplayer, open world, MMO systems, Steam Workshop, AI-generated music pipelines, or large RPG progression.

The first version should be a **single-player third-person vertical slice**:

- One playable character.
- One small gothic forest / ruined village combat arena.
- One simple tavern hub scene.
- One enemy type.
- One elite enemy or mini-boss.
- Basic movement, camera, melee attack, vocal attack, dodge, health, breath, resonance.
- One complete mission loop: tavern → mission → combat result → tavern reward.
- No save system at first except local settings and debug unlocks.
- No online services in the first prototype.

### Why This Scope

The uploaded GDD has a strong identity: a warrior-bard, two-button Strike/Sing combat, Verse-Chorus combo logic, tavern progression, dark fantasy satire, and sonic physics. The risk is not the idea. The risk is trying to build the full game before the core movement and combat are fun.

The first milestone must answer one question:

> Is it fun to move, swing the lute, shout enemies across the arena, and chain Strike/Sing combos?

If the answer is yes, everything else can grow from there.

---

## 2. Product Shape

### Phase 1 Product

**Format:** Single-player PC/browser prototype.  
**Engine:** Godot 4.x.  
**Visual style:** Low-poly / stylised cartoony gothic fantasy.  
**Tone:** Brutal Legend meets gothic fantasy, with comic self-awareness.  
**Target player:** Indie action RPG fans who enjoy stylish combat, humour, fantasy, and music-themed mechanics.

### Target Platforms by Stage

| Stage | Platform | Notes |
|---|---|---|
| Prototype | Windows desktop export | Easiest to test and debug. |
| Early public demo | Itch.io Windows build | Good for testers and feedback. |
| Browser experiment | Godot Web export | Possible, but must keep visuals and rendering simple. Godot 4 web exports use WebGL 2.0 with the Compatibility renderer. |
| Commercial release | Steam + Itch.io | Steam requires Steamworks setup and a Steam Direct app fee. |
| Future | Console | Ignore until the game proves itself. |

---

## 3. Tech Stack

### Core Stack

| Area | Choice | Reason |
|---|---|---|
| Game engine | Godot 4.x | Lightweight, open-source, fast iteration, strong indie fit. |
| Language | Strictly typed GDScript | Fastest development loop and readable for AI coding agents. |
| IDE | VS Code + Godot editor | VS Code for agent/code work, Godot editor for scenes/assets. |
| Version control | Git + GitHub | Required from day one. |
| Project management | GitHub Projects or GitHub Issues | Keep all work visible and traceable. |
| Asset format | `.glb` / `.gltf` for 3D models | Godot-friendly and common for low-poly assets. |
| Audio format | `.ogg` for music/SFX | Good compression and game-engine support. |
| Documentation | Markdown in `/docs` | Easy for AI agents and humans to update. |
| CI checks | GitHub Actions | Run formatting, linting, export checks later. |

### Development Dependencies

Install locally:

1. **Godot 4.x stable**.
2. **VS Code**.
3. **Git**.
4. **GitHub Desktop** if preferred.
5. **Blender** for asset conversion and light editing.
6. **Audacity** for simple audio editing.
7. **Cline / coding agent extension** if using agentic build workflow.
8. Optional: **Godot MCP Server** once the basic project exists.

---

## 4. Services to Sign Up To

### Must-Have from Day One

#### 1. GitHub

Use for:

- Private repo while prototyping.
- Issues and milestones.
- Pull requests, even if solo.
- Secret scanning, Dependabot, and project tracking.

Setup:

1. Create a GitHub repository named something like `acoustic-juggernaut`.
2. Start private.
3. Add a clear `README.md`.
4. Add `.gitignore` for Godot.
5. Enable branch protection once the first playable prototype exists.
6. Enable Dependabot alerts where available.
7. Use GitHub secret scanning/push protection where available. GitHub provides free secret scanning automatically for public repositories; private repository coverage depends on account/organisation features.

Security rules:

- Never commit API keys.
- Never commit `.env` files.
- Never commit paid asset source files unless the licence allows redistribution.
- Every asset needs a licence record in `docs/ASSET_REGISTER.md`.

#### 2. Itch.io

Use for:

- Private test page.
- Browser or downloadable prototype.
- Later public demo.

Setup:

1. Create creator account.
2. Create draft project.
3. Keep visibility private/restricted while testing.
4. Upload Windows build first.
5. Add browser build later only if performance is acceptable.

Notes:

- Itch.io lets creators upload projects without an upfront platform fee and uses open revenue sharing.
- It is ideal for early demos and testing before Steam.

#### 3. Trello, GitHub Projects, or Linear

Recommended: **GitHub Projects** to avoid spreading planning across too many tools.

Create columns:

- Backlog
- Ready
- In Progress
- Needs Testing
- Done
- Cut / Later

### Useful but Optional

#### 4. Snyk

Use for:

- Dependency scanning.
- Licence risk checking.
- Security habit-building.

This is more useful once the project contains build scripts, web tooling, plugins, or third-party packages. Snyk Open Source can scan for dependency vulnerabilities and licence risks.

#### 5. Steamworks

Do not sign up immediately unless you are preparing a public commercial release.

Use later for:

- Steam store page.
- Wishlists.
- Demo festivals.
- Achievements.
- Cloud saves.

Steam Direct requires a per-app fee, currently listed by Valve as $100 USD or equivalent.

#### 6. Suno / AI Music Tooling

Do not integrate into the game initially.

Use only for:

- Mood exploration.
- Trailer/demo background ideas.
- Placeholder tavern song concepts.

Important: confirm the commercial and redistribution rights before using any AI-generated music in a released game.

#### 7. Quaternius / Kenney / OpenGameArt / Itch Asset Packs

Use for:

- Placeholder characters.
- Enemies.
- Props.
- Environment pieces.

Every asset must be logged with:

- Asset name.
- Creator.
- URL.
- Licence.
- Whether modification is allowed.
- Whether commercial use is allowed.
- Whether redistribution in a public repo is allowed.

---

## 5. Security From the Start

### Repo Security Checklist

- [ ] Create private GitHub repo.
- [ ] Add `.gitignore` before first commit.
- [ ] Add `docs/ASSET_REGISTER.md` before importing any external assets.
- [ ] Add `docs/SECURITY.md`.
- [ ] Add `docs/CONTRIBUTING.md` even while solo.
- [ ] Do not store secrets in code.
- [ ] Do not add online accounts, payments, analytics, or telemetry in prototype.
- [ ] Enable GitHub 2FA.
- [ ] Enable secret scanning/push protection where available.
- [ ] Enable Dependabot alerts where available.
- [ ] Use pull requests for agent-generated work, even if reviewing your own PR.
- [ ] Keep all downloaded asset ZIP files outside the repo unless licence permits redistribution.

### Local Machine Security

- Use a password manager.
- Use unique passwords for GitHub, Itch, Steamworks, and AI tools.
- Enable 2FA everywhere.
- Keep commercial assets in a separate local folder outside the repo.
- Do not let coding agents read unrelated personal/business folders.
- Open the project folder only, not your full user directory, when using AI coding tools.

### Agent Safety Rules

Put this in `docs/AGENT_RULES.md`:

```md
# Agent Rules

1. Do not delete files unless explicitly instructed.
2. Do not rename public APIs, signals, scenes, or autoloads without updating all references.
3. Do not add third-party addons without approval.
4. Do not add online services, telemetry, payments, ads, or analytics without approval.
5. Do not commit secrets, tokens, passwords, or personal data.
6. Do not import assets unless licence information is added to docs/ASSET_REGISTER.md.
7. Prefer small, testable changes.
8. After every change, list files changed and explain how to test manually in Godot.
9. Maintain strictly typed GDScript.
10. Keep this vertical slice focused: movement, camera, combat, enemy AI, tavern loop.
```

---

## 6. Codebase Structure

Recommended Godot project layout:

```txt
acoustic-juggernaut/
├─ README.md
├─ LICENSE
├─ .gitignore
├─ docs/
│  ├─ SOURCE_OF_TRUTH.md
│  ├─ AGENT_RULES.md
│  ├─ ASSET_REGISTER.md
│  ├─ SECURITY.md
│  ├─ ROADMAP.md
│  ├─ TEST_PLAN.md
│  └─ PROMPTS.md
├─ godot/
│  ├─ project.godot
│  ├─ scenes/
│  │  ├─ boot/
│  │  │  └─ Boot.tscn
│  │  ├─ player/
│  │  │  ├─ Player.tscn
│  │  │  └─ PlayerCameraRig.tscn
│  │  ├─ enemies/
│  │  │  ├─ ToneDeaf.tscn
│  │  │  └─ MiniBoss.tscn
│  │  ├─ levels/
│  │  │  ├─ PrototypeArena.tscn
│  │  │  └─ TavernHub.tscn
│  │  ├─ ui/
│  │  │  ├─ HUD.tscn
│  │  │  └─ PauseMenu.tscn
│  │  └─ vfx/
│  ├─ scripts/
│  │  ├─ autoload/
│  │  │  ├─ GameManager.gd
│  │  │  ├─ AudioManager.gd
│  │  │  ├─ ProgressionManager.gd
│  │  │  └─ SceneLoader.gd
│  │  ├─ player/
│  │  │  ├─ PlayerController.gd
│  │  │  ├─ PlayerStateMachine.gd
│  │  │  ├─ PlayerStats.gd
│  │  │  ├─ CombatBuffer.gd
│  │  │  ├─ StrikeController.gd
│  │  │  ├─ SingController.gd
│  │  │  └─ VocalTelekinesis.gd
│  │  ├─ enemies/
│  │  │  ├─ EnemyBase.gd
│  │  │  ├─ EnemyStateMachine.gd
│  │  │  └─ ToneDeafAI.gd
│  │  ├─ combat/
│  │  │  ├─ Hitbox.gd
│  │  │  ├─ Hurtbox.gd
│  │  │  ├─ DamageEvent.gd
│  │  │  └─ StatusEffect.gd
│  │  ├─ interaction/
│  │  │  ├─ Interactable.gd
│  │  │  └─ TavernQuestBoard.gd
│  │  └─ ui/
│  │     └─ HUDController.gd
│  ├─ assets/
│  │  ├─ characters/
│  │  ├─ enemies/
│  │  ├─ environment/
│  │  ├─ audio/
│  │  ├─ vfx/
│  │  └─ ui/
│  ├─ resources/
│  │  ├─ abilities/
│  │  ├─ enemies/
│  │  ├─ quests/
│  │  └─ items/
│  └─ tests/
│     ├─ unit/
│     └─ manual/
└─ exports/
   └─ README.md
```

### Important Code Rules

- Use typed GDScript wherever possible.
- Use signals for decoupled combat events.
- Keep data in Resources where practical.
- Avoid hard-coded enemy stats inside scene scripts.
- Keep the player controller small; move combat, stats, telekinesis, camera, and UI into separate scripts.
- Do not add multiplayer architecture in Phase 1.
- Do not add database/backend in Phase 1.

---

## 7. Core Systems

### 7.1 Player Movement

Required:

- Third-person WASD movement.
- Camera-relative direction.
- Controller support later.
- Jump optional; dodge more important.
- Lock-on optional; soft camera targeting first.

Scripts:

- `PlayerController.gd`
- `PlayerCameraRig.gd`
- `PlayerStateMachine.gd`

Acceptance criteria:

- Player moves smoothly around arena.
- Camera follows without fighting the player.
- Character cannot clip through major level geometry.
- Player can dodge out of danger.

### 7.2 Combat

Core buttons:

- `Strike`: melee lute-bludgeon attack.
- `Sing`: vocal/sonic attack.
- `Dodge`: evade.
- `Interact`: tavern/quest objects.

Stats:

- Health.
- Breath.
- Resonance.
- Style multiplier later.

Minimum attacks:

1. Light Strike.
2. Heavy Strike or charged Strike.
3. Short Sing blast.
4. Hold Sing telekinetic lift/pull.
5. Strike → Strike → Sing combo.

Acceptance criteria:

- Strike damages enemies in a clear arc.
- Sing consumes Breath.
- Strike builds Resonance.
- Player can chain at least one combo.
- Combat feels readable before adding visual polish.

### 7.3 Combat Buffer

Purpose:

Track recent inputs and trigger named combo patterns.

Initial combos:

| Combo | Input | Effect |
|---|---|---|
| Intro Combo | Strike → Strike → Sing | Knockdown shout. |
| Bridge Combo | Hold Sing → Strike | Pull target/object then smash. |
| Crescendo Prototype | Strike → Sing → Strike | 360 shockwave. |

Implementation:

- Store recent input actions with timestamps.
- Clear buffer after timeout.
- Emit `combo_matched(combo_id)` signal.
- Combat system listens and triggers ability.

### 7.4 Enemy AI

First enemy: **The Tone Deaf**.

Behaviour:

- Idle patrol.
- Detect player by range.
- Move toward player.
- Attack in melee.
- Get knocked back.
- Die and emit XP/drop event.

Second enemy: **Ironclad Mini-Warden**.

Behaviour:

- Slower movement.
- Armour/poise.
- Requires Sing/Resonance to break armour.

### 7.5 Tavern Hub

Minimum viable tavern:

- Static hub scene.
- Quest board/interactable patron.
- Start mission button.
- End mission result panel.
- Spend XP placeholder.

Later:

- NPC dialogue.
- Dynamic performance cutscene.
- Crowd reaction.
- Tech tree.

### 7.6 Progression

Phase 1:

- XP earned from mission.
- Unlock one ability upgrade.
- No complex inventory.

Phase 2:

- String/Wind/Percussion trees.
- Cosmetics.
- Mission ratings.

---

## 8. Vertical Slice Milestones

### Milestone 0 — Project Setup

Deliverables:

- GitHub repo.
- Godot project.
- Folder structure.
- Source of truth docs.
- First empty scene boots.

Acceptance:

- Project opens cleanly in Godot.
- Repo has README, licence, security docs, asset register.

### Milestone 1 — Movement Playground

Deliverables:

- Player capsule/placeholder model.
- Third-person camera.
- Movement and dodge.
- Prototype arena.

Acceptance:

- Moving around feels decent for 2 minutes.
- No combat yet.

### Milestone 2 — Basic Strike Combat

Deliverables:

- Strike attack.
- Hitbox/hurtbox.
- One dummy enemy.
- Health/damage.

Acceptance:

- Player can kill dummy enemy with lute swings.

### Milestone 3 — Sing / Breath System

Deliverables:

- Sing projectile or cone blast.
- Breath meter.
- Knockback.
- Simple VFX placeholder.

Acceptance:

- Sing feels meaningfully different from Strike.

### Milestone 4 — Combo Buffer

Deliverables:

- Input buffer.
- At least one combo.
- HUD combo feedback.

Acceptance:

- Strike → Strike → Sing reliably triggers special attack.

### Milestone 5 — Enemy AI

Deliverables:

- Tone Deaf enemy.
- Detection/chase/attack/death.
- Enemy spawner.

Acceptance:

- Player can fight 3–5 enemies in a small arena.

### Milestone 6 — Tavern Loop

Deliverables:

- Tavern hub.
- Quest board.
- Launch mission.
- Return to tavern after victory.
- XP result screen.

Acceptance:

- Full loop works from boot to mission complete.

### Milestone 7 — Mini-Boss Slice

Deliverables:

- Ironclad mini-boss.
- Armour break mechanic.
- Arena victory condition.

Acceptance:

- The game has a beginning, middle, and small climax.

### Milestone 8 — Public Prototype Build

Deliverables:

- Windows export.
- Itch.io private upload.
- Build notes.
- Known issues.
- Feedback form.

Acceptance:

- Another person can download and play without you explaining it live.

---

## 9. Asset Strategy

### Art Direction

- Low-poly but not pixel art.
- Chunky silhouettes.
- Cartoony fantasy proportions.
- Dark gothic world, but readable and slightly humorous.
- Use strong character shape language.

### Allowed Asset Types

Preferred:

- CC0.
- MIT.
- Apache-2.0.
- Public domain.
- Paid assets with clear commercial use rights, kept out of public repo unless redistribution is allowed.

Avoid:

- No-commercial-use licences.
- Personal-use-only assets.
- Ripped game assets.
- Fan art based on protected IP.
- Anything resembling official D&D monsters, logos, named settings, spells, or protected lore.

### Asset Register Template

Add every asset to `docs/ASSET_REGISTER.md`:

```md
| Asset | Creator | Source URL | Licence | Commercial Use | Redistribution Allowed | Modified? | Notes |
|---|---|---|---|---|---|---|---|
| Example Knight | Example Creator | https://... | CC0 | Yes | Yes | No | Placeholder player model |
```

---

## 10. Legal / IP Guardrails

This game should be **D&D-inspired only in the broad fantasy sense**, not derivative of Dungeons & Dragons.

Safe inspiration:

- Fantasy adventuring parties.
- Swords, taverns, goblin-like creatures, magic, gothic ruins.
- Original classes, names, monsters, lore, spells, and mechanics.

Avoid:

- D&D logos.
- Forgotten Realms, Baldur's Gate, Waterdeep, Neverwinter, etc.
- Named D&D monsters such as Beholders, Mind Flayers, Displacer Beasts.
- Official spell names if distinctive.
- Rulebook text or stat blocks.
- Directly copying class names, ability structures, monsters, or lore.

Use original names:

- Warrior Bard instead of Bard class.
- Tone Deaf instead of zombie/goblin when possible.
- Ironclad Warden instead of golem if you want distinct identity.
- Breath, Resonance, Encore XP, Verse-Chorus combos.

---

## 11. Testing Plan

### Manual Testing First

Create `docs/TEST_PLAN.md` with checklists for every milestone.

Example movement test:

- [ ] Player starts in correct location.
- [ ] WASD moves camera-relative.
- [ ] Mouse/controller camera rotates smoothly.
- [ ] Dodge works in movement direction.
- [ ] Player cannot walk through walls.
- [ ] Player cannot fall through floor.

Example combat test:

- [ ] Strike animation plays.
- [ ] Strike hitbox appears only during active frames.
- [ ] Enemy takes damage once per swing.
- [ ] Enemy death triggers once.
- [ ] Breath decreases when Sing is used.
- [ ] Resonance increases when Strike lands.

### Automated Testing Later

Godot testing can be added later with a plugin or custom test scenes. Do not block early development on automated tests. The priority is repeatable manual checks and small changes.

---

## 12. Initial Agent Prompts

Store these in `docs/PROMPTS.md`.

### Prompt 1 — Project Setup

```txt
You are helping build Riff Wilde and the Sold-Out Saga, a single-player third-person arcade-action RPG in Godot 4 using strictly typed GDScript.

Your task: create the initial Godot project structure and documentation scaffolding only.

Requirements:
- Do not implement gameplay yet.
- Create the folder structure described in docs/SOURCE_OF_TRUTH.md.
- Add placeholder README sections.
- Add docs/AGENT_RULES.md, docs/ASSET_REGISTER.md, docs/SECURITY.md, docs/ROADMAP.md, docs/TEST_PLAN.md, docs/PROMPTS.md.
- Add a basic Boot scene that can later route to the prototype arena.
- Use small, clean commits.
- Do not add third-party addons.
- Do not import external assets.

After completion, list every file created and explain how I can open/test the project in Godot.
```

### Prompt 2 — Player Movement Prototype

```txt
Build Milestone 1: Movement Playground for Riff Wilde and the Sold-Out Saga.

Context:
- Godot 4.x.
- Strictly typed GDScript.
- Single-player third-person action game.
- No multiplayer, no online services, no save system yet.

Implement:
- Player.tscn with CharacterBody3D.
- PlayerController.gd for camera-relative movement.
- PlayerCameraRig.tscn with spring arm/camera or equivalent stable third-person camera.
- Basic dodge action with cooldown.
- PrototypeArena.tscn with floor, walls, and lighting.
- Input map actions for move, camera, dodge, strike, sing, interact.

Constraints:
- Keep scripts small and decoupled.
- Use typed variables/functions.
- No external assets yet; use placeholder meshes.
- Update docs/TEST_PLAN.md with manual movement tests.

Return:
- Files changed.
- How to test in Godot.
- Known limitations.
```

### Prompt 3 — Strike Combat

```txt
Build Milestone 2: Basic Strike Combat.

Implement:
- StrikeController.gd attached to the player or a child combat node.
- Hitbox.gd and Hurtbox.gd using Area3D.
- DamageEvent.gd as a typed data object/resource if appropriate.
- TrainingDummy.tscn or ToneDeaf placeholder enemy with health.
- HUD text or debug output showing enemy damage.

Requirements:
- Strike should only damage during active frames.
- One swing should not multi-hit the same enemy unless explicitly configured.
- Strike should build Resonance on successful hit.
- Keep animation placeholder simple.
- Update TEST_PLAN.md with combat checks.

Do not:
- Add inventory.
- Add levelling.
- Add external assets.
- Add complex animation trees yet.
```

### Prompt 4 — Sing / Breath System

```txt
Build Milestone 3: Sing and Breath System.

Implement:
- PlayerStats.gd with health, breath, resonance.
- SingController.gd.
- Short Sing blast as a cone or sphere Area3D.
- Breath cost and cooldown.
- Knockback on enemies.
- Basic HUD display for health, breath, resonance.

Requirements:
- Sing must feel mechanically different from Strike.
- Sing should consume Breath.
- Breath should regenerate slowly after a delay.
- Use typed GDScript.
- Update TEST_PLAN.md.

Keep all VFX placeholder-only for now.
```

### Prompt 5 — Combo Buffer

```txt
Build Milestone 4: Verse-Chorus Combo Buffer.

Implement:
- CombatBuffer.gd.
- Track recent Strike/Sing inputs with timestamps.
- Clear buffer after timeout.
- Emit combo_matched(combo_id: StringName).
- Add Intro Combo: Strike → Strike → Sing.
- Trigger a stronger knockdown shout when the combo matches.
- Add HUD/debug feedback showing combo name.

Requirements:
- Combos must be reliable and easy to tune.
- Do not hard-code behaviour directly inside the player controller.
- Keep combo definitions data-driven if practical.
- Update TEST_PLAN.md.
```

### Prompt 6 — Enemy AI

```txt
Build Milestone 5: Tone Deaf Enemy AI.

Implement:
- EnemyBase.gd with health, movement speed, damage, poise.
- ToneDeafAI.gd with idle, chase, attack, stagger, dead states.
- EnemyStateMachine.gd if useful.
- Enemy spawner in PrototypeArena.
- Simple melee enemy attack.

Requirements:
- Player can fight 3 to 5 enemies at once.
- Enemies should not all perfectly stack on top of each other if avoidable.
- Death events should be clean and not double-trigger.
- Update TEST_PLAN.md.
```

### Prompt 7 — Tavern Loop

```txt
Build Milestone 6: Tavern Hub Loop.

Implement:
- TavernHub.tscn.
- Simple quest board interactable.
- Interact action opens mission start panel.
- Start mission loads PrototypeArena.
- Victory condition returns to TavernHub.
- ProgressionManager tracks XP earned this session.
- Mission result panel shows enemies defeated, damage taken, XP earned.

Requirements:
- No complex dialogue yet.
- No save system yet.
- Keep scene transitions simple and reliable.
- Update TEST_PLAN.md.
```

### Prompt 8 — Public Prototype Export

```txt
Prepare the first private Itch.io prototype build.

Tasks:
- Add export presets for Windows desktop.
- Add version number and build notes.
- Add docs/KNOWN_ISSUES.md.
- Add docs/FEEDBACK_GUIDE.md.
- Check that no secrets, paid assets, or unlicensed assets are included.
- Check ASSET_REGISTER.md is complete.
- Create a clean export folder outside source if appropriate.

Do not publish automatically. Provide manual upload steps only.
```

---

## 13. README Starter

Use this as the first `README.md`:

```md
# Riff Wilde and the Sold-Out Saga

Riff Wilde and the Sold-Out Saga is a single-player third-person arcade-action RPG built in Godot 4. You play as a warrior-bard who combines heavy lute-bludgeon melee attacks with sonic magic, rhythm-inspired combos, and dark fantasy tavern theatrics.

## Current Status

Prototype / vertical slice planning.

## Tech Stack

- Godot 4.x
- Strictly typed GDScript
- GitHub for source control and planning
- Itch.io for early private builds

## Development Rule

The current goal is not to build the full game. The current goal is to prove the core loop:

Tavern → Mission → Strike/Sing combat → Victory → Tavern reward.

## Documentation

See:

- docs/SOURCE_OF_TRUTH.md
- docs/ROADMAP.md
- docs/AGENT_RULES.md
- docs/ASSET_REGISTER.md
- docs/TEST_PLAN.md
```

---

## 14. Immediate Next Actions for Phil

When back at the computer:

1. Install/update Godot 4.x stable.
2. Create a private GitHub repo.
3. Create the Godot project locally.
4. Add this file as `docs/SOURCE_OF_TRUTH.md`.
5. Add `docs/AGENT_RULES.md` before letting any coding agent work.
6. Add `.gitignore` before importing anything.
7. Make the first commit with docs only.
8. Open Cline/coding agent with the repo folder only.
9. Run Prompt 1.
10. Review generated structure manually.
11. Commit.
12. Run Prompt 2 only after the setup is clean.

---

## 15. Cut List — Not Yet

These are good ideas, but should be deliberately delayed:

- Multiplayer.
- Co-op.
- Open world.
- Procedural quests.
- Full tech tree.
- Steam Workshop.
- AI-generated dynamic song pipeline.
- Voice acting.
- Console ports.
- Online accounts.
- Cloud saves.
- Paid DLC.
- Analytics.
- Mod support.
- Browser-first optimisation.

---

## 16. Later Roadmap

### Phase 2 — Better Game Feel

- AnimationTree.
- Real character model.
- Better hit reactions.
- Enemy variety.
- Camera polish.
- Controller support.
- Sound effects.
- Combat music layers.

### Phase 3 — RPG Layer

- Tech tree.
- Mission ratings.
- Tavern NPCs.
- Ability upgrades.
- Save/load.
- Equipment/cosmetics.

### Phase 4 — Public Demo

- Itch.io public demo.
- Steam coming-soon page.
- Feedback collection.
- Trailer.
- Devlog.

### Phase 5 — Commercial Build

- Full Act 1.
- 3–5 missions.
- 2 bosses.
- Complete tavern hub.
- Polished menus.
- Steam achievements/cloud saves if justified.

---

## 17. External Reference Notes

- Godot 4 web export currently targets WebGL 2.0 via the Compatibility renderer, so browser builds should stay visually modest and be tested separately from desktop builds.
- GitHub secret scanning is automatic and free for public repositories; private repository coverage depends on account and organisation features.
- Snyk Open Source can scan dependencies for vulnerabilities and licence risks.
- Itch.io allows creators to upload without upfront platform fees and uses open revenue sharing.
- Steam Direct currently lists a $100 USD or equivalent per-app fee.

---

## 18. Core Principle

Do not build the whole game first.

Build the feeling first:

> Move. Strike. Sing. Smash. Laugh. Return to the tavern.

Everything else is optional until that loop is fun.
