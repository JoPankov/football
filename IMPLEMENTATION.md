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
4. Repeat. A goal resets kickoff; the conceding side has the ball and plans first. Helix’s restart is the 180° of Aether’s 4-4-2. Vs-AI still preplans Helix invisibly and always leaves Aether in the chair — including after a Helix kickoff.

Nothing on the board moves during planning. The UI only **queues**. Resolution is the only place pieces, the ball, energy, and score change in a real match.

Tests often call `MatchModel.apply_*` directly, skipping the queue. That is intentional: mechanics are tested without the planner.

---

## Layering (why it is split this way)

```
scenes/main.tscn
  MatchController (Node2D, no class_name)   input, animation, mode
    Pitch / PlayerPiece / BallPiece         drawing only
    MatchHUD / GameMenu                     CanvasLayer UI
    MatchModel                              authoritative state
      MatchRules                            pure constants + math
      Formation                             kickoff slots + role stats
      PlayerState / BallState               data
      CombatLog                             text + fog-of-war
      TurnResolver                          cycle phases
      AiCoach                               greedy Helix planner
```

| Layer | Lives in | May do | Must not do |
|---|---|---|---|
| Rules | `match_rules.gd` | Geometry, dice, chance math | Touch players, RNG, nodes |
| Model | `match_model.gd` | Board, plans, apply one action | Draw, take input, know about HUD |
| Resolver | `turn_resolver.gd` | Order a cycle of plans | Invent new mechanics |
| Controller | `match_controller.gd` | Clicks, tweens, vs-AI / hotseat | Reimplement legality |
| View | `pitch.gd`, `hud.gd`, pieces | Paint what the model already decided | Change match state |

`MatchModel` and friends extend `RefCounted`, not `Node`, so the headless suite can construct a match with no scene tree.

---

## File map

| Path | Role |
|---|---|
| `project.godot` | Name, 1280×720, main scene, Forward Plus, dark clear color |
| `scenes/main.tscn` | `Main` + `Pitch/Pieces/Ball` + `Camera2D` + `HUD` + `GameMenu` |
| `scenes/player.tscn` | Hex/shield piece: number + role labels |
| `scripts/match_rules.gd` | Grid, nets, offside, intercept geometry / reach, 1dSTAT, shot formula, tackle approach angle |
| `scripts/match_model.gd` | Kickoff, queries, queue, `pop_last_plan`, apply move/pass/swap/shoot/contest |
| `scripts/turn_resolver.gd` | Simultaneous cycle; phase order; destination clashes |
| `scripts/player_state.gd` | Id, team, role, pos, facing, printed + live stats, energy |
| `scripts/ball_state.gd` | `pos` + `carrier_id` (`-1` = loose) |
| `scripts/formation.gd` | 4-4-2 kickoff coordinates and role stat table |
| `scripts/combat_log.gd` | Sequential log; plan lines hidden from the other team |
| `scripts/ai_coach.gd` | Greedy Helix: score legal actions, queue up to 3 |
| `scripts/match_controller.gd` | Scene root: input, highlights, resolve playback, modes |
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
- Back pass: `is_back_pass` is the rear cone, directly back ± `BACK_PASS_HALF_ANGLE_DEG` (43). Adjacent cells are never back passes.
- Keepers start **in the net**. From a net, `move_destinations` yields the **3** adjacent pitch tiles (diagonals + forward). The old goal-line square in front of the net is empty at kickoff.

World space (drawing only):

- `TILE_SIZE = 72`.
- Piece centre: `(cell + (0.5, 0.5)) * TILE_SIZE`.
- Grid pick: `floor(world / TILE_SIZE)`.
- **Intercept / shot math uses tile units**, not pixels. `MatchRules.tile_center(cell)` is `Vector2(cell)` (integer cell as float). `INTERCEPT_RADIUS = 1.0` tile. Pitch scales that by `TILE_SIZE` only when drawing the preview circle.

Halfway: integer `GRID_WIDTH / 2 = 13`. Aether’s opponent half is `x >= 13`. Helix’s is `x < 13`. Attacking third is 8 columns: Aether `x >= 18`, Helix `x < 8`.

Penalty “box” = the three **pitch** tiles adjacent to that net:

- Aether: `(0, 7) (0, 8) (0, 9)`
- Helix: `(25, 7) (25, 8) (25, 9)`

