# GDD & Technical Specification: Riff Wilde and the Sold-Out Saga

A unique, single-player, third-person arcade-action RPG built in Godot 4, featuring Riff Wilde, a high-octane warrior-bard who manipulates sonic waves and channels heavy physical bludgeoning in a dark, gothic world filled with satirical, self-aware humor.

---

## 1. Executive Game Concept

* **Core Tagline:** "Brutal Legend meets Dark Souls, directed by a rhythmic ego-maniac."
* **Genre:** Single-player Third-Person Arcade Action RPG.
* **Target Platforms:** PC (Steam, Itch.io), Console ports down the line.
* **Core Philosophy:** Subvert the traditional "squishy support bard" archetype into a front-line physical and magical powerhouse. Contrast terrifying, bleak cosmic horror and gothic tropes with a protagonist who treats the apocalypse like a touring rock concert.
* **Player Character:** Riff Wilde.
* **Self-Appointed Titles:** The Maestro of Mayhem; The Sultan of Smash; The Heartbreaker of Kingdom TBD.

---

## 2. Core Gameplay Mechanics & Features

### ⚔️ The Combat Loop

Combat relies on a fluid, distinct two-button paradigm that separates melee physical weight from telekinetic sonic energy, blending arcade combo mechanics with weighty positioning.

* **The Lute-Bludgeon (Strike):** A massive, iron-rimmed acoustic guitar treated like a war club or battleaxe. Every physical smash hits a literal chord, accumulating **Resonance** (Style & Performance juice).
* **Vocal Telekinesis (Sing):** The bard uses physical sound vibrations to distort physics. Consumes **Breath**.

  * *Low Level:* Quick whistling or humming to flick pebbles, distracting guards or breaking enemy guard animations.
  * *Mid Level:* Guttural war cries that lift boulders out of the ground, holding them suspended with a sustained vocal note before launching them.
  * *High Level:* Perfect acoustic resonance capable of ripping down structural masonry, shattering metal shields, or tearing boss armor completely off.

### 🎵 The "Verse-Chorus" Combo Architecture

Inputs are buffered sequentially to execute devastating spectral attacks:

* **Intro Combo (`Strike` ➔ `Strike` ➔ `Sing`):** Two horizontal bludgeons swing crowd-control arcs, followed by a *Staccato Shout* that knocks enemies flat on their backs.
* **Bridge Combo (`Sing [Hold]` ➔ `Strike`):** Telekinetically lift a distant object or minor enemy, snapping them directly into your physical space for a home-run swing with the Lute-Bludgeon.
* **Crescendo Finisher (`Strike` ➔ `Sing` ➔ `Strike`):** Embed the weapon into the earth, belt out a sustained chord to manifest a *Spectral Double-Bass Drum*, and kick it to release a 360-degree armor-shattering shockwave.

### 🎭 The Idle System ("The Creative Itch")

* If the player halts input for too long in a level, the bard breaks into impromptu song, tuning strings or assessing the room's vocal reverb.
* **Mechanical Catch:** Slowly recovers Breath and minor Health, but generates physical sound waves. Leaving your character idle in an uncleared zone **will** alert and aggro surrounding monsters.

---

## 3. Progression & The Game Loop

```
[ COMBAT ZONE / MISSION ]
         │ (Track combos, styles, spectral weapon variety)
         ▼
[ CINEMATIC ENCORE CUTSCENE ]
         │ (AI/Suno dynamic ballad based on actual gameplay metrics)
         ▼
[ THE TAVERN / INN HUB ]
         │ (Spend XP in Tech Tree, talk to patrons for Tier Quests)
         ▼
[ WORLD MAP NEXT MISSION ]
```

### 🍻 The Tavern / Inn Loop (Performance-to-Progression)

* **Dynamic Song Generator:** Level clears don't go to abstract tally screens. Instead, the game sequences a cinematic cutscene in the local Inn. The song played (pulled from a modular pool of pre-recorded AI Suno tracks) matches how you fought.

  * *High Combo / Flawless:* Fast-paced, hyper-arrogant rock anthem. Crowd goes wild, throws gold, awards massive **Legendary Encore XP**.
  * *Low Health / Sloppy:* Self-deprecating, darkly comedic acoustic blues song about getting pulverized. Crowd boos, throws rotten vegetables (Low XP reward).
* **The "Tiered Open Hub" World Structure:** Each act features a single town and its local Inn. The player can choose any mission from the local patrons in any order. Once all Tier missions and the final Regional Boss are vanquished, a mysterious **Stranger** arrives to tip the bard off about horrors in the next province, transitioning the player to a completely new Inn Hub with higher difficulties and fresh crowds.

---

## 4. Tech Tree: "Orchestra of War"

Spend XP acquired from tavern sets to branch into completely different physical-sonic archetypes:

```
                      [ THE WARRIOR BARD ]
                               │
       ┌───────────────────────┼───────────────────────┐
       ▼                       ▼                       ▼
   [ STRING ]               [ WIND ]            [ PERCUSSION ]
 (The Razor Duelist)     (Ranged Wizard)     (Concussive Juggernaut)
```

1. **String Tree (The Razor Duelist):** Focused on agile, slicing physical blade attacks. Unlocks *Razor Strings* (vocal blasts fire sonic projectiles out of guitar strings) and *Spectral Violins* (orbiting bows that auto-parry incoming backline projectiles).
2. **Wind Tree (The Battlefield Commander):** Focused on massive AoE crowd control and manipulation. Unlocks *Brass Shrapnel* (hunting horn blasts serving as short-range shotguns) and *Tempest Pipe Organs* (spawning massive organ tubes from the ground that vacuum enemies together).
3. **Percussion Tree (The Heavy Juggernaut):** Focused on defense and concussive power. Unlocks *Snare Counters* (drums that stun enemies on a perfect parry) and *The Grand Gong* (a towering screen-clearing blast wave that disintegrates low-tier targets).

