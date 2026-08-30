# Sci-Fi Football — implementation

Player-facing rules: [`RULES.md`](RULES.md). This file is for people (and later coding sessions) changing the game. **Trust this file and the tests over `RULES.md` if they disagree.**

Godot **4.3**. Main scene `res://scenes/main.tscn`. No autoloads; global types are `class_name` scripts.

```bash
# Play
~/.local/bin/godot --path /home/ivan/Projects/sci-fi-football

# Tests (headless SceneTree; no window)
~/.local/bin/godot --headless --path /home/ivan/Projects/sci-fi-football --script res://tests/run_tests.gd
```

---

## What this game is, in code

A **simultaneous-cycle** 11v11 grid football match:

1. Aether (home, cyan, attacks +x) queues up to 3 players × 6 AP.
2. Helix (away, magenta, attacks −x) queues up to 3 players × 6 AP.
3. `TurnResolver` applies both queues against the live board.
4. Repeat. A goal resets kickoff; the conceding side has the ball and plans first. Helix’s restart is the 180° of Aether’s 4-4-2. Vs-AI still preplans Helix invisibly and always leaves Aether in the chair — including after a Helix kickoff. Watch mode fills both sides from clones and never puts a human in the chair.

Nothing on the board moves during planning. The UI only **queues**. Resolution is the only place pieces, the ball, energy, and score change in a real match.

Tests often call `MatchModel.apply_*` directly, skipping the queue. That is intentional: mechanics are tested without the planner.

---

## Layering (why it is split this way)

```
scenes/main.tscn
  MatchController (Node2D, no class_name)   input, animation, hotseat / vs-AI / watch
    Pitch / PlayerPiece / BallPiece         drawing only
    MatchHUD / GameMenu                     CanvasLayer UI
    MatchModel                              authoritative state
      MatchRules                            pure constants + math
      Formation                             kickoff slots + role stats
      PlayerState / BallState               data (`in_flight` while a pass/shot travels)
      CombatLog                             text + fog-of-war
      TurnResolver                          cycle phases
      AiCoach                               sequence search + one-cycle plan-vs-plan
      AiSelfPlay                            independent both-sides fill + play_match
```

| Layer | Lives in | May do | Must not do |
|---|---|---|---|
| Rules | `match_rules.gd` | Geometry, dice, chance math | Touch players, RNG, nodes |
| Model | `match_model.gd` | Board, plans, apply one action | Draw, take input, know about HUD |
| Resolver | `turn_resolver.gd` | Order a cycle of plans | Invent new mechanics |
| Controller | `match_controller.gd` | Clicks, tweens, hotseat / vs-AI / watch | Reimplement legality |
| View | `pitch.gd`, `hud.gd`, pieces | Paint what the model already decided | Change match state |

`MatchModel` and friends extend `RefCounted`, not `Node`, so the headless suite can construct a match with no scene tree.

---

## File map

| Path | Role |
|---|---|
| `project.godot` | Name, 1280×720 maximized, main scene, Forward Plus, dark clear color |
| `scenes/main.tscn` | `Main` + `Pitch/Pieces/Ball` + `Camera2D` + `HUD` + `GameMenu` |
| `scenes/player.tscn` | Hex/shield piece: number + role labels |
| `scripts/match_rules.gd` | Grid, nets, offside, intercept geometry / reach, 1dSTAT, shot formula, tackle approach CTR bonus |
| `scripts/match_model.gd` | Kickoff, queries, queue, `pop_last_plan`, apply move/pass/swap/shoot/contest, `clone()` |
| `scripts/turn_resolver.gd` | Simultaneous cycle; phase order; destination clashes |
| `scripts/player_state.gd` | Id, team, role, pos, facing, printed + live stats, energy; `clone()` |
| `scripts/ball_state.gd` | `pos` + `carrier_id` (`-1` = loose); `clone()` |
| `scripts/formation.gd` | 4-4-2 kickoff coordinates and role stat table |
| `scripts/combat_log.gd` | Sequential log; plan lines hidden from the other team |
| `scripts/ai_coach.gd` | Sequence search generates joint-plan candidates; one-cycle plan-vs-plan picks argmax E[V] |
| `scripts/ai_self_play.gd` | Fill one side; independent both-sides fill from clones; headless `play_match` |
| `scripts/match_controller.gd` | Scene root: input, highlights, resolve playback, hotseat / vs-AI / watch |
| `scripts/pitch.gd` | Tile board, cell-snapped pitch markings, nets, highlights, plan arrows, pass lane |
| `scripts/player_piece.gd` | Piece look: hex (outfield), shield (GK), energy bar, facing chevron, gold ring |
| `scripts/ball_piece.gd` | Small gold disc; slightly smaller when carried |
| `scripts/hud.gd` | Built in code: banner, inspector, action bar, log, forecast |
| `scripts/game_menu.gd` | Title + pause + options; `PROCESS_MODE_ALWAYS` |
| `scripts/game_settings.gd` | `require_end_turn`, animation speed; `user://settings.cfg` |
| `tests/run_tests.gd` | Headless suite — the regression net |
| `tests/capture_preview.gd` | Optional PNGs of kickoff / selection |

HUD and menu widgets are created in `_build()`, not in the `.tscn`. Pitch markings are `_draw()` on `Pitch` (cell grid plus cell-snapped pitch markings: halfway on the column-13 border, centre circle radius 2.5 tiles, penalty area 4×11 cells, goal area 1×5 cells, penalty spots on cell centres, penalty / corner arcs, goal mouths matching the net tile).

---

## Coordinate system

Constants live on `MatchRules`.

