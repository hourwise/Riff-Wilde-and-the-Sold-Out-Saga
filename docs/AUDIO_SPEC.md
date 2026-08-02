# Audio Specification — Vertical Slice

This is the delivery contract for all audio in the vertical slice. The engine-side
`MusicDirector` is built against these exact filenames and timings, so audio can be
produced in parallel with code and dropped in without any changes to gameplay logic.

**Hand this document to whoever produces the music.**

---

## 1. Global Technical Requirements

| Property | Value | Why |
|---|---|---|
| Container | `.ogg` (Vorbis) | Godot-native, good compression, gapless looping |
| Sample rate | 44,100 Hz | Engine default; avoids resampling artefacts |
| Bit depth (source) | 24-bit WAV, converted to OGG at q6+ | Keep lossless masters outside the repo |
| Channels | Stereo | — |
| Loudness (music) | −14 LUFS integrated, −1.0 dBTP ceiling | All stems matched so layers stack without clipping |
| Loudness (SFX) | −18 LUFS average, −1.0 dBTP | Sits under music |
| Silence | **Zero** leading/trailing silence on looping stems | Any padding causes an audible gap on loop |

Deliver music to `godot/assets/audio/music/` and SFX to `godot/assets/audio/sfx/`.

## Two ways to deliver music

The director accepts either, and reports which mode it is in on startup.

**Layered stems** — the original contract below. Four combat parts bounced from
one arrangement, all 120 BPM and exactly 32.000s, sample-aligned. They are started
together and never restarted, and the Encore reveals them one at a time on bar
boundaries. This is the richer option and the meter's effect is unmistakable.

**One finished arrangement** — a whole track of any length and tempo, named
`combat_full` / `boss_choirmaster_full`. The Encore then drives *intensity*
instead: a low-pass filter that opens and a level that lifts as the meter climbs,
so a low Encore sounds like the music is in another room and a full one brings it
into this one. This is not a degraded fallback; it is what the delivered tracks
needed.

`.ogg` and `.wav` are both accepted. `.ogg` is strongly preferred — the three
delivered `.wav` tracks are 68 MB between them, against roughly 6 MB as Ogg
Vorbis at a quality nobody would tell apart. If the tracks can be re-exported as
`.ogg`, drop them in beside the `.wav` files and the director will prefer them
with no code change.

## Delivered

| Track | File | Length | Notes |
|---|---|---|---|
| Moonlit Crypt | `explore_graveyard_ambient.wav` | 84.4s | The exploration bed. |
| Spectral Fanfare | `combat_full.wav` | 82.9s | Combat, run as one arrangement. |
| The Liturgical Duel | `boss_choirmaster_full.wav` | 190.9s | The Choirmaster. Opens further at each conducted interlude. |

All three are 48 kHz stereo, set to loop forward on import, and compressed to QOA
in the project so the 68 MB on disk is not 68 MB in memory.

Still wanted: `tavern_ambient` for the Inn, and an encore stinger for the closing
performance.

---

## 2. The Layered Combat System — Critical Constraint

The four combat layers are **stems of a single arrangement**, not four separate pieces
of music. They are played back simultaneously and faded in/out independently. This only
works if all four are:

- The **same tempo** (recommended: **120 BPM, 4/4**)
- The **same length** (recommended: **16 bars = 32.000 seconds** at 120 BPM)
- **Sample-aligned** — bar 1 beat 1 starts at sample 0 on every stem
- **Seamlessly loopable** in isolation *and* in any combination
- Mixed so that **L1 alone sounds intentional** and **L1+L2+L3+L4 sounds like the full band**

Produce the full arrangement first, then mute-and-bounce each stem. Do not compose
them separately.

> Reverb tails are the usual cause of loop clicks. Bounce with "include tail" past the
> loop point, then fold the tail back onto the start of the file.

### Combat stems

| File | Contents | Triggered at |
|---|---|---|
| `combat_l1_guitar.ogg` | Bass + rhythm guitar foundation. The spine of the track. | Combat starts |
| `combat_l2_percussion.ogg` | Drum kit, toms, driving rhythm. | Encore ≥ 33% |
| `combat_l3_trumpet.ogg` | Brass fanfare / Sir Brass's voice. | Encore ≥ 66% |
| `combat_l4_lead.ogg` | Lead guitar, organ, vocal wails, choir. | Encore = 100% |

`combat_l4_lead.ogg` is **additive** — it stacks on top of L1+L2+L3. It is not a
pre-mixed "full version". Layers are never swapped, only faded in.

### Ambient / exploration

| File | Contents | Length |
|---|---|---|
| `explore_graveyard_ambient.ogg` | Non-metrical bed: wind, distant choir drone, low strings, occasional bell. Tension without rhythm. | 60–90 s, seamless loop |

This does **not** need to be tempo-locked — it crossfades out when combat begins.

### Boss — The Choirmaster

Same stem rules as above (120 BPM, 32.000 s, sample-aligned).

| File | Contents |
|---|---|
| `boss_choirmaster_l1.ogg` | Pipe organ + choir. Menacing, liturgical, in charge. |
| `boss_choirmaster_l2.ogg` | Riff fights back: guitars and drums enter over the organ. Phase 2. |

### Inn / Tavern

| File | Contents | Length |
|---|---|---|
| `tavern_ambient.ogg` | Warm, low-key: lute noodling, hearth crackle, murmur. Loops under dialogue. | 60–90 s, seamless loop |
| `encore_performance.ogg` | **The payoff.** One-shot, non-looping. Riff performs after the mission: starts sparse (guitar + vocal), builds to full band with trumpet, crowd roars on the final hit. | 60–90 s |

`encore_performance.ogg` is the emotional close of the demo. It should sound like the
best 90 seconds in the build.

