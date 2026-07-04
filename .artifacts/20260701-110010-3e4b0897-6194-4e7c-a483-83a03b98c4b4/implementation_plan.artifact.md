# Fix for Enemy Health/Armor Bar Alignment Bug

This plan addresses the issue where enemy health and armor bars "duplicate" or "float away" from their backgrounds when the camera moves. This was caused by individual quads billboarding independently while being offset in 3D space.

## Proposed Changes

### Combat UI Components

#### [NEW] [status_bar.gdshader](file:///D:/Users/fleur/Game Build/godot/shaders/status_bar.gdshader)
- Create a simple spatial shader that renders both background and fill on a single quad.
- Uses the `vertex` function to handle billboarding for the entire quad as a single unit.
- Uses `UV.x` to clip the fill color based on a `progress` uniform.

#### [EnemyStatusBars.gd](file:///D:/Users/fleur/Game Build/godot/scripts/enemies/EnemyStatusBars.gd)
- Refactor to use one `MeshInstance3D` per bar instead of two.
- Apply the new `status_bar.gdshader` to these quads.
- Simplify `_set_fill` to just update the `progress` uniform on the shader material.
- Remove the code that manually scales and shifts the fill quads, eliminating the alignment issues.

## Verification Plan

### Manual Verification
- **Visual Check:** Run the `PrototypeArena.tscn` and move the camera around the Tone Deaf and Ironclad Warden enemies.
- **Alignment Test:** Ensure the health and armor bars stay perfectly contained within their borders regardless of camera angle or distance.
- **Functionality Check:** Attack enemies and verify that the bars still drain correctly (Health for all, Armor for Warden).
- **Armor Break Check:** Verify the Warden's armor bar still disappears correctly when broken.
