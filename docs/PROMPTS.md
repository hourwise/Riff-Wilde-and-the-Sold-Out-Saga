# Agent Prompts

Reusable prompt templates for coding agents working on this project.

---

## New Feature Prompt

```
Add [FEATURE] to the Riff Wilde vertical slice.

Context:
- This is a Godot 4.x project using strictly typed GDScript.
- The project lives at godot/ with autoloads in godot/scripts/autoload/.
- Use signals for decoupled communication.
- Store data in Resources, not hard-coded in scripts.
- Follow the existing patterns in the codebase.

Requirements:
1. [requirement 1]
2. [requirement 2]
3. [requirement 3]

After implementation:
- List all files changed.
- Explain how to test manually in Godot.
- Update docs/TEST_PLAN.md with the new test case.
```

## Bug Fix Prompt

```
Fix [BUG] in the Riff Wilde vertical slice.

Reproduction steps:
1. [step 1]
2. [step 2]
3. Observe [unexpected behavior]

Expected behavior: [what should happen]

Context:
- Godot 4.x, strictly typed GDScript.
- Review the relevant scripts before making changes.
- Do not rename public APIs, signals, or autoloads.
```

## Asset Import Prompt

```
Import [ASSET NAME] from [SOURCE].

Before importing:
- Verify licence allows modification and commercial use.
- Add entry to docs/ASSET_REGISTER.md.
- Confirm file format is .glb or .gltf for 3D, .ogg for audio.

After importing:
- Place assets in the appropriate godot/assets/ subfolder.
- Create any necessary .tscn wrappers.
- List files changed.
```
