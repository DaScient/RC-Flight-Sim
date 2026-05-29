# Contributing to RC-Flight-Sim

Thank you for considering a contribution to **RC-Flight-Sim**! This is a community-driven,
open-source project and every contribution – code, art, documentation, or bug reports –
is valued and appreciated.

---

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Ways to Contribute](#ways-to-contribute)
3. [Development Workflow](#development-workflow)
4. [Coding Standards](#coding-standards)
5. [Pull Request Checklist](#pull-request-checklist)
6. [Reporting Bugs](#reporting-bugs)
7. [Requesting Features](#requesting-features)
8. [License](#license)

---

## Code of Conduct

Be respectful. We follow the [Contributor Covenant](https://www.contributor-covenant.org/) v2.1.  
Harassment, discrimination, or personal attacks will not be tolerated.

---

## Ways to Contribute

| Area | What to do |
|------|-----------|
| **Bug fixes** | Open an issue, then a PR with the fix |
| **New aircraft** | Follow [docs/aircraft_creation.md](../docs/aircraft_creation.md) |
| **New sceneries** | Follow [docs/scenery_creation.md](../docs/scenery_creation.md) |
| **Physics improvements** | Discuss in an issue first (may touch core architecture) |
| **UI / UX** | Open a feature request, then submit a PR |
| **Documentation** | PRs welcome – fix typos, add examples, improve clarity |
| **Translations** | Add a `.po` file under `godot_project/locale/` |

---

## Development Workflow

1. **Fork** the repository on GitHub.
2. **Clone** your fork: `git clone https://github.com/YOUR_USER/RC-Flight-Sim.git`
3. Create a **feature branch**: `git checkout -b feature/my-new-thing`
4. Make your changes and commit with clear, concise messages.
5. **Push** the branch: `git push origin feature/my-new-thing`
6. Open a **Pull Request** against `main`.

> **Never commit directly to `main`.**

---

## Coding Standards

### GDScript

- Use **static typing** where possible: `var speed: float = 10.0`.
- Follow Godot's [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).
- File names: `snake_case.gd`, class names: `PascalCase`.
- Every exported public function must have a `## docstring` comment.
- No magic numbers – define named constants at the top of the file.

### C++ (GDExtension)

- Follow the [Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html).
- Use smart pointers (`std::unique_ptr`, `std::shared_ptr`), no raw `new/delete`.
- Prefer `const&` parameters for non-trivial types.
- All public methods must be documented with Doxygen-style comments.

### Scene Files

- Use descriptive node names (`MainCamera`, not `Camera3D2`).
- Group related nodes under named `Node3D` parents.
- Avoid deeply nesting more than 5 levels.

---

## Pull Request Checklist

Before submitting your PR, verify:

- [ ] Code follows the style guide.
- [ ] No debug `print()` statements left in production paths.
- [ ] New aircraft/sceneries include a README and a screenshot.
- [ ] All exported variables have a `@export` docstring.
- [ ] CI passes (GitHub Actions build workflow).
- [ ] PR description clearly explains *what* changed and *why*.

---

## Reporting Bugs

Use the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md) issue template. Include:

1. Godot version and OS.
2. Controller type (if input-related).
3. Steps to reproduce.
4. Expected vs actual behaviour.
5. Log output from the Godot console.

---

## Requesting Features

Use the [Feature Request](.github/ISSUE_TEMPLATE/feature_request.md) template. Explain:

1. The problem the feature solves.
2. How it fits the project's design pillars.
3. Any implementation ideas or references.

---

## License

- **Code** (`.gd`, `.cpp`, `.h`, `.py`, `.yml`, etc.): MIT License.
- **Art assets** (models, textures, sounds): CC0 or CC-BY-SA 4.0 – please specify in a
  companion `LICENSE.txt` in the asset folder.
- By contributing you agree that your contribution will be licensed under the same terms.