- Pitch: **26×17**. `x` is goal-to-goal. `y` is touchline-to-touchline. That cell count is the FIFA 105×68 m ratio at length 26.
- `x = 0` is Aether’s goal line (left). `x = 25` is Helix’s (right).
- `y = 0` is the **top** of the screen = Aether’s left wing when attacking +x.
- Extra **goal tiles** sit off the rectangle: Aether net `(-1, 8)`, Helix net `(26, 8)`. Each net is one cell.
- `in_bounds` = pitch tile **or** a net. Cells like `(-1, 0)` are dead.
- Distance is **Chebyshev** `max(|dx|, |dy|)`. A move is exactly 1 (8 directions).
- Pass range is **Euclidean**: `MatchRules.in_pass_range` is cell-centre distance `<= PASS_RANGE` (5 tile lengths). The highlight is a circle, not a Chebyshev square.
- `PlayerState.facing` is one of those 8 dirs. Kickoff: Aether `(1, 0)`, Helix `(-1, 0)`. `PlayerState.relocate` writes facing from the step. `turn_facings` is the other 7 dirs. `turn_ap_cost` is 1 AP for 1–2 ring steps (45°/90°) and 2 AP for 3–4 (135°/180°). `action_ap_cost(..., facing)` needs the current facing for turns.
- `move_destinations(from, blocked, facing)` drops the one square **directly behind** `facing`. `facing == ZERO` skips that filter (geometry-only callers).
- `move_reach(from, facing, blocked, remaining_ap)` is every cell a cone-walk can hit by spending at most that many AP (no turns). Cells in `blocked` are **absorbing dests**: you can land on them, you cannot walk through them to a further tile. Values are `{cost, path}`.
- `move_reach_with_prefix_turns(...)` wraps that search with one leading turn of at most `MOVE_PREFIX_TURN_AP` (2): 1 AP for 45°/90°, 2 AP for 135°/180°. Values also carry `turn_dest` (`ZERO` if the cheapest path has no prefix turn). `MatchModel.move_reach` / `command_dests(..., "move")` use this with `teammate_cells` as absorbing dests. Opponents are omitted so the walk continues through them as if empty. A `queue_plan` move expands into that prefix turn (if any) plus the cheapest walk steps.
- `sprint_destinations(from, facing, occupied)` is the cell two tiles **straight ahead** of `facing`. An occupied **through** tile or out of bounds returns empty. An occupied **landing** is still a dest (resolve fights if they stay). Sprint is not a cone. AP cost is `SPRINT_AP_COST` (2) orthogonal or `SPRINT_DIAG_AP_COST` (3) diagonal; energy is `SPRINT_ENERGY_COST` (3) or `SPRINT_DIAG_ENERGY_COST` (5) on an empty landing. Occupied landings use contest energy via `apply_sprint` → `_apply_contest`. `MatchModel.valid_sprints` / `command_dests(..., "sprint")` use this. A sprint is one plan, not two walk steps.
- Back pass: `is_back_pass` is the rear cone, directly back ± `BACK_PASS_HALF_ANGLE_DEG` (43). Adjacent cells are never back passes.
- Keepers start **in the net**. From a net, `move_destinations` yields the **3** adjacent pitch tiles (diagonals + forward). The old goal-line square in front of the net is empty at kickoff.

World space (drawing only):

- `TILE_SIZE = 72`.
- Piece centre: `(cell + (0.5, 0.5)) * TILE_SIZE`.
- Grid pick: `floor(world / TILE_SIZE)`.
- **Intercept / shot math uses tile units**, not pixels. `MatchRules.tile_center(cell)` is `Vector2(cell)` (integer cell as float). `INTERCEPT_RADIUS = 0.7` tile. Pitch scales that by `TILE_SIZE` only when drawing the preview circle. Adjacent orthogonal cells sit 1.0 away, so they do not intercept an axis-aligned pass.

Halfway: integer `GRID_WIDTH / 2 = 13`. Aether’s opponent half is `x >= 13`. Helix’s is `x < 13`. Attacking third is 8 columns: Aether `x >= 18`, Helix `x < 8`.

Penalty “box” = the three **pitch** tiles adjacent to that net:

- Aether: `(0, 7) (0, 8) (0, 9)`
- Helix: `(25, 7) (25, 8) (25, 9)`

Shooting is legal from any in-bounds **pitch** tile whose unclamped hit chance is **≥ 5%** (`MatchRules.can_attempt_shot` / `SHOT_MIN_HIT`). Leftover AP counts. You cannot shoot from a net tile.

Hit chance is a 2-D Gaussian aimed at goal centre. Tile deltas convert to metres first (`TILE_M_X = 105/26`, `TILE_M_Y = 68/17`; a cell is not 1 m). Leftover AP multiplies ACC (`× (1 + 0.05 × leftover)` via `shot_accuracy`) before spray, so ACC 20 with 6 leftover aims as 26. Then `θw = (GOAL_W × max(COS_FLOOR, cos θ)) / max(d_m, D_MIN)`, `θh = GOAL_H / max(d_m, D_MIN)` (FIFA 7.32 × 2.44 **metres**), spray `σ = lerp(SIGMA_MAX_DEG, SIGMA_MIN_DEG, (ACC/100)^SIGMA_POWER)`, then `erf(θw / 2σ√2) × erf(θh / 2σ√2)`, clamped 5–98%. No leftover addend on hit. `shot_base_hit_chance` / `shot_hit_chance` take metres. Constants live on `MatchRules`.

---

## Kickoff and identities

`MatchModel.setup_kickoff(kicking_team)` **rebuilds** the 22 `PlayerState`s from `Formation.slots(team, kicking_team)`. Scores are **not** reset. Plans are cleared. RNG is **not** re-randomized (the stream continues so seeded clones / `play_match` stay reproducible after a goal). A new `MatchModel` randomizes once in `_init`. Combat log is **not** cleared — a goal just appends a header. `current_team` and `awaiting_other_side` reset so the kicking side plans first; the second `end_planning` of the cycle resolves.

Player ids are 0..21 in formation order (Aether 0–10, Helix 11–21). Lowest id wins some same-team ties.

`Formation` stores Aether’s kicking 4-4-2 (`_home`) and Helix’s receiving 4-4-2 (`_away`). When Helix kicks, both arrays are rotated 180° with `MatchRules.mirror_cell` (`x' = 25-x`, `y' = 16-y`).

| | Aether kicking | Helix kicking |
|---|---|---|
| Attack | +x | −x |
| Net | `(-1, 8)` | `(26, 8)` |
| Kicking #9 ST | `(12, 8)` `CENTER_SPOT` | `(13, 8)` `AWAY_SPOT` |
| Kicking other ST | `(12, 7)` | `(13, 9)` |
| Receiving #9 ST | `(14, 11)` `AWAY_KICKOFF` | `(11, 5)` (mirror of `AWAY_KICKOFF`) |
| Receiving other ST | `(14, 5)` | `(11, 11)` |

