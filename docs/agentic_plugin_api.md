# Agentic Plugin API (Skills)

Community members can extend the AI with **skills** — self‑contained GDScript
units that teach the agent new tricks without touching the core. This is
**Phase 5.5** of Agentic Mode.

---

## Concepts

A skill extends `AgenticSkill` (`scripts/agentic/skills/agentic_skill.gd`),
registers with `AgenticManager`, and can:

- **Request a telemetry snapshot** — `request_snapshot()`
- **Send a prompt to the LLM** — `send_prompt(system, user)` (reply delivered to
  `on_llm_response(text)`)
- **Apply control overrides** — `play_maneuver(maneuver, label)` engages the AI
  co‑pilot (clamped + safety‑guarded like the core)
- **Spawn UI** — `spawn_ui(control)` adds a `Control` to the shared agentic
  overlay `CanvasLayer`

All of these route through `AgenticManager`, so skills inherit the same
non‑blocking HTTP, throttling, control clamping and safety‑disengage guarantees
as the built‑in features.

---

## Writing a skill

1. Copy `scripts/agentic/skills/skill_template.gd`.
2. Rename the class and file (snake_case).
3. Set `id`, `display_name`, `description` in `_init()`.
4. Override the hooks you need.

```gdscript
class_name MySkill
extends AgenticSkill

func _init() -> void:
    id = &"my_skill"
    display_name = "My Skill"
    description = "Does something clever."

func invoke() -> void:
    var snap := request_snapshot()
    send_prompt("You are a helpful RC assistant.",
        "Telemetry: " + AgenticUtils.snapshot_to_prompt_text(snap))

func on_llm_response(text: String) -> void:
    print(text)  # speak it, show UI, or play a maneuver
```

### Lifecycle hooks

| Hook | When |
|------|------|
| `setup(host)` | On registration (always `super()` first; stores `manager`) |
| `teardown()` | On unregister / shutdown |
| `on_snapshot(snapshot)` | After a snapshot you requested |
| `on_llm_response(text)` | After the LLM replies to your `send_prompt()` |
| `invoke()` *(optional)* | Called by `AgenticManager.invoke_skill(id)` |

---

## Registering & invoking

```gdscript
AgenticManager.register_skill(MySkill.new())   # returns false if id taken
AgenticManager.invoke_skill(&"my_skill")        # runs invoke()
AgenticManager.get_skill(&"my_skill")           # -> AgenticSkill or null
AgenticManager.list_skills()                    # -> Array[AgenticSkill]
AgenticManager.unregister_skill(&"my_skill")
```

The two built‑in skills are registered automatically at startup.

---

## Built‑in skills

### Smoke Writer (`smoke_writer_skill.gd`)
Asks the LLM for a maneuver keyframe sequence that traces a shape in the sky and
hands it to the co‑pilot:

```gdscript
(AgenticManager.get_skill(&"smoke_writer") as SmokeWriterSkill).draw("a big loop")
```

### Formation Trainer (`formation_trainer_skill.gd`)
Coaches the pilot to hold a slot behind a lead aircraft. `evaluate(trainee,
lead)` returns a concise local correction (pure, unit‑testable); `coach()` can
ask the LLM to phrase it more richly.

```gdscript
var ft := AgenticManager.get_skill(&"formation_trainer") as FormationTrainerSkill
var tip := ft.evaluate(my_pos, lead_pos)   # e.g. "Hold the slot: drop back, slide left."
```

---

## Guidelines

- **Keep logic testable.** Put any non‑trivial maths/parsing in pure static
  functions (ideally in `AgenticUtils`) and unit‑test them in `tests/`.
- **Stay non‑blocking.** Never call the network directly — use `send_prompt()`.
- **Be safe.** Control overrides are always clamped and the co‑pilot disengages
  on dangerous attitudes or any human stick input; don't try to bypass this.
- **Degrade gracefully.** Skills should no‑op cleanly when the LLM is offline
  (the helper methods return `false`).

Example skill ideas: *Competition Judge*, *Spot‑Landing Coach*, *Wind Caller*.
