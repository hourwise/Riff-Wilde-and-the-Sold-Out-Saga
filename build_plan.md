# Riff Wilde and the Sold-Out Saga — Comprehensive Build Plan

This build plan serves as a step-by-step roadmap for developing the vertical slice of **Riff Wilde and the Sold-Out Saga**. Each stage includes specific implementation tasks, architectural notes, and built-in testing strategies to ensure mechanical stability and fun gameplay.

**Player character:** Riff Wilde.

**Riff's self-appointed titles:** The Maestro of Mayhem; The Sultan of Smash; The Heartbreaker of Kingdom TBD.

---

## Database & Persistence Constraints (Read First)

Based on project constraints and limitations:
1. **Supabase:** 🚫 *Unavailable* — Do not integrate or use.
2. **Firebase:** ⚠️ *Spark (Free Level) Only* — Free level provides Firestore, Realtime Database, and Authentication. However, it does **not** allow Cloud Functions (requires Blaze plan). We must interact with it via HTTP REST APIs (using Godot's `HTTPRequest`) or lightweight plugins, keeping read/write volume below free daily caps (50k reads, 20k writes).
3. **Local / Offline-First Databases (Recommended Baseline):** 
   - **Godot ConfigFile / JSON:** The standard, robust method for saving local player stats, unlocked upgrades, and options to `user://`.
   - **Local SQLite:** Use a GDScript SQLite wrapper for managing large tables of quests, items, dialogue, and stats without server dependency.
4. **Other Free Cloud Databases (Optional):**
   - **MongoDB Atlas (Free M0):** 512MB storage, accessed via REST-based Data API.
   - **Neon Serverless Postgres (Free Tier):** SQL database with small storage limits, auto-suspends on inactivity.

### Storage Strategy for the Vertical Slice
* **Local Persistence (Baseline):** Save all player progression (XP, unlocked combos, settings) locally using `user://save_game.json` or Godot's `ConfigFile`.
* **Cloud Persistence (Optional Sync):** Use **Firebase Firestore (Free Tier)** for optional online leaderboards or cloud save backups. Design the architecture to be **offline-first**, meaning the game is 100% playable offline, and gracefully syncs to Firebase in the background when an active internet connection is detected.

---

## Phase 0: Project Setup & Base Scaffolding

### [ ] Step 0.1: Directory and Scaffolding Creation
Create the initial repository and folder structure matching the codebase architecture blueprint.
- **Tasks:**
  - Create Godot project directory and subfolders under `godot/` (`scenes/`, `scripts/`, `assets/`, `resources/`, `tests/`).
  - Create the documentation directory `docs/`.
  - Add standard Godot `.gitignore` to prevent committing build exports, local editor settings, and `.import/` caches.
  - Create standard empty docs files: `docs/ASSET_REGISTER.md`, `docs/AGENT_RULES.md`, `docs/SECURITY.md`.
- **Built-in Tests:**
  - **Manual Verification:** Open the Godot Editor; verify it imports the empty directory structure cleanly without warnings.
  - **Git Check:** Run `git status` to verify `.gitignore` correctly ignores `.godot/` and local files.

### [x] Step 0.2: Project Settings & Input Configuration
Define project settings and coordinate mappings for PC play.
- **Tasks:**
  - Set project rendering method to Forward+ (desktop) or Compatibility (if browser testing is prioritized).
  - Configure the **Input Map** with the following actions:
    - `move_forward` (W / Up Arrow)
    - `move_back` (S / Down Arrow)
    - `move_left` (A / Left Arrow)
    - `move_right` (D / Right Arrow)
    - `dodge` (Shift)
    - `strike` (Left Mouse Button)
    - `sing` (Right Mouse Button)
    - `sing_hold` (Right Mouse Button Hold)
    - `interact` (E)
    - `pause` (Escape)
- **Built-in Tests:**
  - **Manual Verification:** Run a simple test scene with a script printing `Input.is_action_just_pressed("strike")` to verify mappings work.

### [x] Step 0.3: Autoload Singleton Scaffolding
Create script stubs for global singletons (Autoloads) to manage state.
- **Tasks:**
  - `GameManager.gd`: Handles game loop states (Tavern, Active Mission, Game Over).
  - `AudioManager.gd`: Configures audio channels, background music, and spatial SFX.
  - `ProgressionManager.gd`: Holds active progression stats (XP, level, unlocked skills).
  - `SceneLoader.gd`: Manages scene transitions and loading screens.
- **Built-in Tests:**
  - **Automated Check:** Run the project. Verify in the Godot debugger that all four Autoloads instantiate successfully on startup and print initializing messages to the console.

---

## Phase 1: Player Controller & Movement Playground

### [x] Step 1.1: Player Scene Setup
Set up the physical player representation.
- **Tasks:**
  - Create `Player.tscn` with a `CharacterBody3D` as root.
  - Add a capsule mesh and collision shape.
  - Attach `PlayerStateMachine.gd` to manage player physical states (`Idle`, `Move`, `Dodge`, `Staggered`).
- **Built-in Tests:**
  - **Manual Verification:** Verify the player state machine prints state transitions (e.g., "State changed: Idle -> Move") to the output window when movement inputs are mocked.

### [x] Step 1.2: Third-Person Camera Rig
Implement a camera system that rotates around the player and reacts to terrain.
- **Tasks:**
  - Create `PlayerCameraRig.tscn` using a `SpringArm3D` and `Camera3D`.
  - Attach the rig as a child of the player or sync its position via script.
  - Implement mouse-look script capturing mouse movement and rotating the spring arm.
- **Built-in Tests:**
  - **Manual Verification:** Move the mouse in-game. Verify the camera rotates smoothly around the player without jitter. Test running the player into a wall; verify the `SpringArm3D` correctly shortens the camera distance to prevent clipping through wall geometry.

### [x] Step 1.3: Camera-Relative Movement & Dodge
Implement player controls relative to camera orientation.
- **Tasks:**
  - Write WASD movement logic in `PlayerController.gd` calculated from the camera's forward and right vectors.
  - Implement the `Dodge` action: apply a sudden forward/directional velocity boost, set an invulnerability flag, and run a cooldown timer.
- **Built-in Tests:**
  - **Manual Verification:** Face the camera in various directions. Verify pressing 'W' always moves the player character directly away from the camera's view vector.
  - **Dodge Check:** Verify pressing 'Shift' performs a swift dodge in the direction of movement. Verify dodge is disabled during its cooldown period.

### [x] Step 1.4: Prototype Arena Layout
Build a test map to evaluate movement mechanics.
- **Tasks:**
  - Create `PrototypeArena.tscn`.
  - Use `CSGBox3D` objects (with collision enabled) to build a floor, perimeter walls, ramps, and platforms.
- **Built-in Tests:**
  - **Manual Verification:** Run around the arena. Perform jumps, climbs, and dodges on ramps. Ensure the player does not clip through geometry or fall out of bounds.

---

## Phase 2: Combat System - Strike (Lute-Bludgeon)

### [x] Step 2.1: Hitbox & Hurtbox System
Establish the decoupled spatial overlap system for combat detection.
- **Tasks:**
  - Create `Hitbox.gd` (inherits `Area3D`): Set monitoring to true, monitorable to false. Configured to detect specific physics layers.
  - Create `Hurtbox.gd` (inherits `Area3D`): Set monitoring to false, monitorable to true.
  - Create `DamageEvent.gd` (inherits `RefCounted` or `Resource`): A custom data class containing `damage_amount`, `knockback_force`, `knockback_direction`, and `attacker`.
- **Built-in Tests:**
  - **Integration Check:** Create a small test script where a mock Hitbox overlaps a mock Hurtbox. Verify a signal is emitted and correctly prints the received damage event parameters.

### [x] Step 2.2: Lute Strike Controller
Implement the physical melee bludgeon attack.
- **Tasks:**
  - Add a Lute-Bludgeon placeholder mesh to the Player scene.
  - Attach a child `Hitbox` node matching the strike range arc.
  - Implement `StrikeController.gd` to listen for the `strike` input. Toggle the Hitbox collision shapes active only during active swing frames.
- **Built-in Tests:**
  - **Manual Verification:** Enable "Visible Collision Shapes" in Godot's debug options. Run the game, trigger the Strike, and confirm the red Hitbox area appears only during the sweep of the swing and disappears immediately after.

### [x] Step 2.3: Combat Target Dummy
Create a static object to receive strike damage.
- **Tasks:**
  - Create `TrainingDummy.tscn` using a `StaticBody3D` or `RigidBody3D`.
  - Add a `Hurtbox` child node.
  - Attach a health manager script that listens for damage signals, reduces health, and triggers a knockback force or visual squash-and-stretch effect.
- **Built-in Tests:**
  - **Manual Verification:** Stand next to the dummy and press click. Verify the dummy reacts (shreds particle effects or moves slightly) and logs health reduction to the console on every successful hit.

---

## Phase 3: Combat System - Sing (Vocal Wave) & Core Stats

### [x] Step 3.1: Stats & HUD Display
Implement and monitor player combat resources.
- **Tasks:**
  - Implement `PlayerStats.gd`: Keep tracks of `health` (max 100), `breath` (max 100, used for Singing), and `resonance` (max 100, gained by striking).
  - Implement automatic recovery for `breath` after a brief delay.
  - Implement decay over time for `resonance` if no hits are landed.
  - Create a simple UI HUD (`HUD.tscn`) displaying three progress bars bound to player stats.
- **Built-in Tests:**
  - **Manual Verification:** Verify that hitting an enemy increases the Resonance bar, using a Sing attack drains the Breath bar, and the bars fill or empty accurately.

### [x] Step 3.2: Vocal Sing Attacks
Implement the ranged/physics combat utility.
- **Tasks:**
  - Create `SingController.gd`.
  - Implement a short-range cone blast (using a shape-cast or wider `Area3D` Hitbox) that triggers on `sing` input.
  - Consume a portion of the player's Breath stat.
  - Apply high knockback force but low health damage.
- **Built-in Tests:**
  - **Manual Verification:** Face the training dummy. Trigger a Sing blast. Verify the dummy is pushed back significantly farther than a physical Strike. Verify the attack fails if Breath is completely depleted.

### [x] Step 3.3: Strike-Sing Gameplay Loop
Balance the two actions to encourage alternating play.
- **Tasks:**
  - Configure striking to generate Resonance.
  - Scale the damage and knockback force of Sing attacks based on current Resonance levels (higher Resonance yields stronger sonic waves).
- **Built-in Tests:**
  - **Manual Verification:** Test Sing at 0 Resonance, then strike the dummy to fill the Resonance meter and Sing again. Verify the second Sing applies greater knockback distance/damage.

---

## Phase 4: Verse-Chorus Combo Buffer

### [x] Step 4.1: Combat Input Buffer
Track recent inputs for rhythm combos.
- **Tasks:**
  - Create `CombatBuffer.gd` as a child of the player.
  - Listen to `strike` and `sing` actions, logging them into an array containing the action name and a timestamp.
  - Clear input events older than 0.8 seconds (adjustable combo window).
- **Built-in Tests:**
  - **Console Validation:** Perform sequences like Strike, wait, Strike. Check console printouts to verify inputs register and automatically clear after the window expires.

### [x] Step 4.2: Combo Matching Engine
Detect specific command lists.
- **Tasks:**
  - Define three core combo sequences:
    - **Intro Combo:** `Strike` ➔ `Strike` ➔ `Sing`
    - **Bridge Combo:** `Sing` (Hold / Quick) ➔ `Strike`
    - **Crescendo Finisher:** `Strike` ➔ `Sing` ➔ `Strike`
  - Match current buffer history against patterns. On match, emit a `combo_matched(combo_name)` signal and clear the buffer.
- **Built-in Tests:**
  - **Integration Check:** Press Strike ➔ Strike ➔ Sing in rapid succession. Verify the HUD or logger displays "Combo Matched: Intro Combo" immediately.

### [x] Step 4.3: Combo Executions
Execute special physics/attacks for combos.
- **Tasks:**
  - **Intro Combo:** Perform a heavy vocal shout that applies a "knockdown" status (forcing enemies into a temporary flattened state).
  - **Bridge Combo:** Lift a nearby dummy and pull it toward the player.
  - **Crescendo Finisher:** Trigger a circular radial blast wave damaging all targets within a 360-degree perimeter.
- **Built-in Tests:**
  - **Manual Verification:** Execute the Crescendo Finisher surrounded by multiple dummies. Check that all dummies within range are hit simultaneously.

---

## Phase 5: Enemy AI (The Tone Deaf & Ironclad Warden)

**Progress note:** Steps 5.1 and 5.2 are complete for the current prototype pass. Added `EnemyBase.gd`, `ToneDeafAI.gd`, `ToneDeaf.tscn`, and a fixed three-enemy Tone Deaf pack in `PrototypeArena.tscn`. Tone Deaf enemies now chase with runtime navigation, use attack wind-up, damage the player, stagger from player hits, die permanently, and decrement the local encounter counter. Clearing the current pack now shows a temporary "Encounter cleared" notification and does not trigger victory or area completion. Step 5.3 is implemented and ready for manual balance testing: `IroncladWardenAI.gd` and `IroncladWarden.tscn` add an armored heavy that blocks non-Sing damage while armor is active, converts Sing resonance power into armor damage, then becomes vulnerable to Strikes after armor break. Enemy overhead status bars were added: Tone Deaf shows HP; Ironclad Warden shows HP plus armor, with armor feedback and armor-bar removal after break. Fuller spawn-director and area-objective systems move into the mission-flow work.

### [x] Step 5.1: Enemy State Machine
Establish baseline AI behaviors.
- **Tasks:**
  - Create `EnemyBase.gd` as a template script inheriting `CharacterBody3D`.
  - Add basic state machine: `Idle`, `Chase`, `Attack`, `Stagger`, `Dead`.
  - Implement navigation agent tracking the player coordinate.
- **Built-in Tests:**
  - **Manual Verification:** Confirmed. Tone Deaf enemies chase the player, use runtime navigation around arena obstacles, handle ramps/low edges more cleanly, and recover pursuit after temporary line-of-sight loss.

### [x] Step 5.2: The Tone Deaf (Melee Swarm)
Implement the base melee opponent.
- **Tasks:**
  - Set low health and low poise (meaning every Strike or Sing staggers them immediately).
  - Add a simple swing attack that targets the player if within range.
  - Implement a basic prototype pack of 3-5 Tone Deaf in the arena.
- **Built-in Tests:**
  - **Manual Verification:** Confirmed. Player attacks interrupt enemies, Tone Deaf wind-up attacks damage the player, enemies can kill the player, death stops further enemy damage, and killing all three enemies logs `Encounter cleared. Area remains active.`

### [x] Step 5.3: The Ironclad Warden (Armored Heavy)
Implement the armor/poise mechanic.
- **Tasks:**
  - Create `IroncladWarden.tscn`.
  - Add an armor/poise meter. While the shield is active, the Warden is completely immune to standard Strike damage and cannot be staggered.
  - Make Sing attacks (specifically at high Resonance) deal massive damage to the armor meter. Once depleted, the Warden enters a prolonged stagger and becomes vulnerable to physical Strikes.
- **Built-in Tests:**
  - **Automated Check:** Passed. Strike does not damage health while armor is active; high-power Sing breaks armor; Strike damages health after armor break.
  - **Automated Check:** Passed. Tone Deaf and Ironclad Warden status bars instantiate, debug text labels are hidden, and Warden armor bar hides after armor break.
  - **Visual Check:** Resolved. Health/Armor bars now use a single-quad shader to prevent floating/separation during camera movement.
  - **Manual Verification:** Attempt to strike the Ironclad Warden. Observe 0 damage and no stagger. Generate Resonance on regular enemies or dummies, launch Sing attacks on the Warden to break armor, then strike to confirm damage is applied. Tune armor values, speed, attack wind-up, and damage after playtest.

---

## Phase 6: Tavern Hub & Game Loop Flow

### [x] Step 6.1: Tavern Hub Layout
Build the safe zones where players upgrade.
- **Tasks:**
  - Create `TavernHub.tscn`.
  - Place a Quest Board `Area3D` with an interaction indicator.
  - Implement a simple interact script that opens a 2D Mission Selection UI.
- **Built-in Tests:**
  - **Automated Check:** Passed. `TavernHub.tscn` loads, creates the hub UI, opens the mission panel, and sets `GameManager` to `TAVERN`.
  - **Manual Verification:** Walk the player character to the Quest Board. Confirm an "Interact [E]" prompt appears, and pressing 'E' opens the mission panel.

### [x] Step 6.2: Scene Loading & Flow Management
Manage the main game state changes.
- **Tasks:**
  - Wire the Quest Board UI to launch the mission arena through `SceneLoader.gd`. **Implemented for Tavern Hub -> Prototype Arena.**
  - Create an area-complete condition for mission zones. This must require all relevant enemies and bosses to be defeated, required scouting objectives to be completed, and any mandatory loot or exit interactions to be resolved. **Implemented for Prototype Arena using enemy defeat plus scouting marker.**
  - Keep local enemy-pack clears separate from area completion. Clearing one fight should show only a short encounter-cleared notification and should not freeze controls or offer extraction. **Implemented.**
  - On area completion or player death, freeze inputs and offer appropriate transitions such as next zone, return to hub, retry, or continue exploring if optional objectives remain. **Implemented first pass: area completion activates an extraction point that returns to Tavern Hub.**
- **Built-in Tests:**
  - **Automated Check:** Passed. Tavern mission launch switches `GameManager` to `MISSION` and loads `PrototypeArena.tscn`.
  - **Automated Check:** Passed. Scouting plus all enemies defeated marks the area complete, activates extraction, and returns to `TavernHub.tscn`.
  - **Manual Loop Verification:** Start in Tavern ➔ Accept Quest ➔ Load Arena ➔ Clear one mob pack ➔ Verify exploration continues ➔ Complete all area objectives and boss defeat ➔ Verify extraction/next-zone options appear.

### [x] Step 6.3: Score & XP System
Reward player performance.
- **Tasks:**
  - Track stats during missions (damage dealt, combos completed, clear time). **Implemented first pass: tracks damage dealt, armor damage, damage taken, enemies defeated, combos completed, scouting completion, and elapsed time.**
  - Map calculations in `ProgressionManager.gd` to yield XP. **Implemented first pass.**
  - Present an Encore scoreboard overlay in the Tavern upon returning. **Implemented as a Tavern results panel after extraction.**
- **Built-in Tests:**
  - **Automated Check:** Passed. Completing and extracting from Prototype Arena awards XP and shows the Tavern results panel.
  - **Manual Verification:** Complete a mission and confirm the XP score screen summarizes correct numbers and adds it to the player's total XP pool.

---

## Phase 7: Database & Persistence Layer

### [x] Step 7.1: Local Save/Load (Baseline)
Build the local file saving system.
- **Tasks:**
  - Create `SaveService.gd` helper script. **Implemented as an autoload.**
  - Collect player variables from `ProgressionManager.gd` (XP, level, unlocked skills, settings) and write them to a JSON or ConfigFile at `user://save_data.dat`. **Implemented for XP, level, and unlocked skills using `user://save_data.json`.**
  - Implement load logic to populate state on startup. **Implemented in `ProgressionManager._ready()`.**
- **Built-in Tests:**
  - **Automated Check:** Passed. Isolated test save persisted XP and unlocked skill, then reloaded both into `ProgressionManager`.
  - **Manual Verification:** Play the game, earn XP, and close the application. Re-open and verify the total XP matches the end of the previous session.

### [ ] Step 7.2: Database Choice & Configuration (Firebase Free Tier)
Configure connections under the specified database constraints.
- **Tasks:**
  - **Constraint Rules Configured:**
    - Local DB is the primary source of truth.
    - Cloud syncing behaves asynchronously and does not block loading or progression.
  - Create a Firebase configuration script using Firebase REST API URLs pointing to Firestore (Spark Plan).
  - Use `HTTPRequest` nodes to send GET/POST payloads for database storage.
- **Built-in Tests:**
  - **Connectivity Test:** Trigger a connection check. Verify that if the remote server is unreachable, the game prints a warning and proceeds using local files without stuttering or crashing.

### [ ] Step 7.3: Asynchronous Cloud Sync
Save scores and progress to Firebase.
- **Tasks:**
  - Write standard Firestore REST request structures to upload player scores (`/documents/users/<user_id>`).
  - Cap database write requests to occur ONLY when returning to the Tavern, ensuring daily free-tier limits (20,000 writes/day) are not exceeded.
- **Built-in Tests:**
  - **Integration Check:** Complete a mission, trigger cloud sync, and verify in the Firebase Console (via web browser) that the document is updated with correct XP values.

---

## Phase 8: Polish, Audio & Export

### [ ] Step 8.1: Audio Spectrum Analyzer
Implement reactive visual elements.
- **Tasks:**
  - Configure Godot's audio bus routing: Send vocals and sound effects to an effects channel.
  - Add an `AudioEffectSpectrumAnalyzer` to the combat audio bus.
  - Write a script that reads frequency magnitudes (Bass, Mid, High) and passes them to environment shaders or mesh scales (e.g., lights pulsing to the beat).
- **Built-in Tests:**
  - **Manual Verification:** Play background track or execute Sing yells. Confirm target objects or lights scale up and pulse relative to the volume of the sound.

### [ ] Step 8.2: Windows Desktop Export
Compile the final vertical slice build.
- **Tasks:**
  - Configure Godot export settings for Windows Desktop.
  - Export the binary and pack files to `exports/windows/`.
  - Add `docs/KNOWN_ISSUES.md` detailing any bugs.
- **Built-in Tests:**
  - **Clean Machine Test:** Move the exported executable to a separate computer that does not have Godot installed. Run the game and verify it loads, plays, saves locally, and closes successfully.