Default kickoff: Aether #9 has the ball. After a goal, `_award_goal` calls `setup_kickoff(opposite_team(scorer))` so the **conceding** side starts with the ball and `current_team`.

Two players never share a cell. `setup_kickoff` asserts uniqueness, that the ball is held, and that no receiving player starts inside the centre circle (`MatchRules.in_centre_circle`, radius `CENTRE_CIRCLE_R` = 2.5 tiles, same as the drawn marking). On the circle line is outside.

Role stats: `Formation.base_stats`. Printed ACC/DEF/CTR/STA. Every role has **STA 10**. ST 20/10/15; LCM/RCM and LB/RB 10/15/15; LM/RM 15/10/10; LCB/RCB and GK 10/20/20. Energy pool = `STA * 10` (100 at kickoff), starts full. Live stats:

```
factor = 0.5 + 0.5 * (energy / max_energy)
live   = max(1, round(printed * factor))
```

Empty energy **halves** the printed number (rounded), it does not zero it. Each **resolved** action costs 1 energy (`_finish_action` / a few goal paths), except **sprint** which costs 3 orthogonal or 5 diagonally (`sprint_energy_cost`) and **dribble / tackle / square fight** which cost 5 (`CONTEST_ENERGY_COST`). Cancelled actions do not spend. A kickoff rebuild refills everyone.

---

## Possession

The ball is either on a player (`carrier_id >= 0`, that player’s `has_ball == true`) or loose (`carrier_id == -1`). Always go through `_give_ball` / `_release_ball` so those two fields stay in sync.

Walking onto a loose ball takes it. Walking the ball onto the **opponent net** is a goal (`_carrier_in_opponent_net`). You cannot pass into an **empty** net; you can pass to a keeper standing in their own net.

---

## Planning vs resolving

### Queue

`home_plans` / `away_plans`: arrays of dictionaries.

```
{
  player_id, team, action, dest, target_id, origin, label,
  ap_index,       # sequence of this action for this player (0, 1, …)
  ap_cost,        # 2 ortho / 3 diagonal / 2 sprint / 1–2 turn / 1 pass / leftover for shoot
  ap_end,         # cumulative AP after this action = resolve wave (1..6)
  ap_left,        # remaining AP before this action (shot ACC bonus)
  expects_ball    # true if this pass/shoot/dribble is planned off a pass or a collect
  expects_reason  # "pass did not arrive" or "did not get the ball"
}
```

Action ids: `move`, `sprint`, `turn`, `pass`, `dribble`, `tackle`, `challenge` (UI: Fight), `swap`, `shoot`, `done`.

Rules of a queue:

- Many plans per player, capped by leftover AP. `queue_plan` appends. A `move` whose dest is more than one step away — or that needs a prefix turn to leave the cone — expands into that turn (if `turn_dest` is set) plus the cheapest cone-walk (`move_path`) and appends one plan per action; unreachable far dests return `{ok = false, reason = "illegal_dest"}`. `pop_last_plan(player_id)` removes that player’s last plan (or the last plan of `current_team` if `player_id < 0`) and drops that PLAN log line. Remaining plans for that player keep their `ap_index` / `ap_end`.
- At most `ACTIONS_PER_SIDE` (3) distinct players per team. A player who already has a plan can queue more until they spend 6 AP or queue `done`.
- `done` costs 0 AP, is planning-only (resolver skips it), and `can_queue` becomes false for that player. They still occupy an acting slot. Backspace pops Done (or their last action). Clicking them twice clears the plan, including Done.
- `can_select` / `can_queue` require `player.team == current_team` unless `ignore_team_gate`.
- `end_planning`: the first lock of a cycle (`awaiting_other_side` is false) flips `current_team` to the other side and returns `{action = "end_planning"}`. The second lock calls `TurnResolver.resolve`. After a Helix kickoff, Helix is first and Aether is second.

`ignore_team_gate` exists because `apply_*` still refuse the “wrong” team. The resolver sets it true so Helix actions can apply during a simultaneous cycle. Tests set it to poke Helix pieces during Aether’s turn.

### Planning-time possession

`has_ball` is the **real** board. `planning_carrier()` / `planning_has_ball()` walk the acting team’s queue so a player can already queue pass / shoot / dribble as if they will have the ball.

- Pass to an onside teammate: planning possession moves to that teammate (and can chain). An offside teammate does not get it.
- Pass to an empty square or an opponent’s square: planning possession ends, unless an **onside** teammate has queued a **move** or **sprint** onto that square — they collect it and can chain. A marked / offside collector does not. An opponent standing on the dest collects at resolve if they stay.
- Shoot: planning possession ends.
- Loose ball: the first queued **move** or **sprint** onto the ball’s cell collects it for planning, unless that player is marked from the last pass.
- Cycle detection: if a pass loop exists, stop.

The real ball never moves during planning. Resolve playback snaps pieces and the ball back to the pre-cycle snapshot, then plays the events.

`expects_ball` is set when the actor does **not** currently hold the ball but `planning_has_ball` is true. At resolve, if they still do not have it, the follow-up is cancelled (`"pass did not arrive"` after a teammate pass, `"did not get the ball"` after a collect) rather than `"lost the ball"`.

### Ending a side

- Default: filling **all leftover AP on 3 players**, or marking those players **Done**, auto-calls `end_planning` from the controller (`planning_complete()`).
- `End Turn` / Enter is always legal, including 0 actions (`can_end_planning()` is unconditionally true).
- Option `GameSettings.require_end_turn`: third action only queues; player must confirm.

---

## How one action is applied

The resolver never implements dribble/tackle itself. It calls model methods. **Stepping onto anyone still standing on the dest is always `apply_move`**, which dispatches. Occupied dests are legal to **queue** as `move` (and as `pass`); the contest happens at apply time if they have not left.

| Same team? | Mover has ball? | Occupant has ball? | Resulting `action` | Dice |
|---|---|---|---|---|
| yes | (any) | (any) | `challenge` | CTR vs CTR |
| no | yes | (any opponent) | `dribble` | mover CTR vs occupant DEF |
| no | no | yes | `tackle` | mover DEF vs occupant CTR |
| no | no | no | `challenge` | CTR vs CTR |