Shooting is legal from any in-bounds **pitch** tile whose unclamped hit chance is **≥ 5%** (`MatchRules.can_attempt_shot` / `SHOT_MIN_HIT`). Leftover AP counts. You cannot shoot from a net tile.

Hit chance is a 2-D Gaussian aimed at goal centre. Tile deltas convert to metres first (`TILE_M_X = 105/26`, `TILE_M_Y = 68/17`; a cell is not 1 m). Then `θw = (GOAL_W × max(COS_FLOOR, cos θ)) / max(d_m, D_MIN)`, `θh = GOAL_H / max(d_m, D_MIN)` (FIFA 7.32 × 2.44 **metres**), spray `σ = lerp(SIGMA_MAX_DEG, SIGMA_MIN_DEG, (ACC/100)^SIGMA_POWER)`, then `erf(θw / 2σ√2) × erf(θh / 2σ√2)`. Clamp that base to 5–98%, then add leftover AP (`+3pp` each), clamp again. `shot_base_hit_chance` / `shot_hit_chance` take metres. Constants live on `MatchRules`.

---

## Kickoff and identities

`MatchModel.setup_kickoff(kicking_team)` **rebuilds** the 22 `PlayerState`s from `Formation.slots(team, kicking_team)`. Scores are **not** reset. Plans are cleared. RNG is re-randomized. Combat log is **not** cleared — a goal just appends a header. `current_team` and `awaiting_other_side` reset so the kicking side plans first; the second `end_planning` of the cycle resolves.

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

