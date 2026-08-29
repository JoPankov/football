# Sci-Fi Football — read this first

This is the onboarding note for a new coding session. It is **not** the rules bible and **not** the implementation map. Those are:

| File | Audience | Use it for |
|---|---|---|
| **This file** | Agents and new sessions | What the game is, how the repo is layered, how to run it, how to add a feature, what not to break |
| [`RULES.md`](RULES.md) | Players | How a match feels to play. Geometry must match `MatchRules` |
| [`IMPLEMENTATION.md`](IMPLEMENTATION.md) | People changing the game | File map, phase order, result dictionaries, invariants, where to edit |

**Truth order when they disagree:** `scripts/` + `tests/run_tests.gd` > `IMPLEMENTATION.md` > `RULES.md`.

Godot **4.3**. GDScript. No autoloads. Shared types are `class_name` scripts. Model objects extend `RefCounted`, not `Node`, so the headless suite can construct a match without a scene tree.

```bash
# Play
~/.local/bin/godot --path /home/ivan/Projects/sci-fi-football

# Tests (headless SceneTree; no window)
~/.local/bin/godot --headless --path /home/ivan/Projects/sci-fi-football --script res://tests/run_tests.gd
```

After a rules change, run the suite before considering it done. Prefer adding a test in `tests/run_tests.gd` in the same change. Prefer `scripted_*` flags on `MatchModel` over seeding RNG.

---

## Adding a feature

A feature is not done when the code runs. The same change must include a test and the docs that describe the new behaviour. Do not leave a “docs later” note.

### Code

