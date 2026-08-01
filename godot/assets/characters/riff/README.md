Riff Wilde's model goes here as `riff_wilde.glb`.

See `docs/CHARACTER_ASSET_SPEC.md` for the full contract. The three things that
are expensive to get wrong:

1. Animations must be IN PLACE — root motion off, or he will fight the physics.
2. Origin between the feet on the ground plane, not at the hips.
3. Mesh, rig and all clips in ONE .glb.