Empty energy **halves** the printed number (rounded), it does not zero it. Each **resolved** action costs 1 energy (`_finish_action` / a few goal paths). Cancelled actions do not spend. A kickoff rebuild refills everyone.

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
  ap_cost,        # 2 ortho / 3 diagonal / 1–2 turn / 1 pass / leftover for shoot
  ap_end,         # cumulative AP after this action = resolve wave (1..6)
  ap_left,        # remaining AP before this action (shot hit bonus)
  expects_ball    # true if this pass/shoot/dribble is planned off a pass or a collect
  expects_reason  # "pass did not arrive" or "did not get the ball"
}
```

Action ids: `move`, `turn`, `pass`, `dribble`, `tackle`, `challenge` (UI: Fight), `swap`, `shoot`, `done`.

Rules of a queue:

- Many plans per player, capped by leftover AP. `queue_plan` appends. `pop_last_plan(player_id)` removes that player’s last plan (or the last plan of `current_team` if `player_id < 0`) and drops that PLAN log line. Remaining plans for that player keep their `ap_index` / `ap_end`.
- At most `ACTIONS_PER_SIDE` (3) distinct players per team. A player who already has a plan can queue more until they spend 6 AP or queue `done`.
- `done` costs 0 AP, is planning-only (resolver skips it), and `can_queue` becomes false for that player. They still occupy an acting slot. Backspace pops Done (or their last action). Clicking them twice clears the plan, including Done.
- `can_select` / `can_queue` require `player.team == current_team` unless `ignore_team_gate`.
- `end_planning`: the first lock of a cycle (`awaiting_other_side` is false) flips `current_team` to the other side and returns `{action = "end_planning"}`. The second lock calls `TurnResolver.resolve`. After a Helix kickoff, Helix is first and Aether is second.

`ignore_team_gate` exists because `apply_*` still refuse the “wrong” team. The resolver sets it true so Helix actions can apply during a simultaneous cycle. Tests set it to poke Helix pieces during Aether’s turn.

### Planning-time possession

`has_ball` is the **real** board. `planning_carrier()` / `planning_has_ball()` walk the acting team’s queue so a player can already queue pass / shoot / dribble as if they will have the ball.

- Pass to a teammate: planning possession moves to that teammate (and can chain).
- Pass to an empty square: planning possession ends, unless a teammate has queued a **move** onto that square — they collect it and can chain.
- Shoot: planning possession ends.
- Loose ball: the first queued **move** onto the ball’s cell collects it for planning.
- Cycle detection: if a pass loop exists, stop.

The real ball never moves during planning. Resolve playback snaps pieces and the ball back to the pre-cycle snapshot, then plays the events.

`expects_ball` is set when the actor does **not** currently hold the ball but `planning_has_ball` is true. At resolve, if they still do not have it, the follow-up is cancelled (`"pass did not arrive"` after a teammate pass, `"did not get the ball"` after a collect) rather than `"lost the ball"`.

### Ending a side

- Default: filling **all leftover AP on 3 players**, or marking those players **Done**, auto-calls `end_planning` from the controller (`planning_complete()`).
- `End Turn` / Enter is always legal, including 0 actions (`can_end_planning()` is unconditionally true).
- Option `GameSettings.require_end_turn`: third action only queues; player must confirm.

---

## How one action is applied

The resolver never implements dribble/tackle itself. It calls model methods. **Stepping onto an opponent is always `apply_move`**, which dispatches:

| Mover has ball? | Occupant has ball? | Resulting `action` | Dice |
|---|---|---|---|
| yes | (any opponent) | `dribble` | mover CTR vs occupant DEF |
| no | yes | `tackle` | mover DEF vs occupant CTR |
| no | no | `challenge` | CTR vs CTR |

Win: swap onto the square (loser shoved to origin). Dribble win keeps the ball; tackle win steals it and the winner **faces away** from the player they stole from (`_face_away_from`). Dribble loss: stay put, occupant steals the ball. Tackle/fight loss: nothing changes. Dribble or tackle **numeric tie**: both stay put and the ball bounces to a random in-bounds cell of the 3×3 around its current tile (`MatchRules.bounce_cells`), including staying put. Occupied landings give that player the ball; empty landings leave it loose. Square-fight ties still use `attacker_wins_ties`.

Tackle success is the 1dDEF vs 1dCTR chance minus an **approach-angle penalty** (`MatchRules.tackle_direction`): 0° front 0, 45° −15pp, 90° side −30pp, 135° −50pp, 180° back −85pp, clamped at 0%. Angle is carrier facing vs the vector from the contested cell to the tackler. Dice still roll; a win can be dropped so overall P(win) matches the penalised chance. Numeric ties still bounce. Scripted contest outcomes skip the extra drop. HUD `contest_preview` shows the penalised percent.

Pass: `apply_pass_to`. Intercepts first (see below), then offside, then give or drop. Passer does not move.

Swap: adjacent teammate only. Carrier keeps the ball and it follows them.

Shoot: `apply_shoot(player_id, remaining_ap)`. Intercepts first (`_resolve_pass_intercepts` on shooter → opponent net, same as a pass; the keeper in the net is the dest occupant so they do not intercept). If stolen, interceptor cuts to the landing and takes the ball (`intercepted`, no hit roll). Else hit roll against `shot_hit_chance` (Gaussian/erf base plus **+3 percentage points per leftover AP**, clamped 5–98%), then optional keeper save (shooter 1dACC vs keeper 1dDEF, ties to shooter). The shot spends every leftover AP and ends that player’s planning. Miss → loose on the goal tile. Save → keeper has the ball. Goal → `_award_goal` (rebuilds kickoff). `shot_preview.goal_chance` is `through × hit × (1 − save)`. Hovering the net with Shoot selected draws the pass lane and intercept circles.

### Dice

`1dSTAT`: `rng.randi_range(1, max(1, stat))`. Higher wins.

Dribble and tackle **numeric ties bounce** the ball (`tied` on the roll, `bounced` on the result). They do not use `attacker_wins_ties`. Other contests still go to **the team with the ball** (`MatchRules.attacker_wins_ties`):

- Attacker has the ball → attacker (pass-through, shot).
- Defender has the ball → defender (unused for dribble/tackle; those bounce).
- Same team, nobody has it → attacker (first claimer in clash code).
- Opposite, nobody has it → the side whose team currently possesses, else occupant.

`contest_win_chance` enumerates the `atk * def` outcomes so HUD percents match the dice, including the tie rule. Tackle previews then subtract `MatchRules.tackle_angle_penalty` (percentage points by approach vs the carrier’s facing).

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

`TurnResolver.resolve(model)` copies `home_plans + away_plans` into `remaining`, logs `── Resolve cycle N ──`, sets `ignore_team_gate`, then loops **six AP waves** (`ap_end` 1..6). An action plays in the wave equal to the cumulative AP spent when it completes. A 2-AP first step is wave 2; a 3-AP first step is wave 3; a second 2-AP step on the same player is wave 4. Empty waves are skipped. A 1-AP pass as a first action therefore happens in wave 1, **before** anyone’s 2-AP tackle.

Inside a wave:

1. **Tackles** (`tackle`) — lowest `player_id` first inside a phase.
2. **Ball** (`pass`, `shoot`) — not id order. Always play the **current carrier’s** pass/shot next, so a pass can feed another pass or a shot. If the carrier has no ball action left, lowest id in the leftover batch.
3. **Dribbles**
4. **Square fights** (`challenge`)
5. **Destination contests** — remaining **moves** that share a dest:
   - Same team: 1dCTR, tie via `attacker_wins_ties` (ball / lower id). Losers cancelled `"lost the square fight"`. Winner stays in `remaining` for the move phase.
   - Opposite, one has the ball: treat as **tackle** (DEF vs CTR, same approach-angle penalty as a step-on tackle, measured from the meeting square). Winner may steal and then faces away from the old carrier. A numeric tie bounces the ball and both stay put.
   - Opposite, neither has the ball: CTR vs CTR square fight. Winner also collects a loose ball on that tile if `apply_move` runs onto it.
6. **Moves and swaps**

A result with `reset == true` (goal) **stops the cycle**. Leftover plans are cancelled `"play stopped — goal"`. Kickoff already ran inside `_award_goal`.

If no goal: leftover plans cancelled `"could not be completed"`, `current_team = HOME`, `turn_index += 1`. Always clears `awaiting_other_side` so the next cycle’s first lock is Aether (or the kicking side after a goal, already reset inside `setup_kickoff`).

Then both plan arrays clear and the gate is restored.

**Re-check legality at apply time.** Plans were aimed at the planning board. After earlier phases, dest may be illegal, the carrier may have lost the ball, a swap partner may have moved. `_apply_plan` cancels with a reason instead of forcing the action. If a player was shoved, the action is tried from the **new** tile (`valid_moves` / `can_pass_to_cell` use current `player.pos`).

Pass destinations stored as a teammate `target_id` are resolved to that player’s **current** cell, not the queued `dest`, so a moving receiver can still be found.

---

## Intercepts

Computed in **tile space**. Segment = passer / shooter tile centre → target tile centre. Shots reuse `interceptors_for_pass` / `_resolve_pass_intercepts` with dest = opponent net. An opponent intercepts if their 1-tile-radius circle touches the segment at `t > 0` (standing only next to the passer does not count). Teammates and the intended receiver never intercept. A keeper standing in the net is that dest occupant, so they save rather than intercept.

Order: increasing `t` along the lane. Each is passer **live ACC** vs interceptor **live DEF**, ties to the **passer** (ball team). Intercept chance is then multiplied by `reach = 1 / (1 + INTERCEPT_DIST_K * dist)` (`INTERCEPT_DIST_K = 1`, so 1 tile off the lane keeps half). First failure steals — interceptor must win the dice and pass the reach roll.

Landing: snap the closest point on the segment to a tile; if occupied, search nearby free tiles. Interceptor leaves their old cell empty.

`scripted_first_intercept_wins == false` means “beat every interceptor”, not “only beat the first”. It applies to shots as well as passes.

---

## Offside

Position check (`MatchRules.is_offside_position`): in opponent’s half, strictly nearer the opponent goal than the **ball/passer** cell, and fewer than two opponents as near that goal as the receiver (level counts as covering). Keeper counts. Level with the ball is onside.

Only a **completed pass to a teammate** is an offence. Empty-square passes, carrying, swapping, collecting a loose ball: never offside. Intercept happens **before** offside; a stolen pass is not flagged.

Restart: closest opponent (Chebyshev, then lowest id) swaps onto the receiver’s tile and takes the ball.

---

## Combat log and hotseat fog

`CombatLog` stores `{kind, text, team?, hidden_from_opponent?}`.

Hidden from the opponent:

- `queue` events (PLAN lines)
- `note(..., team)` such as “AETHER locked in N actions.”

Public: resolution events, headers, phase titles.

Viewers:

- `VIEWER_ALL` (`-1`): everything (tests, debug).
- `VIEWER_PUBLIC` (`-2`): hide all private lines. HUD uses this **while resolving**.
- A team id: that team’s private lines + all public.

HUD during planning: viewer = `model.current_team`. Plan arrows (`pitch.set_plans`) and gold rings are **only** the acting team’s queue, including past cycles — you never see the other side’s arrows.

---

## Controller / UI

`match_controller.gd` is the scene root.

**Input**

- Left click cell → `handle_cell_clicked`.
- Right click adjacent cell of the selected player → queue `turn` (`handle_cell_right_clicked`). 1 AP up to 90°, 2 AP for 135°/180°. Otherwise cancel pending command, then deselect. Esc: cancel pending command, then deselect, then open pause menu.
- Backspace: `undo_last_action` → `pop_last_plan` of the selected player if they have a queued action, otherwise the last plan of the acting side. Selects that player and re-arms Move. No-op when the queue is empty.
- Enter / Space: `end_planning`. Space is taken in `_input` so a focused action button cannot steal it.
- 1–9 / keypad: Nth button currently shown in `commands_for` (not a fixed action map).

**Command-first UX.** Select a player → `_pending_action` defaults to `"move"` if they have a walk. After a queued action with AP remaining, Move is re-armed so consecutive tiles chain. Bottom bar lists only commands with at least one dest. Then click a highlighted tile → `action_for_command` → `queue_plan`.

Why not “click the tile then pick Move/Pass”? One cell is often two actions (adjacent empty = move or pass; adjacent teammate = pass or swap; net = shoot and maybe move). The old chooser is still in the HUD (`show_choices`) and `_open_choice` still exists on the controller, but **nothing calls `_open_choice`**. Do not revive it without wiring; current tests assume command-then-tile.

Highlight colours (pitch): green walk, white turn, amber contest, blue pass, red offside pass, purple swap (`choice_cells` reused for this), gold shot. Pass hover and Shoot-on-net hover share `set_pass_preview` (lane + intercept circles). Right-click queues a turn even when Move is armed (a 45° cell is both a walk and a turn).

Selecting a **planned** player twice clears their plan (`clear_plan`) so you can pick someone else before the third action locks.

**Resolve playback.** `animate_moves` is false on `headless` and in tests. When true, `_play_resolve` sets `busy`, walks `result.events`, tweens pieces/ball, then respawns on kickoff reset. `_resolve_generation` invalidates an in-flight tween if New Game is pressed mid-animation.

**Camera.** `_frame_camera` fits `pitch.world_rect()` (including both nets) into `hud.play_area()` — the rectangle left of the 308px log and between the top/bottom bars.

**Menu.** Title on first graphical launch (`open_title`, tree paused). Pause: Esc with nothing selected. Options persist via `GameSettings` (`user://settings.cfg`) so New Game does not wipe them. `anim_scale()` = `5 / speed` (1 = slowest, 10 = fastest, 5 = original timing).

