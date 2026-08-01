# Contributing

This is currently a solo project. These guidelines exist to maintain consistency and prepare for potential collaborators.

## Development Workflow

1. Pick an issue from GitHub Projects / Issues.
2. Create a feature branch from `main`: `feature/short-description`.
3. Implement changes in small, testable commits.
4. Open a pull request — even if you're the sole reviewer.
5. After merge, delete the feature branch.

## Code Style

- **Language:** Strictly typed GDScript.
- **Naming:**
  - `PascalCase` for classes, nodes, and scenes.
  - `snake_case` for functions, variables, and signals.
  - `UPPER_SNAKE_CASE` for constants.
- **Comments:** Document _why_, not _what_. The code should be self-explanatory for the _what_.
- **Signals:** Use signals for decoupled communication between systems (combat events, state changes, UI updates).
- **Resources:** Store data in Godot `Resource` files where practical; avoid hard-coding stats inside scene scripts.

## Testing

- Every new system must include a manual test scenario described in `docs/TEST_PLAN.md`.
- Before merging, run the project and verify the test scenario passes.
- Automated unit tests go in `godot/tests/unit/`.

## Commit Messages

Use conventional commits:
- `feat:` new feature
- `fix:` bug fix
- `refactor:` code restructuring
- `docs:` documentation
- `test:` adding or updating tests
- `chore:` build, CI, or tooling
