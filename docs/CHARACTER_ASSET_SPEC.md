# Character Asset Specification — Riff Wilde

Delivery contract for Riff's model, rig, animations and his lute-bludgeon.
The engine is already built against this: `CharacterVisual` maps clip names to
gameplay, so a model meeting this spec drops in without gameplay code changes.

---

## 1. The One Rule That Matters Most

**All animations must be in place, with root motion baked OFF.**

Riff is a `CharacterBody3D` driven by velocity in code. If the animations move the
root, the animation and the physics will fight each other and he will slide,
drift or teleport. Every clip should play as if he is on a treadmill — feet
cycling, root staying at the origin.

In Mixamo this is the **"In Place"** checkbox. In Blender, clear the root/hips
location channel before export.

---

## 2. Model

| Property | Value |
|---|---|
| Format | **`.glb`** (binary glTF), single file |
| Height | **~2.0 m** to the top of the head, matching the concept sheet's height guide |
| Pose | A-pose or T-pose |
| Facing | **−Z** (Godot's forward). If it faces +Z I can correct it with one rotation — just tell me |
| Up axis | **+Y** |
| Origin | Between the feet, on the ground plane — **not** at the hips |
| Scale | Applied (no unapplied scale on the export) |
| Textures | **Embedded** in the `.glb` |
| Polycount | 8k–15k triangles is right for this game |

**Riff must be modelled without the lute.** You have already done this — the lute
is a separate weapon model (section 5) so it can be swung independently.

---

## 3. Rig

| Property | Value |
|---|---|
| Type | Humanoid skeleton, single armature |
| Bones | Standard humanoid hierarchy — hips → spine → chest → neck → head, plus both arms and legs |
| Hands | **Right hand bone required.** The lute attaches to it via a `BoneAttachment3D` |
| Naming | Any consistent convention is fine (Mixamo's `mixamorig:*` is ideal). I will read the actual bone names from the file — no need to rename anything |

---

## 4. Animations

Deliver **one `.glb` containing the mesh and every clip**. One file with one
AnimationPlayer is far simpler in Godot than separate files needing animation
library wiring. If your tool can only export clips separately, say so and I will
set up the library import instead.

### Required — the demo needs all eight

| Clip name | Loop | Target length | Notes |
|---|---|---|---|
| `idle` | Yes | 2–4 s | Cocky, weight on one leg, alive rather than static. He is a showman standing still |
| `run` | Yes | 0.6–0.9 s | Full stride cycle. Speed is matched in code, so author it naturally |
| `attack_1` | No | ~0.45 s | Horizontal lute swing, right to left. Impact lands about a third in |
| `attack_2` | No | ~0.45 s | Return swing, left to right. Must read as continuing from `attack_1` |
| `attack_3` | No | ~0.80 s | The finisher — big overhead power-chord smash. Slower wind-up, heavier follow-through |
| `dodge` | No | ~0.35 s | Quick roll or hard side-step. Reads as evasive, not as a stumble |
| `hit` | No | ~0.3 s | Short flinch. Must not fully interrupt — he keeps his footing |
| `death` | No | 1–2 s | Collapse. Holds on the final pose |

The three attacks are a chain: `attack_1 → attack_2 → attack_3` plays as one
combo, so they should flow into each other rather than each returning to idle.

Lengths are targets, not constraints — I can retime playback in code. Getting the
*shape* right (where the impact lands within the swing) matters more than the
exact duration.

### Wanted — needed for later phases, not blocking

| Clip name | Loop | Notes |
|---|---|---|
| `sing` | No | The vocal blast: chest out, arms wide, head back. Riff's other attack |
| `summon` | No | Raises the lute overhead to call Sir Brass |
| `walk` | Yes | Slower locomotion for the Inn, where running looks wrong |
| `perform` | Yes | **The Tavern Encore.** Playing the lute to a crowd. This is the closing scene of the demo and the emotional payoff — worth more attention than any other clip here |
| `victory` | No | Short flourish on mission complete |

---

## 5. The Lute-Bludgeon

A separate `.glb`.

| Property | Value |
|---|---|
| Format | **`.glb`**, textures embedded |
| Length | **~1.4 m** overall. The concept calls for an oversized silhouette that reads at distance |
| Origin | **At the grip point** — where his right hand closes on the neck. Not at the body of the lute, not at the centre |
| Orientation | Neck pointing **+Y** (up) from the origin, body of the lute hanging **−Y** |
| Scale | Applied |

Origin placement is the part that matters. It becomes the pivot the weapon
rotates around when attached to his hand, so if it is in the wrong place the
swing arc will be wrong and no amount of tuning will fix it.

---

## 6. Where To Put The Files

```
godot/assets/characters/riff/riff_wilde.glb     ← mesh + rig + all animations
godot/assets/weapons/lute_bludgeon.glb          ← the weapon
```

Create the folders if they do not exist. Godot will import them automatically the
next time the editor opens; I will do the rest.

---

## 7. Licensing

Confirm the generation tool's terms allow **commercial use and redistribution**
of what you generate, then add a row to `docs/ASSET_REGISTER.md` before the files
are committed. Per `AGENT_RULES.md`, nothing is imported without a licence record.

---

## 8. Delivery Checklist

- [ ] `.glb`, single file, textures embedded
- [ ] ~2.0 m tall, origin between the feet, +Y up
- [ ] **All animations in place — root motion off**
- [ ] All eight required clips present and named as above
- [ ] Right hand bone exists for weapon attachment
- [ ] Lute is a separate `.glb` with its origin at the grip
- [ ] Licence recorded in `ASSET_REGISTER.md`

Drop the files in and tell me. I will read the bone names and clip list straight
out of the file with `tools/inspect_model.gd`, wire the weapon to the hand bone,
and match the animation timings to the existing combat windows.