---

## Vs AI vs hotseat

Human is **always Aether**. `vs_ai` is a flag on the controller, not the model.

On each cycle `_begin_vs_ai_cycle` → `_preplan_ai`:

1. `current_team = AWAY`
2. `AiCoach.fill_plans(model)` — greedy, up to 3, avoids stacking dests when it can
3. `current_team = HOME`

Helix therefore commits **before** Aether queues, on the current board, without seeing Aether’s plans. That matches simultaneous play. (In hotseat Helix plans second, but also cannot see Aether’s arrows/log.)

When Aether `end_planning`s, the controller immediately `end_planning`s again (Helix is already filled) so the player does not sit through a Helix turn. After a Helix kickoff, vs-AI still preplans Helix, marks Helix as already locked (`awaiting_other_side`), and puts Aether in the chair. Helix arrows stay hidden. Aether’s End Turn is the second lock of the cycle and resolves immediately. Clicks are ignored only as a safety net if `current_team` is ever AWAY in vs-AI.

`AiCoach` scoring (rough): shoot ≫ walk-in goal ≫ through-pass with forward gain ≫ tackle ≫ dribble ≫ collect loose ball ≫ move toward ball / forward. Offside passes are heavily penalised. First action of a side uses a very low keep-threshold so Helix always tries to queue at least one thing.