1. Edit the layer that owns the behaviour ([Where to edit, by job](#where-to-edit-by-job)). Keep legality in the model, dice math in `MatchRules`, cycle order in `TurnResolver`.
2. Add or extend a test in `tests/run_tests.gd` in the same change. Prefer `scripted_*` flags on `MatchModel` over seeding RNG.
3. Run the headless suite. If you add an **action**, also update `commands_for`, `command_dests`, `TurnResolver` phases, `CombatLog.format_result`, controller highlights / playback, and `AiCoach._score`. `done` is planning-only: skip it in the resolver.

### Docs (same change, not a follow-up)

| File | Update it when… | Write for… |
|---|---|---|
| [`RULES.md`](RULES.md) | The match **feels different to play**: a new action, a changed cost / range / formula, kickoff, highlights, turn flow, or a change to what is or is not implemented | Players. No file names, no function names. Geometry must match `MatchRules` — do not leave a new drift row |
| [`IMPLEMENTATION.md`](IMPLEMENTATION.md) | The **code map** changed: new file, new `action` key, new phase, new invariant, new result flag, new “where to edit” job, or a RULES drift you just fixed | People changing the game |
| **This file** | A later session would get it wrong without the note: mental model, layering, planning UX, geometry gotchas, invariants, file map, or this checklist | Agents and new sessions |

Skip a file only when that audience cannot be affected. A HUD colour tweak does not need `RULES.md`. A new contest type needs all three.

If you implement something listed under “not implemented”, delete that item from every doc that lists it. If `RULES.md` is wrong, fix it in the same change — do not leave a drift note instead of updating the player doc.

Truth order is unchanged: `scripts/` + tests > `IMPLEMENTATION.md` > `RULES.md`. The point of this checklist is to stop that order from being necessary.

---

## Pushing to GitHub (PAT)

Remote is HTTPS: `https://github.com/JoPankov/football.git` (`origin`). Default branch is `main`. Username is `JoPankov`.

When the user pastes a **personal access token** and asks to push, do it in **one** shell command. Do not try a token-less `git push origin` first — that fails and wastes a round trip. Do not assume `GH_TOKEN` / `PAT` already exists in the environment.

- Do **not** store the token in the remote URL, `git config`, a file, or the repo.
- Do **not** echo the token in commit messages, logs, or chat.
- Do **not** remind the user to revoke it. They issue short-lived tokens and revoke them themselves.

Working recipe (export, push, unset, then fetch so `origin/main` catches up — a URL push does not update tracking refs):

```bash
export GH_TOKEN='<token from the user message>'
GIT_TERMINAL_PROMPT=0 git -c credential.helper= push "https://JoPankov:${GH_TOKEN}@github.com/JoPankov/football.git" HEAD:main
unset GH_TOKEN
git fetch origin
```

`GIT_TERMINAL_PROMPT=0` and `-c credential.helper=` stop git from hanging on a credentials prompt. Classic or fine-grained PATs both work as the password on HTTPS. Scope needs `repo` (classic) or Contents + Metadata on this repository (fine-grained).

If `origin` is already ahead/behind, say so before pushing. Do not force-push `main` unless the user asked. Confirm with `git status -sb` that local `main` matches `origin/main`.

---

## What this game is

A **turn-based, simultaneous-cycle, 11v11 grid football** match with a sci-fi skin. It is not a real-time football sim, not a board-game port of a licensed ruleset, and not networked.

Two sides:

- **Aether** — home, cyan, attacks **+x** (left → right). Human plays Aether in hotseat and vs-AI.
- **Helix** — away, magenta, attacks **−x**. A second hotseat player, or a local greedy `AiCoach`.

Pitch: **26×17** tiles plus **two extra goal tiles** outside the rectangle: Aether net `(-1, 8)`, Helix net `(26, 8)`. Keepers start in the net. Distance is **Chebyshev** (`max(|dx|, |dy|)`). Facing is one of the 8 directions.

Each cycle:

1. Aether **queues** up to **3 players**, **6 action points** each. Nothing on the board moves.
2. Helix does the same (in vs-AI, Helix is pre-planned *before* Aether queues, still without seeing Aether’s plans). Watch mode (`NEW AI vs AI`) fills both sides from clones of the same board; the human never queues.
3. `TurnResolver` applies both queues in **six AP waves**. An action plays in the wave equal to the cumulative AP spent when it finishes: a 2-AP first step is wave 2, a later 2-AP step on the same player is wave 4, a 3-AP first step is wave 3. Empty waves do nothing. Inside a wave: turns, tackles, passes/shots, dribbles, square fights, destination clashes, then moves/sprints/swaps. Straight steps cost 2 AP, diagonal 3 AP. Sprint is 2 tiles ahead of facing: 2 AP / 3 energy straight, 3 AP / 5 energy diagonally. A turn costs 1 AP up to 90° and 2 AP for 135°/180°. A shot spends leftover AP for +5% ACC each and ends that player’s turn. A tackle or dribble that rolls a **numeric tie** bounces the ball to a random cell of the 3×3 around it (including staying put). Tackle success is DEF vs CTR minus an approach-angle penalty vs the carrier’s facing (front 0, 45° −15pp, side −30pp, 135° −50pp, back −85pp). A player who steals with a tackle keeps their tile, takes the ball, and then faces away from the old carrier.
4. Repeat. A goal rebuilds kickoff; the conceding side has the ball and plans first. Helix’s restart is the 180° of Aether’s 4-4-2. Vs-AI still preplans Helix invisibly and always leaves Aether in the chair — including after a Helix kickoff.

The UI only **queues**. Resolution is the only place pieces, the ball, energy, and score change in a real match. Tests often call `MatchModel.apply_*` directly and skip the queue — that is intentional.

There is no clock, no fouls, no substitutions, no pass inaccuracy other than intercepts. Aether AI exists only for watch and self-play (the same greedy `AiCoach` as Helix). Vs-AI still puts a human on Aether.

---

## Mental model (keep this or you will implement the wrong thing)

```
scenes/main.tscn
  MatchController (Node2D, no class_name)   input, animation, hotseat / vs-AI / watch
    Pitch / PlayerPiece / BallPiece         drawing only
    MatchHUD / GameMenu                     CanvasLayer UI (built in code)
    MatchModel                              authoritative state
      MatchRules                            pure constants + math
      Formation                             kickoff slots + role stats
      PlayerState / BallState               data
      CombatLog                             text + fog-of-war
      TurnResolver                          cycle phases
      AiCoach                               greedy one-side planner
      AiSelfPlay                            clone both-sides fill + play_match
```

| Layer | May do | Must not do |
|---|---|---|
| `MatchRules` | Geometry, dice math, chance formulas | Touch players, RNG, nodes |
| `MatchModel` | Board, plans, apply one action | Draw, take input, know about HUD |
| `TurnResolver` | Order a cycle of already-queued plans | Invent new mechanics |
| Controller | Clicks, tweens, modes | Reimplement legality |
| View | Paint what the model already decided | Change match state |

If a click moves a piece immediately, you bypassed `queue_plan`. If you “just apply plans in queue order”, you skipped the resolver.

---

## Planning, not moving

- Command-first UX: select a player, pick an action (Move is armed by default and stays armed after a walk), click a highlighted tile. Move highlights every empty cell a leftover-AP cone-walk can still reach, including after one prefix turn (1 AP up to 90°, 2 AP for 135°/180°) — clicking a far green tile queues that turn if needed, then every step on the cheapest path. Right-click an adjacent cell to turn toward it without picking Turn. Backspace pops the last queued action of the selected player, or this side’s last action if they have none / nobody is selected. One cell is often two actions (adjacent empty = move or pass; adjacent teammate = pass or swap; net = shoot and maybe move). Do not revive the old tile-then-chooser without wiring; tests assume command-then-tile.
- A player’s queued actions are an array, not a single slot. `ap_spent` = sum of each plan’s `ap_cost`. Cap is `PLAYER_ACTION_POINTS` (6). Orthogonal steps cost 2, diagonal 3, sprint 2 AP / 3 energy straight or 3 AP / 5 energy diagonally, pass 1, turn 1 AP up to 90° or 2 AP for 135°/180°. A shot costs every leftover AP. Cap on distinct acting players is `ACTIONS_PER_SIDE` (3).
- `planning_pos` / `planning_facing` / `planning_has_ball` walk the acting team’s queue so the second AP, a pass-fed teammate, and a player who steps onto a loose ball can be planned against the *intended* board. The real `PlayerState.pos` / `has_ball` do not change until resolve. If they never actually get the ball, those follow-up actions are cancelled.
- Filling all 6 AP on 3 players, or marking those players **Done**, auto-ends the side unless `GameSettings.require_end_turn`. Done costs 0 AP, occupies an acting slot, and blocks further queues for that player. End Turn / Enter / Space is always legal, including 0 actions.
- Hotseat fog: plan arrows, gold rings, and PLAN log lines are visible only to the team that queued them. Resolution events are public.

Action ids in code: `move`, `sprint`, `turn`, `pass`, `dribble`, `tackle`, `challenge` (UI: Fight), `swap`, `shoot`, `done`.

---

## Geometry agents get wrong

Constants live on `MatchRules`. Pitch is **26×17**; do not hardcode 13-row / 9-tall leftovers from older commits.

- `x = 0` is Aether’s goal line (left of screen). `x = 25` is Helix’s. `y = 0` is the **top** touchline = Aether’s left wing.
- Nets are playable (`in_bounds`). Cells like `(-1, 0)` are dead. From a net the keeper has **3** steps onto the pitch (forward + both diagonals).
- Halfway is `GRID_WIDTH / 2 = 13`. Aether’s opponent half is `x >= 13`. Helix’s is `x < 13`.
- Penalty box = the three **pitch** tiles adjacent to that net: Aether `(0, 7) (0, 8) (0, 9)`, Helix `(25, 7) (25, 8) (25, 9)`. Shooting is allowed from any pitch tile whose unclamped hit chance is **≥ 5%** (`MatchRules.can_attempt_shot`). Hit is a 2-D Gaussian in the FIFA goal mouth (7.32 × 2.44 **m**). Convert tile deltas with `TILE_M_X` / `TILE_M_Y` (105×68 m pitch on the 26×17 grid) before that math — do not treat 1 tile as 1 m. Leftover AP adds after. You cannot shoot from a net tile.
- Move = 1 tile into the **3-cell cone** (facing ± 45°). The Move highlight is every empty cell a cone-walk can still reach with leftover AP, including after one prefix turn (1 AP up to 90°, 2 AP for 135°/180°). Turns are not inserted mid-walk. Sprint = 2 tiles **straight ahead** of facing (not the cone), 2 AP / 3 energy straight or 3 AP / 5 energy diagonally, both through and landing empty. Turn faces any of the other 7 directions: 45°/90° cost 1 AP, 135°/180° cost 2 AP. Pass range = Euclidean radius 5 tile lengths (cell centre to cell centre), not into the rear cone except adjacent cells.
- Kickoff: Aether #9 ST on `CENTER_SPOT` `(12, 8)` with the ball. Helix #9 on `AWAY_KICKOFF` `(14, 11)` when receiving, outside the centre circle. When Helix kicks, that 4-4-2 is rotated 180° (`AWAY_SPOT` `(13, 8)` with the ball). The receiving team starts in its own half and outside the centre circle. Two players never share a cell.
- Intercept and shot math use **tile units**, not pixels. `MatchRules.tile_center(cell)` is `Vector2(cell)`. `INTERCEPT_RADIUS = 0.7` tile. Adjacent orthogonal cells sit 1.0 away, so they do not intercept an axis-aligned pass. `TILE_SIZE = 72` is drawing only. Shots use the same intercept lane as passes (`interceptors_for_pass` with dest = opponent net). The keeper in the net does not intercept; they save if the ball arrives.
- Live stats, not printed stats, go to dice and HUD percents. Empty energy **halves** ACC/DEF/CTR; it does not zero them.
- Offside is snapshotted **when the pass is played**, not when someone later reaches the ball. `offside_marked_ids` holds teammates who were offside at that moment. The first of those to play the ball is flagged; any other first touch clears the list. Do not re-check `is_offside_position` at collect time.

When in doubt, read `MatchRules` and the tests.

---

## File map (short)

| Path | Role |
|---|---|
| `project.godot` | Name, 1280×720 maximized, main scene, Forward Plus |
| `scenes/main.tscn` | `Main` + pitch + camera + HUD + menu |
| `scripts/match_rules.gd` | Grid, nets, facing, offside, intercepts, 1dSTAT, shot formula |
| `scripts/match_model.gd` | Kickoff, queries, queue, `apply_*`, `clone()` |
| `scripts/turn_resolver.gd` | Waves + phase order + destination clashes |
| `scripts/formation.gd` | 4-4-2 slots and role stat table |
| `scripts/player_state.gd` / `ball_state.gd` | Data. Both have `clone()`. Ball: `carrier_id == -1` means loose |
| `scripts/combat_log.gd` | Sequential log; plan lines hidden from the other team |
| `scripts/ai_coach.gd` | Greedy one-side planner (Helix in vs-AI; both sides in watch/self-play) |
| `scripts/ai_self_play.gd` | Independent both-sides fill from clones; headless `play_match` |
| `scripts/match_controller.gd` | Scene root. Hotseat / vs-AI / AI vs AI watch |
| `scripts/pitch.gd` / `player_piece.gd` / `ball_piece.gd` | Drawing |
| `scripts/hud.gd` / `game_menu.gd` / `game_settings.gd` | UI chrome; settings in `user://settings.cfg` |
| `tests/run_tests.gd` | The regression net. Extend this file; do not start a second suite |
| `tests/capture_preview.gd` | Manual screenshots, not part of the suite |

HUD and menu widgets are created in `_build()`, not in the `.tscn`. Pitch markings are `_draw()` on `Pitch` (FIFA-style lines snapped to cell borders; spots sit on cell centres).

---

## Invariants (break these and something subtle dies)

1. **Model is truth.** Visual positions snap back from `PlayerState.pos` after a tween.
2. **Never two players on one cell.** Dribble and square-fight wins swap; a won tackle steals in place; intercepts refuse occupied landings; walking onto a teammate is illegal (use swap).
3. **`has_ball` and `ball.carrier_id` stay paired.** Only `_give_ball` / `_release_ball`.
4. **Planning does not mutate the board.**
5. **Resolver is the only multi-action path.** Phase order is the design.
6. **Pass range and move range are different.** Move = 1. Pass = Euclidean radius 5.
7. **Dice use live stats** (`live_accuracy()` etc.).
8. **Fog is a view filter**, not deleted data. `CombatLog.as_text()` with no args still contains PLAN lines.
9. **Almost every public function returns `{ok, action, ...}`.** The log formatter and the tween code switch on `action`. Keep those keys stable. If you add an action, update `commands_for`, `command_dests`, `TurnResolver` phases, `CombatLog.format_result`, controller highlights / playback, `AiCoach._score`, and tests. `done` is planning-only: skip it in the resolver. `sprint` is one 2-tile plan, not two `move` steps.
10. **`MatchModel.clone()` is a deep copy.** Players, ball, plans, RNG seed+state, and scripted flags are independent. Combat log starts empty on the clone. Mutating the clone must not change the original.
11. **Headless watch must not auto-chain.** `animate_moves == false` runs at most one fill+resolve when tests call `step_ai_vs_ai_cycle()`. Graphical watch chains the next cycle only after `_play_resolve` finishes.

---

## Where to edit, by job

| You want to… | Start here |
|---|---|
| Grid size, pass range, energy, shot curve, intercept radius / reach, facing cones, turn costs | `MatchRules` + tests |
| Kickoff shape or role stats | `Formation` |
| When an action is legal to **queue** | `MatchModel.command_dests` / `can_plan_*` / `can_queue` |
| What an action **does** | `MatchModel.apply_*` |
| Simultaneous order / clash rules | `TurnResolver` |
| Helix / watch-coach personality | `AiCoach._score` |
| Run self-play / watch mode | `ai_self_play.gd` / `match_controller.gd` (`start_ai_vs_ai`, `step_ai_vs_ai_cycle`) |
| Click / hotkey / animation | `match_controller.gd` |
| Board or piece look | `pitch.gd` / `player_piece.gd` |
| HUD chrome | `hud.gd` `_build*` |
| Persist a new option | `GameSettings` + `GameMenu` options panel |

Do not pretend fouls, a clock, named set pieces beyond kickoff, substitutions, injuries, stamina recovery, or network play exist. Do not make `AiCoach` smarter in a plumbing change. Vs-AI is still human Aether + greedy Helix; watch/self-play is two greedy coaches.

---

## Stale comments you will meet

A few file headers still talk about “up to 3 actions” from before 6-AP planning. The live caps are `ACTIONS_PER_SIDE = 3` players and `PLAYER_ACTION_POINTS = 6`. Trust the constants and `TurnResolver.resolve`, not the oldest sentence in a script.