Win: dribble and square fight swap onto the square (loser shoved to origin). Same-team fights never steal — the carrier keeps the ball and it follows them. Dribble win keeps the ball. Tackle win steals in place — both stay put, the ball moves to the tackler, and the winner **faces away** from the player they stole from (`_face_away_from`). Dribble loss: stay put, occupant steals the ball. Tackle/fight loss: nothing changes. Dribble or tackle **numeric tie**: both stay put and the ball bounces to a random in-bounds cell of the 3×3 around its current tile (`MatchRules.bounce_cells`), including staying put. Occupied landings give that player the ball; empty landings leave it loose. Square-fight ties still use `attacker_wins_ties`. Each of these contests costs 5 energy on the acting player. A queued `move` that finds the dest empty is a normal 1-energy walk.

Tackle success is 1dDEF vs the carrier’s **angled CTR**. Approach angle (`MatchRules.tackle_direction`) is carrier facing vs the vector from the contested cell to the tackler. The carrier’s live CTR is multiplied by `1 + 0.25 × (angle / 45°)` (`MatchRules.tackle_angle_stat`): 0° front ×1, 45° ×1.25, 90° side ×1.5, 135° ×1.75, 180° back ×2. That boosted face is what both the dice and `contest_win_chance` use. Numeric ties still bounce. HUD `contest_preview` shows the boosted CTR and the chance.

Pass: `apply_pass_to(from_id, dest, instant=true)`. `_launch_flight` releases the ball and snapshots offside marks. Instant (tests) then `drain_flight()`. Resolver passes `instant=false` and drains after that wave’s movement. Intercepts are `_resolve_pass_intercepts` on the remaining lane against live positions; a steal `_give_ball`s the interceptor and clears marks. Arrival: offside if the occupant is marked, else give to whoever is standing there (teammate or opponent) or drop if empty. Passer does not move. Empty nets and the opponent net are still illegal pass dests. A later collect by a marked player (`apply_move` / `apply_sprint` onto a **collectable** loose ball, not an in-flight one) is also offside. Anyone else receiving the ball (`_give_ball`) clears the marks.

Sprint: `apply_sprint`. Two tiles straight ahead of facing. Through tile must be empty. Occupied landing calls `_apply_contest` (same dribble / tackle / square fight as a walk onto that player). Empty landing carries or collects the ball (dest or through) and costs 3 energy straight or 5 diagonally. Opponent net with the ball is a goal, same as a walk-in.

Swap: adjacent teammate only. Carrier keeps the ball and it follows them.

Shoot: `apply_shoot(player_id, remaining_ap, instant=true)`. Same launch/drain path as a pass with dest = opponent net (the keeper in the net is the dest occupant so they do not intercept). If stolen, interceptor cuts to the landing and takes the ball (`intercepted`, no hit roll). Else on arrival: hit roll against `shot_hit_chance` (Gaussian/erf with **+5% ACC per leftover AP**, clamped 5–98%), then optional keeper save (shooter 1dACC vs keeper 1dDEF, ties to shooter; ACC includes leftover). The shot spends every leftover AP and ends that player’s planning. Miss → loose on the goal tile. Save → keeper has the ball. Goal → `_award_goal` (rebuilds kickoff). `shot_preview.goal_chance` is `through × hit × (1 − save)`. Hovering the net with Shoot selected draws the pass lane and intercept circles.

### Dice

`1dSTAT`: `rng.randi_range(1, max(1, stat))`. Higher wins.

Dribble and tackle **numeric ties bounce** the ball (`tied` on the roll, `bounced` on the result). They do not use `attacker_wins_ties`. Other contests still go to **the team with the ball** (`MatchRules.attacker_wins_ties`):

- Attacker has the ball → attacker (pass-through, shot).
- Defender has the ball → defender (unused for dribble/tackle; those bounce).
- Same team, nobody has it → attacker (first claimer in clash code).
- Opposite, nobody has it → the side whose team currently possesses, else occupant.

`contest_win_chance` enumerates the `atk * def` outcomes so HUD percents match the dice, including the tie rule. Tackle previews feed the carrier’s angled CTR (`MatchRules.tackle_angle_stat`) into that same formula.

### Scripted outcomes (tests only)

On the model, left `null` in play:

- `scripted_attacker_wins`: bool — force contest winner; dice are faked so the log still reads `1dN=…`.
- `scripted_contest_tie`: bool — force a numeric tie (dribble/tackle bounce).
- `scripted_bounce_cell`: `Vector2i` — landing for that bounce; otherwise random among `bounce_cells`.
- `scripted_first_intercept_wins`: bool — first interceptor takes it, or passer beats **every** interceptor.
- `scripted_shot_outcome`: `"goal"` / `"save"` / `"miss"`.

Do not use these from game code.

---

## TurnResolver — cycle phases

`TurnResolver.resolve(model)` copies `home_plans + away_plans` into `remaining`, logs `── Resolve cycle N ──`, sets `ignore_team_gate`, then loops **six AP waves** (`ap_end` 1..6). An action plays in the wave equal to the cumulative AP spent when it completes. A 2-AP first step is wave 2; a 3-AP first step is wave 3; a second 2-AP step on the same player is wave 4. Empty waves are skipped. A 1-AP pass as a first action therefore **launches** in wave 1, **before** anyone’s 2-AP tackle; it then flies the **whole remaining path** after that wave’s movement.

Inside a wave:

1. **Tackles** (`tackle`) — lowest `player_id` first inside a phase.
2. **Ball** (`pass`, `shoot`) — not id order. Always play the **current carrier’s** pass/shot next, so a pass can feed another pass or a shot once the ball arrives. Launch only (`apply_pass_to` / `apply_shoot` with `instant = false`); the ball is `BallState.in_flight`. If the ball is still flying, other pass/shot plans wait. If it is not, applying them cancels `"lost the ball"` / the plan’s `expects_reason`.
3. **Dribbles**
4. **Square fights** (`challenge`)
5. **Destination contests** — remaining **moves and sprints** that share a dest:
   - Same team: 1dCTR, tie via `attacker_wins_ties` (ball / lower id). Losers cancelled `"lost the square fight"`. Winner stays in `remaining` for the move phase.
   - Opposite, one has the ball: treat as **tackle** (DEF vs CTR, same approach-angle CTR bonus as a step-on tackle, measured from the meeting square). Winner may steal and then faces away from the old carrier. A numeric tie bounces the ball and both stay put.
   - Opposite, neither has the ball: CTR vs CTR square fight. Winner also collects a loose ball on that tile if `apply_move` runs onto it.