---

## Result dictionaries

Almost every public function returns `{ok, action, ...}`. The log formatter and the tween code both switch on `action`. Keep these keys stable:

| `action` | Meaning |
|---|---|
| `queue` | Plan stored; board unchanged |
| `pop_plan` | Last queued action removed; PLAN log line dropped |
| `end_planning` | Side locked; other team to move |
| `resolve` | Cycle done; `events` is the playback list |
| `move` / `dribble` / `tackle` / `challenge` / `swap` / `pass` / `shoot` / `offside` / `clash` | Applied |
| `cancelled` | Plan dropped; `reason` / `reason_text` |

Useful flags: `contest_won`, `contest_tied`, `bounced`, `bounce_cell`, `gained_possession`, `lost_possession`, `intercepted`, `goal`, `reset`, `hit`, `saved`, `expects_ball` (on the plan, not the event), `displaced_id` (shove/swap partner), `player_id` / `defender_id` / `receiver_id`. Tackles also carry `angle_deg` / `angle_penalty` / `angle_label`. A steal may set `facing` on the winner’s result so playback does not use the step direction.

If you add an action, update: `commands_for`, `command_dests`, `TurnResolver._apply_plan` + phase lists, `CombatLog.format_result`, controller `_present_result` / highlights, `AiCoach._score`, and tests.