---

## 3. Sound Effects

Named exactly as listed. Mono is fine for all SFX; the engine positions them in 3D.

### Narrative / world
| File | Notes |
|---|---|
| `church_bell_toll.ogg` | Single deep toll with long tail. Fires when the last altar is cleansed. Must feel like an event. |
| `altar_cleanse.ogg` | Corruption breaking; spectral shimmer resolving to a clean chord. |
| `choir_corrupted_loop.ogg` | Loops from Hollow Choir enemies while channelling. Dissonant, wrong. |

### Player
| File | Notes |
|---|---|
| `riff_strike_swing_01/02/03.ogg` | Three variations, heavy wooden whoosh. |
| `riff_strike_impact_01/02/03.ogg` | Lute-bludgeon connecting. Wood + metal + a struck string. |
| ~~`riff_strike_impact`~~ | **Delivered** (1 of 3 variations). A struck open-E chord, cut to 0.5s. Two more variations would help — the pitch jitter covers a single sample, but the ear finds the pattern in one sample faster than in three. |
| `riff_sing_blast.ogg` | The vocal wave. |
| `choirmaster_conduct.ogg` | The Choirmaster turning to the great altar and raising his hands. The cue that he has become untouchable, so it must be unmistakable over a fight already in progress. Three times per fight. |
| `choirmaster_summon.ogg` | One of the dead clawing its way up. Played per summon, up to eight in a wave, so it needs to stack without turning to mud. |
| `choirmaster_cast.ogg` | A note leaving his hands. Heavier and lower than the Cantor's — he fires three at a time and should not read as a large Cantor. |
| `choirmaster_stomp.ogg` | His close-range answer, when Riff gets inside his casting distance. |
| `cantor_note.ogg` | The Dirge Cantor releasing a sung note at the player. A single sustained vowel, cold and thin — it is a telegraph as much as a sound, so it must carry across a noisy fight. |
| `riff_song_restore.ogg` | The restorative song, sung between fights to heal. Roughly 1.8s and should read as a complete phrase rather than a loop, because it is cut off the moment Riff is hit — the break needs to be audible. Warm and unhurried, the opposite of the blast. |
| `riff_dodge.ogg` | Cloth + boot scuff. |
| `riff_combo_finisher.ogg` | Power chord stinger on combo completion. |
| `riff_hurt_01/02.ogg`, `riff_death.ogg` | — |
| `footstep_stone_01..04.ogg`, `footstep_grass_01..04.ogg` | Four variations each. |

### Companion
| File | Notes |
|---|---|
| `sirbrass_summon.ogg` | Spectral materialisation. |
| `sirbrass_trumpet_attack.ogg` | The signature blast. Should be genuinely triumphant. |
| `sirbrass_dismiss.ogg` | Fading back to spectral form. |

### Enemies
| File | Notes |
|---|---|
| `tonedeaf_groan_01/02.ogg`, `tonedeaf_attack.ogg`, `tonedeaf_death.ogg` | |
| `gravecrawler_screech.ogg`, `gravecrawler_leap.ogg`, `gravecrawler_death.ogg` | |
| `hollowchoir_channel_start.ogg`, `hollowchoir_interrupt.ogg`, `hollowchoir_death.ogg` | |
| `bellringer_bell_swing.ogg`, `bellringer_shockwave.ogg`, `bellringer_stagger.ogg`, `bellringer_death.ogg` | |
| `choirmaster_summon.ogg`, `choirmaster_conduct.ogg`, `choirmaster_phase_change.ogg`, `choirmaster_death.ogg` | |

### UI
| File | Notes |
|---|---|
| `ui_hover.ogg`, `ui_confirm.ogg`, `ui_back.ogg`, `ui_objective_complete.ogg`, `ui_encore_full.ogg` | `ui_encore_full.ogg` fires when the Encore meter fills — the cue to summon Sir Brass. |

> **Shortcut:** Kenney publishes CC0 SFX packs (Impact Sounds, RPG Audio, UI Audio) that
> can cover footsteps, impacts and UI immediately, leaving only the character-specific
> and narrative sounds to be produced. Any pack used must be added to `ASSET_REGISTER.md`
> before import.

---

## 4. Engine-Side Behaviour (for reference)

Producers do not need to implement any of this — it describes what the engine does with
the files so the mix can be judged in context.

**Bus layout:** `Master` → `Music` → (`MusicAmbient`, `MusicCombat`, `MusicBoss`) and
`Master` → `SFX` → (`SFXPlayer`, `SFXWorld`, `SFXUI`).

- All four combat stems start together, in sync, at volume `-80 dB`. Layers are revealed
  by fading to `0 dB` over 1.5 s. They are never started or stopped individually, which
  is what guarantees they stay phase-locked.
- Entering combat crossfades ambient → combat over 1.2 s.
- Leaving combat holds the combat bed for 4 s (in case a straggler re-engages), then
  crossfades back to ambient over 2.5 s.
- Layer changes are quantised to the next bar boundary so instruments never enter
  off-beat. This requires the 120 BPM / 32.000 s contract above to be exact.
- The `Music` bus ducks by 6 dB during dialogue and cinematic voice lines.

---

## 5. Delivery Checklist

- [ ] All combat stems are exactly 32.000 s and start on beat 1
- [ ] Each combat stem loops cleanly in isolation
- [ ] L1 alone sounds like a finished piece of music
- [ ] L1+L2+L3+L4 does not clip and sounds like one band
- [ ] Ambient and tavern loops have no audible seam
- [ ] All files are `.ogg`, 44.1 kHz stereo, normalised to spec
- [ ] Licence and authorship recorded in `docs/ASSET_REGISTER.md`
