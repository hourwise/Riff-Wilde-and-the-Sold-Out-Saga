# Character Asset Specification — Riff Wilde

Delivery contract for Riff's model, rig and his lute-bludgeon.

**This replaces the earlier generic-humanoid version.** The project's art direction
is now KayKit, and every character in the game shares one skeleton and draws from
one animation library. Riff should join that system rather than sit outside it.

---

## 1. The Opportunity — Read This First

Every KayKit character uses a skeleton called **`Rig_Medium`**: 23 bones, fixed
names. All animation ships separately in shared libraries — 22 melee clips,
movement, hit reactions, deaths, spawns.

**If Riff is rigged to that exact skeleton, he inherits the entire library for
free.** No animating attacks, runs, dodges, deaths by hand. He also moves in the
same idiom as the rest of the cast, which is what makes an ensemble read as one
game rather than a collection of assets.

The engine already does the assembly: `CharacterVisual.animation_libraries` merges
the clips onto any character at load. If your rig matches, Riff drops in with
**zero code changes**.

If it does not match, everything still works — but you are then hand-authoring
around a dozen clips, and he will not move like anyone else in the game.

---

## 2. The Rig — Match This Exactly

23 bones. Names are lower-case with `.l` / `.r` suffixes, exactly as written:

```
root
  hips
    spine
      chest
        upperarm.l → lowerarm.l → wrist.l → hand.l → handslot.l
        upperarm.r → lowerarm.r → wrist.r → hand.r → handslot.r
        head
    upperleg.l → lowerleg.l → foot.l → toes.l
    upperleg.r → lowerleg.r → foot.r → toes.r
```

Notes that matter:

- **`handslot.l` / `handslot.r`** are weapon mount points at the end of each hand
  chain. The lute attaches to `handslot.r`. Do not omit them.
- There is **no neck bone** — `head` parents directly to `chest`.
- There is a **`wrist`** between `lowerarm` and `hand`. Easy to miss.
- Bone *names* are what the animation tracks address. Hierarchy and rest pose
  should match too, or borrowed clips will deform oddly even with correct names.

**The reliable way to get this right:** download a KayKit character —
`assets/kaykit/adventurers/Characters/gltf/Barbarian.glb` is already in the repo —
open it in Blender, delete its mesh, and bind Riff to the skeleton that remains.
That guarantees an exact match rather than an approximate one.

If your tool cannot produce this and gives you its own rig, send it anyway and say
so. I can write a bone-name remap, though a differing hierarchy or rest pose may
still need retargeting in Blender.

---

## 3. Model

| Property | Value |
|---|---|
| Format | **`.glb`**, single file, textures embedded |
| Triangles | **6,000–9,000**. Sits with the cast: Barbarian 7,123, Skeleton_Warrior 5,934, Ranger 8,900. Do not go below ~5,000 — he would be lower detail than the enemies |
| Height | **~2.2 m** including hair, matching the Barbarian he replaces |
| Pose | A-pose or T-pose — not a posed stance |
| Facing | Either is fine. Correct it in-engine with one field (`model_yaw_degrees`); do not rebuild for it |
| Up axis | **+Y** |
| Origin | Between the feet on the ground plane, **not** at the hips |
| Scale | Applied |

**Style notes**, from the concept you picked:

- Keep the **faceted, hard-planed hair**. It is his silhouette and it is what makes
  him sit with KayKit. Do not smooth it.
- Keep the **broad shoulders and pauldrons**. Same reason.
- Keep the **smirk**. It is carrying the personality the character sheet describes.
- **Add a brighter accent somewhere.** He is maroon, black and brown, and the
  cemetery is dark blue-grey fog with warm torch pools. He risks disappearing into
  it. The magenta from the logo, or a warm-toned lute, would give him a "you are
  here" read at twenty metres.

Model him **without the lute** — it is a separate object.

---

## 4. Animation

**If the rig matches `Rig_Medium`: none needed.** He inherits:

| Need | Clip he inherits |
|---|---|
| Idle | `Idle_A` / `Idle_B` |
| Run / walk | `Running_A/B`, `Walking_A/B/C` |
| Attack chain | `Melee_2H_Attack_Chop`, `_Slice`, `_Spin`, `_Stab` |
| Dodge | `Jump_Full_Short` |
| Hit | `Hit_A` / `Hit_B` |
| Death | `Death_A` / `Death_B` |
| Spawn, interact, pick up, throw | available |

Anything Riff-specific is then a bonus rather than a requirement — a **`perform`**
loop for the Tavern Encore would be the one genuinely worth authoring, since it is
the closing scene of the demo and no library clip covers playing to a crowd.

**If you do author clips: in place, root motion OFF.** Riff is driven by velocity
in code; a clip that moves the root fights the physics and he will slide or drift.

---

## 5. The Lute-Bludgeon

A separate `.glb`.

| Property | Value |
|---|---|
| Format | `.glb`, textures embedded |
| Length | **~1.4 m**. Oversized on purpose — it must read at distance |
| Origin | **At the grip point**, where his right hand closes on the neck |
| Orientation | Neck +Y from the origin, body of the lute hanging −Y |
| Triangles | 1,500–3,000, budgeted separately from the character |

Origin placement is the part people get wrong. It becomes the pivot when the
weapon is attached to `handslot.r`, so if it sits at the lute's body or centre the
swing arc will be wrong and no tuning fixes it.

---

## 6. Where The Files Go

```
godot/assets/characters/riff/riff_wilde.glb
godot/assets/weapons/lute_bludgeon.glb
```

---

## 7. Delivery Checklist

- [ ] `.glb`, single file, textures embedded
- [ ] Rigged to `Rig_Medium` — 23 bones, names exactly as listed, `handslot.r` present
- [ ] 6,000–9,000 triangles
- [ ] ~2.2 m tall, origin between the feet, +Y up, A- or T-pose
- [ ] Faceted hair and pauldrons preserved; a bright accent added
- [ ] Lute is a separate `.glb` with its origin at the grip
- [ ] Any hand-authored clips are in place with root motion off
- [ ] Licence recorded in `docs/ASSET_REGISTER.md`

Drop the files in and tell me. I will read the bone names and clip list straight
out of the file with `tools/inspect_kaykit_rig.gd`, confirm the rig matches, wire
the lute to `handslot.r`, and set his scale from measurement rather than by eye.
