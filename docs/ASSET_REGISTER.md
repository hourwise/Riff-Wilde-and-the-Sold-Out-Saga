# Asset Register

Track every external asset imported into the project. Update this file before adding any new asset.

| Asset Name | Creator | Source URL | Licence | Modification Allowed? | Commercial Use Allowed? | Redistribution in Repo? | Notes |
|---|---|---|---|---|---|---|---|
| Kenney Furniture Kit | Kenney | https://kenney.nl | CC0 / Licence (see godot/License.txt) | Yes | Yes | Yes | Tables, chairs, bookshelves, couch, plant |
| Animated Monster Pack | @Quaternius | (local) | See godot/Animated Monster Pack by @Quaternius/License.txt | Yes | Yes | Yes | Placeholder enemy models |
| Easy Animated Enemy Pack | (Jan 2019) | (local) | See godot/Easy Animated Enemy Pack - Jan 2019/License.txt | Yes | Yes | Yes | Placeholder enemy models |
| Ultimate Modular Ruins Pack | (Aug 2021) | (local) | TBD | Yes | TBD | TBD | Environment pieces for levels |
| Blockbench models (axe, barrel, pickaxe, shield, sword) | TBD | (local bbmodel/) | TBD | Yes | TBD | TBD | Weapon/prop placeholders |
| RPG Characters (Nov 2020) | Quaternius | https://quaternius.com | CC0 | Yes | Yes | Yes | 6 rigged characters, 32-joint humanoid rigs, ~5k tris, 11-15 animations each including attack, roll, hit reaction and death. Warrior is Riff's stand-in; the rest become Inn NPCs. glTF is self-contained (embedded buffers and textures). |
| Ultimate Monsters | Quaternius | https://quaternius.com | CC0 | Yes | Yes | Yes | 50 rigged monsters, self-contained glTF. Ghost_Skull earmarked for Sir Brass. |
| KayKit (Skeletons 1.1, Adventurers 2.0, Character Animations 1.1, Dungeon 1.1, Forest Nature 1.0, Halloween Bits 1.0, Fantasy Weapons 1.0) | Kay Lousberg | https://kaylousberg.com | CC0 | Yes | Yes | Yes | Primary art direction. Characters share one Rig_Medium skeleton and draw from shared animation libraries (General, MovementBasic, CombatMelee), so the whole cast moves from one motion set. Character .glb embed their textures; prop .gltf reference textures by relative path, so folder structure must be preserved on import. |
| Riff Wilde (character + 20 animations) | Commissioned by the project team, generated with Meshy AI | https://meshy.ai | Owned by the project (Meshy paid-plan output) | Yes | Yes | Yes | The player character and his own motion set, on his own rig — not the KayKit `Rig_Medium`. Animations ship as separate .glb sharing that rig; they are stripped of the duplicated mesh and 4K textures (551 MB → 1.3 MB) but **must retain their `skins` array**, or Godot imports them as plain node chains and every track silently fails to resolve. Guarded by `smoke_test_phase2.gd`. |
| The Choirmaster (character + 19 animations) | Commissioned by the project team, generated with Meshy AI | https://meshy.ai | Owned by the project (Meshy paid-plan output) | Yes | Yes | Yes | The mini boss, on the same rig family as Riff and deliberately taller (2.10 m against his 1.25 m). Stripped from 566 MB to 1.4 MB with `tools/strip_animation_glb.py`, skins retained. Note that Meshy names the clip *inside* each file after its own source rather than after the file: `Walking.glb` contains `walking_man`. Check with `tools/inspect_model.gd` rather than assuming. |
| Open E guitar chord hit (Freesound #246288) | afleetingspeck | https://freesound.org/s/246288/ | **UNCONFIRMED — see note** | Yes | TBD | TBD | `riff_strike_impact_01.wav`, the lute connecting. Trimmed from 3.12s to 0.50s with `tools/trim_sound.py` and peak-normalised to -1 dBFS. **Freesound licences vary per upload — CC0, CC-BY and CC-BY-NC all appear on the site. This needs checking on the sound's page before release: CC-BY requires crediting "afleetingspeck" in the game's credits, and CC-BY-NC would make it unusable in a commercial release.** |
| Graveyard Kit (5.0) | Kenney | https://kenney.nl/assets/graveyard-kit | CC0 1.0 (see godot/assets/environment/graveyard-kit/License.txt) | Yes | Yes | Yes | 90 GLB models. Cemetery environment for the vertical slice: Funeral Altars (`altar-stone`, `altar-wood`), crypts, gravestones, iron fences, fire baskets, lightposts. Character meshes are static (no rig). |

## Instructions

- Every asset must have a row in this table **before** it is imported into the Godot project.
- If licence terms are unclear, do not import the asset until confirmed.
- Paid assets must not be committed to the public repo unless the licence explicitly allows redistribution.
- Keep original licence files alongside the asset files in the project.