6. **Moves, sprints, and swaps** — `apply_move` onto a still-occupied dest is the fight for the square.
7. **Flight** — `drain_flight()` the whole remaining path. Intercepts use the remaining lane against **live** `player.pos` after movement. `scripted_first_intercept_wins` applies to whoever is on that lane. Follow-up pass/shot plans of the new carrier play immediately in this same flight step (and also drain). After wave 6, `drain_flight()` is a safety net if anything is still in the air.

A result with `reset == true` (goal) **stops the cycle**. Leftover plans are cancelled `"play stopped — goal"`. Kickoff already ran inside `_award_goal`.

If no goal: leftover plans cancelled `"could not be completed"`, `current_team = HOME`, `turn_index += 1`. Always clears `awaiting_other_side` so the next cycle’s first lock is Aether (or the kicking side after a goal, already reset inside `setup_kickoff`).

Then both plan arrays clear and the gate is restored.

**Re-check legality at apply time.** Plans were aimed at the planning board. After earlier phases, dest may be illegal, the carrier may have lost the ball, a swap partner may have moved. `_apply_plan` cancels with a reason instead of forcing the action. If a player was shoved, the action is tried from the **new** tile (`valid_moves` / `can_pass_to_cell` use current `player.pos`).

Pass destinations stored as a teammate `target_id` are resolved to that player’s **current** cell, not the queued `dest`, so a moving receiver can still be found.

---

## Intercepts

Computed in **tile space**. Segment = passer / shooter tile centre → target tile centre. Shots reuse `interceptors_for_pass` / `_resolve_pass_intercepts` with dest = opponent net. An opponent intercepts if their 0.7-tile-radius circle touches the segment at `t > 0` (standing only next to the passer does not count; an adjacent orthogonal cell is 1.0 away and is out). Teammates and the intended receiver never intercept. A keeper standing in the net is that dest occupant, so they save rather than intercept.

Direct `apply_pass_to` / `apply_shoot` **drain** the whole path immediately (tests). `TurnResolver` launches (`instant = false`), then `drain_flight()` after that wave’s movement. A player who was off the lane when the pass was queued intercepts if they are in range when it flies — they stepped there in an earlier wave, or in this wave before flight. Too late if they arrive after the pass wave.

Order: increasing `t` along the lane. Each is passer **live ACC** vs interceptor **live DEF**, ties to the **passer** (ball team). Intercept chance is then multiplied by `reach = 1 / (1 + INTERCEPT_DIST_K * dist)` (`INTERCEPT_DIST_K = 1`, so 0.7 tiles off keeps `1/1.7`). First failure steals — interceptor must win the dice and pass the reach roll.

Landing: snap the closest point on the segment to a tile; if occupied, search nearby free tiles. Interceptor leaves their old cell empty.

`scripted_first_intercept_wins == false` means “beat every interceptor”, not “only beat the first”. It applies to shots as well as passes.

---

## Offside

Position check (`MatchRules.is_offside_position`): in opponent’s half, strictly nearer the opponent goal than the **ball/passer** cell, and fewer than two opponents as near that goal as the player (level counts as covering). Keeper counts. Level with the ball is onside.

A pass **launch** snapshots every teammate in an offside position (`offside_marked_ids`, `offside_passer_id`). Offside is called if a marked player is the next to play the ball: they occupy the pass dest, or they collect the loose ball later (`_take_loose_ball`). An onside teammate, opponent, interceptor, or the passer touching it first clears the marks (`_give_ball`). Kickoff clears them. Carrying, swapping, and collecting while unmarked are never offside. An intercept `_give_ball` clears the marks, so a stolen pass is not flagged.

`planning_carrier` does not hand the ball to an offside receiver or a marked collector, so they cannot queue follow-up pass/shoot/dribble.

Restart: closest opponent (Chebyshev, then lowest id) swaps onto the receiver’s tile and takes the ball.

---

## Combat log and hotseat fog

`CombatLog` stores `{kind, text, team?, hidden_from_opponent?}`.

Hidden from the opponent:

- `queue` events (PLAN lines)
- `note(..., team)` such as “AETHER locked in N actions.”

Public: resolution events, headers, phase titles.

Viewers:

- `VIEWER_ALL` (`-1`): everything (tests, debug, AI vs AI watch).
- `VIEWER_PUBLIC` (`-2`): hide all private lines. HUD uses this **while resolving** in hotseat / vs-AI.
- A team id: that team’s private lines + all public.

HUD during planning: viewer = `model.current_team`. Plan arrows (`pitch.set_plans`) and gold rings are **only** the acting team’s queue, including past cycles — you never see the other side’s arrows. Watch mode is the exception: both queues, `VIEWER_ALL`, and gold rings for both teams.

---

## Controller / UI

`match_controller.gd` is the scene root.

**Input**

- Left click cell → `handle_cell_clicked`.
- Right click adjacent cell of the selected player → queue `turn` (`handle_cell_right_clicked`). 1 AP up to 90°, 2 AP for 135°/180°. Otherwise cancel pending command, then deselect. Esc: cancel pending command, then deselect, then open pause menu.
- Backspace: `undo_last_action` → `pop_last_plan` of the selected player if they have a queued action, otherwise the last plan of the acting side. Selects that player and re-arms Move. No-op when the queue is empty.
- Enter / Space: `end_planning`. Space is taken in `_input` so a focused action button cannot steal it.
- 1–9 / keypad: Nth button currently shown in `commands_for` (not a fixed action map).

**Command-first UX.** Select a player → `_pending_action` defaults to `"move"` if they have a walk. After a queued action with AP remaining, Move is re-armed so consecutive tiles chain. Bottom bar lists only commands with at least one dest. Then click a highlighted tile → `action_for_command` → `queue_plan`. Move dests are the remaining-AP cone-walk plus tiles that a single prefix turn can open (`move_reach_with_prefix_turns`), **including occupied cells** (amber). Clicking a far tile queues that turn if needed, then each step on the cheapest path. Teammate cells are absorbing: you can land on them, you cannot walk through them. Opponent cells are dests and through-tiles (treated as empty for the walk). A pending-command dest wins over selecting a teammate — with Move armed, clicking an occupied teammate queues a walk onto them. Click a teammate who is not a dest, or cancel Move first, to select them instead. Pass dests are every in-range cell except empty nets and the opponent net, including squares an opponent occupies.