---

## 5. Technical Architecture & Tech Stack

### 🛠️ The Software Stack

* **Game Engine:** Godot 4.x (Highly optimized for lightweight, performant 3D deployment, native object layout, and custom data processing).
* **Programming Language:** **Strictly Typed GDScript**. Chosen deliberately for its deep AI-agent familiarity, zero compilation latency, and swift refactoring cycles.
* **Development Paradigm:** Agentic Assistance via **VS Code + Cline (Plan-and-Act architecture)**. Powered by Claude Sonnet models, anchored with a local **Godot MCP Server** allowing the agent to interface directly with engine environments, terminal contexts, and scene tree nodes.

### 📁 Initial Codebase Blueprints

The foundational architectural block should maintain clean division via decoupled components:

1. `PlayerStateMachine.gd`: Manages movement and animation states (`Idle`, `Run`, `MeleeStrike`, `VocalSing`, `Staggered`), using Godot 4's `AnimationTree` with upper/lower body masks.
2. `CombatBuffer.gd`: A modular timer-driven node catching player inputs, appending them to an internal array stack, and broadcasting signal executions when key patterns match.
3. `AudioManager.gd`: Global Autoload singleton managing spatial audio. Uses Godot's `AudioEffectSpectrumAnalyzer` to grab frequency values from the Vocal Audio Bus and pipe them directly into global shader uniforms.
4. `ProgressionManager.gd`: Cross-scene global state engine holding data for current player XP, unlocked tech paths, and completion status of quest dictionaries across acts.
5. `VocalTelekinesis.gd`: Physics logic helper executing sphere-casts to dynamically tag local `RigidBody3D` assets, applying continuous central counter-gravity forces to sustain floatation.

---

## 6. Expanded Content & Expansion Suggestions

### 🗺️ Expanded Level Design

* **Act 1 Hub: The Muddy Pig Tavern**

  * *Vibe:* Dilapidated, rain-slicked medieval farming hub.
  * *Levels:* *The Weeping Catacombs* (tight corridors, linear crypts), *The Sunken Mire* (hazardous swamps reducing mobility, forcing use of ranged pebble distracting tricks).
* **Act 2 Hub: The Iron Anvil**

  * *Vibe:* Subterranean, industrial mining citadel. Massive volcanic columns and dark dwarven steel architecture.
  * *Levels:* *The Obsidian Spires* (extreme vertical drop-offs; excellent for using Wind skills to blast monsters into chasms), *The Core Smelter* (lava hazards, heavy moving mechanical platforms).
* **Act 3 Hub: The Cathedral of Whispers**

  * *Vibe:* Gothic, silent city shrouded in unnatural mist. The crowd here consists of hollowed-out nobility who only appreciate classical or dirge compositions.
  * *Levels:* *The Silent Courtyard*, *The Grand Organ Altar*.

### 👾 Mob & Bestiary Breakdown

* **The Tone Deaf (Act 1 Swarm):** Rotting zombies who shuffle mindlessly toward you. They have low poise, meaning basic `Strike` impacts or low-level pebble flicks easily pop their limbs off.
* **Screaming Banshees (Act 2 Elite):** Flying, ethereal monsters that use a rival acoustic magic. They shield other enemies with sonic walls. The player must use a precise *Frequency Matching* Wind or String skill to break their pitch barrier.
* **Ironclad Wardens (Act 2 Heavy Tank):** Massive golems completely immune to standard melee bludgeoning. The player must strike them with the guitar to build Resonance, then use a maximum-charge `Sing` note to vibrate their armor plating until it shatters off.
* **The Grand Maestro (Act 3 Boss):** A terrifying multi-limbed phantom that controls an array of flying sharp orchestra strings. He alters the game's background tempo, forcing the player to adapt their combo window speeds to the rhythmic music track playing in real-time.

### 🎨 Visual & Audio Design Expansion

* **Visual Direction:** Gritty, high-contrast desaturated dark-fantasy palette (reminiscent of Dark Souls) interrupted by vivid, ethereal neon-gold or ghostly-blue visual effects whenever spectral instruments manifest. Use custom GLSL vertex shaders to make physical assets visibly shake, ripple, and tear apart along sound-wave contours.
* **Audio Direction:** Leverage Godot 4’s audio routing. Apply severe distortion, chorus, or delay blocks programmatically to the *entire game world audio mix* when the player is running a high combo multiplier, giving the player the visceral feeling of being in an overdriven live concert.

### 💰 Monetization Strategy (Tailored for Indie Premium)

To preserve the charm of a single-player arcade experience and maximize community goodwill:

* **Base Game Model:** Premium paid release on Steam/Consoles ($19.99 to $24.99 sweet spot).
* **Free Content Loop:** Include hidden unlockable "Guitar Skins" or "Tavern Costumes" behind challenging in-game masteries or flawless combo ratings (No microtransactions).
* **Post-Launch DLC ("The Second Tour"):** Major episodic updates introducing a completely new Hub Town/Inn, an extra Instrument Tree (e.g., Brass or Woodwind), and 4-5 high-difficulty maps bundled with new Suno tracks.

### 📈 Future Roadmap Suggestions

* **Steam Workshop Support:** Expose the song mapping schema. Allow players to drop their own `.ogg` audio files and custom txt chord files into a mod folder so the game dynamically scales its environment, visual effects, and enemy attack rhythms to custom user tracks.
* **Local/Co-Op Jam Mode:** A two-player local arcade mode where a second player joins as a Percussionist or Violinist, allowing players to bridge their input buffers to pull off massive cooperative orchestral cataclysms.