---

## Tests

`tests/run_tests.gd` extends `SceneTree`, `call_deferred("_run")`, `quit(0|1)`.

It covers rules math, kickoff, contests, dribble/tackle bounce, tackle approach angle, AP waves, pass/intercept/offside/shoot (including shot intercepts), full plan→resolve sequences (tackle-then-pass cancel, pass-then-move carry, ground-pass collect, arrival tackles, empty end-turn), controller clicks, menu/settings, vs-AI preplan.

Controller tests instantiate `main.tscn`, set `animate_moves = false`, and often `queue_free()` the instance. They reach into HUD private fields (`_end_turn`, `_forecast`) — ugly but load-bearing.

When you change a rule, **add or extend a test in the same file**. Prefer `scripted_*` over seeding RNG.

`tests/capture_preview.gd` is a manual screenshot helper (`/tmp/sci-fi-football/*.png`), not part of the suite.

---

## Invariants (break these and something subtle dies)

1. **Model is truth.** Visual positions are synced from `PlayerState.pos` in `_refresh` except during a tween. After a tween, `_refresh` / `_spawn_visuals` snap back.
2. **Never two players on one cell.** Contests swap; intercepts refuse occupied landings; moves onto teammates are illegal (use swap).
3. **`has_ball` and `ball.carrier_id` stay paired.** Only `_give_ball` / `_release_ball`.
4. **Planning does not mutate the board.** If a click moves a piece immediately, you bypassed `queue_plan`.
5. **Resolver is the only multi-action path.** Phase order is the design. Do not “just apply plans in queue order”.
6. **Pass range and move range are different.** Move = 1. Pass = Euclidean radius `PASS_RANGE` (5 tile lengths, cell centre to cell centre). Adjacent empty/teammate is a chooser in the **model** (`actions_for`), a command pick in the **UI**.
7. **Live stats for dice and previews.** Always `live_accuracy()` etc., never the printed field, except when showing `ACC 10 (13)`.
8. **Fog is a view filter**, not deleted data. `as_text()` with no args still contains PLAN lines.

---

## Not implemented (do not pretend they exist)

- Fouls, cards, clock, extra time, named set pieces beyond kickoff.
- Pass inaccuracy other than intercepts (a non-intercepted pass always arrives).
- Substitutions, stamina recovery, injuries.
- Network play. Hotseat is same-machine; vs-AI is local greedy Helix.
- Aether AI. Vs-AI human is Aether.

---

## Where to edit, by job

| You want to… | Start here |
|---|---|
| Change grid size, pass range, energy, AP pool, move costs, turn costs, shot curve, intercept radius / reach, tackle angle penalties | `MatchRules` constants + tests |
| Change kickoff shape or role stats | `Formation` |
| Change when an action is legal to **queue** | `MatchModel.command_dests` / `can_plan_*` |
| Change what an action **does** | `MatchModel.apply_*` |
| Change simultaneous order / clash rules | `TurnResolver` |
| Change Helix personality | `AiCoach._score` |
| Change click / hotkey / animation | `match_controller.gd` |
| Change look of the board or pieces | `pitch.gd` / `player_piece.gd` |
| Change HUD chrome | `hud.gd` `_build*` |
| Persist a new option | `GameSettings` + `GameMenu` options panel |

After a rules change, run the headless suite before considering it done.

A feature is not done until the docs match. Full checklist: [`_README_FIRST.md` — Adding a feature](_README_FIRST.md#adding-a-feature). Player-visible behaviour → [`RULES.md`](RULES.md). File map / phases / result keys / invariants → this file. Session gotchas → [`_README_FIRST.md`](_README_FIRST.md). Same change, not a follow-up.