Why not “click the tile then pick Move/Pass”? One cell is often two actions (adjacent empty = move or pass; adjacent occupied = move, pass, contest, or swap; net = shoot and maybe move). The old chooser is still in the HUD (`show_choices`) and `_open_choice` still exists on the controller, but **nothing calls `_open_choice`**. Do not revive it without wiring; current tests assume command-then-tile.

Highlight colours (pitch): green walk, white turn, amber contest, blue pass, red offside (pass dest, flagged players, offside collect), purple swap (`choice_cells` reused for this), gold shot. Pass hover and Shoot-on-net hover share `set_pass_preview` (lane + intercept circles). Right-click queues a turn even when Move is armed (a 45° cell is both a walk and a turn).

Selecting a **planned** player twice clears their plan (`clear_plan`) so you can pick someone else before the third action locks.

**Resolve playback.** `animate_moves` is false on `headless` and in tests. When true, `_play_resolve` sets `busy`, walks `result.events`, tweens pieces/ball, then respawns on kickoff reset. `_resolve_generation` invalidates an in-flight tween if New Game is pressed mid-animation.

**Camera.** `_frame_camera` fits `pitch.world_rect()` (including both nets) into `hud.play_area()` — the rectangle left of the 308px log and between the top/bottom bars.

**Menu.** Title on first graphical launch (`open_title`, tree paused): NEW HOTSEAT, NEW VS AI, NEW AI vs AI, EXIT. Pause: Esc with nothing selected (RESUME / NEW GAME / OPTIONS / EXIT — no extra watch button). Options persist via `GameSettings` (`user://settings.cfg`) so New Game does not wipe them. `anim_scale()` = `5 / speed` (1 = slowest, 10 = fastest, 5 = original timing).

---

## Clone

`MatchModel.clone()` is a deep copy of authoritative match state. Name is `clone` everywhere (`PlayerState.clone`, `BallState.clone`).

Copied:

- `current_team`, `awaiting_other_side`, `turn_index`, `home_score`, `away_score`, `ignore_team_gate`
- `scripted_attacker_wins`, `scripted_contest_tie`, `scripted_bounce_cell`, `scripted_first_intercept_wins`, `scripted_shot_outcome`
- every `PlayerState` field listed on that type (new RefCounted per player)
- `BallState.pos` / `carrier_id` / `in_flight` and the flight fields (new RefCounted)
- `home_plans` / `away_plans` via `duplicate(true)`
- RNG `seed` **and** `state` (set seed first, then state)
- `offside_marked_ids` / `offside_passer_id`

Omitted: `combat_log` starts empty on the clone so search/eval stays cheap.

The clone is not the same RefCounted as the original. Mutating a clone player, queue, score, or RNG must not change the original. `queue_plan` / `apply_*` on the original still work after a clone was taken. `has_ball` still pairs with `ball.carrier_id`. Positions stay unique.

---

## AiSelfPlay

`scripts/ai_self_play.gd`, `class_name AiSelfPlay`, node-free.

- `fill_side(model)` — `AiCoach.fill_plans` for `model.current_team`. The coach does not peek at the other live queue.
- `fill_both_independently(live)` — clone the live board twice, clear plans on each copy, set `current_team` to HOME on one and AWAY on the other (`awaiting_other_side = false`), fill each independently, write `home_plans` / `away_plans` onto the live model (and PLAN log lines). One side’s dests cannot influence the other side’s scoring.
- `resolve_cycle(model)` — `TurnResolver.resolve`. Re-check legality stays in the resolver.
- `play_match(max_cycles = 40, seed = -1)` — new `MatchModel`, Aether kickoff, optional `rng.seed` after kickoff, then loop fill-both + resolve. Always runs `max_cycles` resolves (a goal reset still counts as a cycle; two sequence-search coaches may never score). No scene tree, no HUD, no tweens. Returns `{ home_score, away_score, cycles, seed, terminated = "cycles", carrier_id, ball_pos, turn_index, holder_pos }`. `seed < 0` means “leave the model’s randomized stream”. Dice are real RNG; `scripted_*` still work on clones.

Do not switch vs-AI over to `play_match`. Vs-AI still preplans Helix on the live board and leaves Aether in the chair.

---

## Controller modes

Flags on the controller, not the model. Do not overload `vs_ai = true` to mean both AIs.

| Call | `vs_ai` | `ai_vs_ai` |
|---|---|---|
| `start_hotseat()` | false | false |
| `start_vs_ai()` | true | false |
| `start_ai_vs_ai()` | false | true |

`start_new_game()` rebuilds Aether kickoff and **keeps** the current flags (pause NEW GAME restarts the same mode).

**Vs-AI** — human is always Aether. On each cycle `_begin_vs_ai_cycle` → `_preplan_ai`:

1. `current_team = AWAY`
2. `AiSelfPlay.fill_side(model)` — sequence search plus one-cycle plan-vs-plan, up to 3 players, avoids stacking dests when it can
3. `current_team = HOME`

Helix therefore commits **before** Aether queues, on the current board, without seeing Aether’s plans. That matches simultaneous play. (In hotseat Helix plans second, but also cannot see Aether’s arrows/log.)

When Aether `end_planning`s, the controller immediately `end_planning`s again (Helix is already filled) so the player does not sit through a Helix turn. After a Helix kickoff, vs-AI still preplans Helix, marks Helix as already locked (`awaiting_other_side`), and puts Aether in the chair. Helix arrows stay hidden. Aether’s End Turn is the second lock of the cycle and resolves immediately. Clicks are ignored only as a safety net if `current_team` is ever AWAY in vs-AI.

**Watch (`ai_vs_ai`)** — spectator. Human never queues: clicks, action hotkeys, End Turn, and undo return `{ok = false, reason = "watching"}`. Esc still opens pause. Cycle:

1. `fill_both_independently` from a clone of the current board
2. `TurnResolver.resolve` on the live model
3. If `animate_moves`: `_play_resolve`, then chain the next cycle after playback (same `_resolve_generation` token as vs-AI)
4. If `animate_moves` is false (headless / tests): **do not** auto-chain. Tests call `step_ai_vs_ai_cycle()` (one fill+resolve) or `fill_ai_vs_ai_plans()` (fill only, so `_plan_markers()` can see both teams)

After a goal, `setup_kickoff` already ran inside the model. Watch fills **both** sides for that kickoff; it does not use the vs-AI “Helix locked, Aether plans” shortcut. Plan arrows, gold rings, and PLAN log lines use both teams (`CombatLog.VIEWER_ALL`). Action bar / End Turn are hidden. Hint: “Watching AI vs AI — Esc for menu.” Animation speed still applies to resolve playback. `require_end_turn` is irrelevant while watching.

`AiCoach.fill_plans(model)` is still the only planner entry (`AiSelfPlay.fill_side` / vs-AI / watch all call it). It **generates** joint plans with the sequence beam, then **chooses** among a handful by playing them against a belief over the opponent’s simultaneous queue. Search is plans vs plans, not a tree of primitive AP moves. It never reads the other side’s live `home_plans` / `away_plans`.

**Generate** (on clones of a snapshot, both plan arrays cleared so leftover live queues cannot leak; `current_team` is us; `awaiting_other_side = false`; already-queued *our* prefix is restored so a pre-queued pass can still feed a shot):

1. For each eligible player, beam remaining-AP sequences (width 6, 8 expansions per node). The first actor is the ball carrier when they can still queue; otherwise the 5 players nearest the ball. Candidates come from `commands_for` / `command_dests` / `action_for_command` so a new action that is wired there is searched without a beam change. Pass dests are pruned to teammates plus a few forward empty squares. `done` is not expanded. A prefix that has already reached the opponent net is not expanded further.
2. Rank a prefix by summed 1-ply `_score` plus `_prefix_bonus` (ball progress, xG if the actor can shoot, shape / GK stay-home).
3. Commit the best sequence among players, then search again on the updated queue so a pass can feed the next actor’s shot. Dest clashes among committed sequences are penalised.
4. Unknown action ids use `_score_generic` (forward gain / toward the ball). Add a `_score` match arm for the new action to play well. If the action relocates the piece, `planning_pos` / `planning_facing` must walk it or later AP is aimed from the old tile.

Π_us (about 4–8 joint plans, duplicates skipped by the set of `(player_id, action, dest, ap_end)`): default sequence fill; 2nd-best first sequence from that same first beam (no second 3-player fill); ban the default first actor by dropping their plans from the default joint plan (full re-fill only if that would leave nothing); cheap “shoot / walk-in now” if the carrier can. Empty is **not** committed for us (Helix in vs-AI must still queue) but **is** in the opponent belief. At most **3** full sequence fills for us. Π_them (2–3): their default sequence fill from the snapshot board and the empty plan. A third variant only if it reuses a fill already ran. At most **2** full sequence fills for them. Opponent belief is generated from the snapshot, never from live plans the other side already queued.

**Choose:** for each π_us, for each π_them, for N=2 dice samples: clone the snapshot, write the two queues (`duplicate(true)` plan dicts), `TurnResolver.resolve` on that clone, add `V(clone, us)`. Score is the average. Tie-break: default sequence fill, then more AP spent, then lower first player_id. Copy the winner onto the **live** model (append plan dicts + PLAN log lines). Live `current_team` stays us. Do not lock / `end_planning` / resolve. Dice use the clone’s RNG (seed+state copied by `clone()`, then `randi()` per extra sample). Do not roll `live.rng`.

**V(s)** after resolve, us-perspective, live positions (not `planning_*`):

- `10000 * (our_score - their_score)`
- If that resolve awarded a goal (`reset` / score change): return the goal term plus a small kickoff-shape term. Do not search past the kickoff rebuild.
- `18 * ball_progress` (our attack direction; 0 if they hold it; half if loose, using `ball.pos`)
- `400 * best_xG_we_could_take_now` (max `shot_preview.goal_chance` among our players who `can_attempt_shot` from live pos with leftover AP 0)
- `−300 * best_xG_they_could_take_now`
- `8 * (our_energy_sum - their_energy_sum) / 100`
- Shape: CBs/GK Chebyshev to `Formation.slots(team, team)` home cells; penalty if GK is out of our net
- `−40` if two relocating dests in queued π_us shared a cell

Weights are named constants on the coach (`_W_SCORE`, `_W_BALL`, `_W_XG_US`, `_W_XG_THEM`, `_W_ENERGY`, `_W_SHAPE`, `_W_GK_OUT`, `_W_DEST_CLASH`). This is step 2’s hand-written position eval; do not train it. Live stats only; do not parse the combat log. Helpers: `_evaluate_position`, `_rollout`, `_our_candidates` / `_their_belief`. Do not new a Node or add autoloads.

1-ply `_score` (rough): shoot ≫ walk-in goal ≫ through-pass with forward gain (plus receiver xG) ≫ tackle ≫ dribble ≫ collect loose ball ≫ move toward ball / forward. Offside passes are heavily penalised. First sequence of a side uses a very low keep-threshold so the coach always tries to queue at least one thing. Budget: worst case ~5 sequence fills + ~12 resolves per `fill_plans`. Reuse one probe per beam the way `_beam_player` already does.

---

## Result dictionaries

Almost every public function returns `{ok, action, ...}`. The log formatter and the tween code both switch on `action`. Keep these keys stable:

| `action` | Meaning |
|---|---|
| `queue` | Plan stored; board unchanged |
| `pop_plan` | Last queued action removed; PLAN log line dropped |
| `end_planning` | Side locked; other team to move |
| `resolve` | Cycle done; `events` is the playback list |
| `move` / `sprint` / `dribble` / `tackle` / `challenge` / `swap` / `pass` / `shoot` / `offside` / `clash` | Applied |
| `cancelled` | Plan dropped; `reason` / `reason_text` |

Useful flags: `contest_won`, `contest_tied`, `bounced`, `bounce_cell`, `gained_possession`, `lost_possession`, `intercepted`, `goal`, `reset`, `hit`, `saved`, `expects_ball` (on the plan, not the event), `displaced_id` (shove/swap partner), `player_id` / `defender_id` / `receiver_id`. Tackles also carry `angle_deg` / `angle_bonus` / `angle_label`. A steal may set `facing` on the winner’s result so playback does not use the step direction.

If you add an action, update: `commands_for`, `command_dests`, `TurnResolver._apply_plan` + phase lists, `CombatLog.format_result`, controller `_present_result` / highlights, `AiCoach._score`, and tests. Sequence search enumerates `commands_for` automatically; `_score` still needs a case (or it uses `_score_generic`). Relocating actions must be listed in `planning_pos` / `planning_facing`. `sprint` is a 2-tile facing-only step: queue as one plan, resolve in the movement phase, clash with moves that share its dest.

`AiSelfPlay.play_match` returns a different dict (not an action result): `home_score`, `away_score`, `cycles`, `seed`, `terminated` (`"cycles"` when the cap is hit), plus `carrier_id`, `ball_pos`, `turn_index`, `holder_pos` for replay asserts. Keep action keys on apply/queue/resolve results stable.

---

## Tests

`tests/run_tests.gd` extends `SceneTree`, `call_deferred("_run")`, `quit(0|1)`.

It covers rules math, kickoff, contests, dribble/tackle bounce, tackle approach angle, AP waves, pass/intercept/offside (including delayed first-touch after a through ball)/shoot (including shot intercepts), full-flight intercepts against live positions (same-wave and earlier-wave steps onto the lane; later-wave arrivals too late), full plan→resolve sequences (tackle-then-pass cancel, pass-then-move carry, ground-pass collect, arrival tackles, empty end-turn), controller clicks, menu/settings, vs-AI preplan, `MatchModel.clone` isolation, independent both-sides fill, seeded `play_match`, AI vs AI watch, sequence-search candidates / pass-then-shot, plan-vs-plan no-peek / suicide-dribble / empty-belief walk-in.

Controller tests instantiate `main.tscn`, set `animate_moves = false`, and often `queue_free()` the instance. They reach into HUD private fields (`_end_turn`, `_forecast`) — ugly but load-bearing.

When you change a rule, **add or extend a test in the same file**. Prefer `scripted_*` over seeding RNG.

`tests/capture_preview.gd` is a manual screenshot helper (`/tmp/sci-fi-football/*.png`), not part of the suite.

---

## Invariants (break these and something subtle dies)

1. **Model is truth.** Visual positions are synced from `PlayerState.pos` in `_refresh` except during a tween. After a tween, `_refresh` / `_spawn_visuals` snap back.
2. **Never two players on one cell.** Dribble and square-fight wins swap; a won tackle steals in place; intercepts refuse occupied landings; a queued move onto an occupied cell becomes that contest at apply time. Planning occupancy does not block dests. Opponent occupancy does not absorb a cone-walk; teammates still do.
3. **`has_ball` and `ball.carrier_id` stay paired.** Only `_give_ball` / `_release_ball`.
4. **Planning does not mutate the board.** If a click moves a piece immediately, you bypassed `queue_plan`.
5. **Resolver is the only multi-action path.** Phase order is the design. Do not “just apply plans in queue order”.
6. **Pass range and move range are different.** Move = 1. Pass = Euclidean radius `PASS_RANGE` (5 tile lengths, cell centre to cell centre). Adjacent empty/teammate is a chooser in the **model** (`actions_for`), a command pick in the **UI**.
7. **Live stats for dice and previews.** Always `live_accuracy()` etc., never the printed field, except when showing `ACC 10 (13)`.
8. **Fog is a view filter**, not deleted data. `as_text()` with no args still contains PLAN lines.
9. **`clone()` is a deep copy.** New player/ball RefCounteds, duplicated plans, copied RNG seed+state. Combat log omitted (empty).
10. **Headless watch does not auto-chain** the next fill+resolve. Graphical watch chains only after `_play_resolve` finishes.
11. **`AiCoach` does not peek.** Search copies clear both plan arrays; opponent belief is generated from the snapshot board. Poisoned `away_plans` must not change a HOME fill. Generate on clones; write the winner onto live at the end. Never `TurnResolver.resolve` the live model for search.

---

## Not implemented (do not pretend they exist)

- Fouls, cards, clock, extra time, named set pieces beyond kickoff.
- Pass inaccuracy other than intercepts (a non-intercepted pass always arrives).
- Substitutions, stamina recovery, injuries.
- Network play. Hotseat is same-machine; vs-AI is local sequence-search Helix vs human Aether; AI vs AI is two copies of that coach with a spectator.
- A learned position value (stage 3). Step 2 is one-cycle plan-vs-plan with a hand-written `V(s)`. Vs-AI human is still Aether.

---

## Where to edit, by job

| You want to… | Start here |
|---|---|
| Change grid size, pass range, energy, AP pool, move costs, sprint costs, turn costs, shot curve, intercept radius / reach, tackle angle CTR bonus | `MatchRules` constants + tests |
| Change kickoff shape or role stats | `Formation` |
| Change when an action is legal to **queue** | `MatchModel.command_dests` / `can_plan_*` |
| Change what an action **does** | `MatchModel.apply_*` |
| Change simultaneous order / clash rules | `TurnResolver` |
| Change Helix / watch-coach personality | `AiCoach._score` / `_prefix_bonus` / `_evaluate_position` / beam and V constants |
| Run self-play / watch mode | `ai_self_play.gd` / `match_controller.gd` (`start_ai_vs_ai`, `step_ai_vs_ai_cycle`) |
| Change click / hotkey / animation | `match_controller.gd` |
| Change look of the board or pieces | `pitch.gd` / `player_piece.gd` |
| Change HUD chrome | `hud.gd` `_build*` |
| Persist a new option | `GameSettings` + `GameMenu` options panel |

After a rules change, run the headless suite before considering it done.

A feature is not done until the docs match. Full checklist: [`_README_FIRST.md` — Adding a feature](_README_FIRST.md#adding-a-feature). Player-visible behaviour → [`RULES.md`](RULES.md). File map / phases / result keys / invariants → this file. Session gotchas → [`_README_FIRST.md`](_README_FIRST.md). Same change, not a follow-up.
