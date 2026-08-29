# Sci-Fi Football — current rules

This is what the game actually does today.

## Setup

- Pitch: **26×17** tiles plus **two extra goal tiles**. `x` runs goal to goal (0 = Aether goal line, 25 = Helix goal line). `y` runs touchline to touchline (`y = 0` is the top / Aether’s left wing). The 26×17 cell grid is the FIFA 105×68 m pitch (width kept to the FIFA ratio at length 26).
- Goal tiles sit **outside** the rectangle, on the old out-line: Aether net `(-1, 8)`, Helix net `(26, 8)`. Each net is **one cell**. Keepers start in the net so they do not occupy a pitch tile.
- From a net tile the keeper can step to the three adjacent pitch squares in front of goal.
- Teams: **Aether** (home, cyan, attacks +x) vs **Helix** (away, magenta, attacks −x).
- **11v11**, 4-4-2 kickoff. Two players never share a tile.
- Aether **#9 ST** starts on the centre spot `(12, 8)` **with the ball**. Helix does not start in possession. Helix’s strikers stand in their own half, just outside the centre circle.
- After **Helix** scores, that same Aether kickoff is used again. After **Aether** scores, the whole 4-4-2 is rotated 180° through the pitch centre: Helix **#9 ST** takes `(13, 8)` with the ball. The receiving team starts in its own half and **outside the centre circle**, so those strikers cannot contest the first pass.
- **Simultaneous cycles.** The kicking team plans first. Aether plans **up to 3 players** at match start (and after Helix scores); Helix plans first after Aether scores. Each of those players has **6 action points**. The turn auto-ends when all 3 players have spent their AP; **End Turn** can finish early with fewer players or leftover AP. The other side then plans the same way. All queued actions resolve together in **six waves**, one per action point. An action plays in the wave equal to the AP spent when it finishes. Then Aether plans again.

Distance is **Chebyshev**: `max(|dx|, |dy|)`. One tile in any of 8 directions is adjacent.

Each player **faces** one of those 8 directions (the chevron on the piece). Aether starts facing **+x**, Helix facing **−x**. After a player changes tile — move, dribble, tackle, square fight, swap, intercept cut-off, or offside restart — they face that step. A player who **wins a tackle and takes the ball** then turns their back to the player they stole from (faces away from them). That is the same as the step facing on a swap tackle; on an arrival tackle it may be a different direction from the step they took onto the square.

## Attributes

Every player has four stats plus an **energy** pool. Hover or select a player to see them. A bar under each piece shows remaining energy.

| Stat | Used for |
|---|---|
| **ACC** | Completing a pass or shot against interceptors; hitting a shot |
| **DEF** | Stopping a dribble; tackling the carrier; intercepting a pass or shot |
| **CTR** | Dribbling; holding the ball when tackled; fighting for an empty square |
| **STA** | Size of the energy pool |

Kickoff values by role:

| Role | ACC | DEF | CTR | STA |
|---|---|---|---|---|
| ST | 20 | 10 | 15 | 10 |
| Central mid (LCM/RCM) | 10 | 15 | 15 | 10 |
| Wide mid (LM/RM) | 15 | 10 | 10 | 10 |
| Centre back (LCB/RCB) | 10 | 20 | 20 | 10 |
| Full back (LB/RB) | 10 | 15 | 15 | 10 |
| GK | 10 | 20 | 20 | 10 |

### Energy

- Max energy is **STA × 10**. Players start each kickoff full.
- Each resolved action (move, turn, swap, pass, dribble, tackle, square fight, shot) costs **1 energy**. Cancelled actions do not.
- Live ACC / DEF / CTR scale with remaining energy: full energy is 100% of the printed stat; **empty energy halves them**. In between, the drop is linear. The inspector shows `ACC 10 (13)` when fatigue has reduced the live value.

## How to take a turn

1. Click any player on the team that is planning.
2. Choose an action from the bottom bar (or press **1–9**): Move, Turn, Pass, Dribble, Tackle, Fight, Swap, Shoot, Done. Only actions that player can currently take are listed. **Move** is selected as soon as you click a player, and it stays selected after the first step so you can chain-click tiles.
3. Click a highlighted tile. That **queues** the action — nothing moves yet. The player stays selected if they still have AP, so you can chain more steps.
4. Repeat for up to **3 different players**, **6 AP** each. Gold pips around a piece show leftover AP after that player has spent at least one point. A gold ring marks a planned player; arrows show their queued steps.
5. Filling **all 6 AP on 3 players**, or marking those players **Done**, ends the turn automatically. **Done** parks leftover AP and a mint check shows they are finished. Click **End Turn** (or press Enter / Space) to finish with fewer players or unused AP.
6. After Helix’s turn ends, all queued actions resolve in **six AP waves**. A 2-AP first step plays in wave 2; a later 2-AP step on the same player plays in wave 4. The match log lists every public event and roll.
7. **Backspace** cancels the latest queued action of the selected player. With nobody selected — or if the selected player has no actions — it cancels this side’s latest action. Click a planned player twice to clear all of theirs and pick someone else. **Right-click an adjacent tile** to turn toward it (1 AP up to 90°, 2 AP for 135°/180°) without picking Turn first. Right-click anywhere else, or Escape, cancels the current action, then the selection; Escape with nothing selected opens the menu.

You cannot pick a fourth player.

Hotseat: plan arrows, gold rings, and plan log lines are visible only to the team that queued them — including past cycles. Resolution events (who tackled whom, rolls, and results) are public.

Highlights (after you pick an action):

- **Green** — walk there
- **White** — turn to face that square (no step)
- **Amber** — contest an opponent on that square
- **Blue** — pass there
- **Red** — pass to an offside teammate
- **Purple** — swap with that teammate
- **Gold** — shoot at the opponent net

## Actions

### Move

- Costs **2 AP** straight (orthogonal) or **3 AP** diagonally. 1 tile into the **3-cell cone**: the square you face, plus 45° either side.
- You cannot queue a step you cannot afford. With 2 AP left you can still walk straight, but not diagonally.
- Empty tiles only (or an opponent tile, which is a contest instead).
- Cannot walk onto a teammate. Use **swap** for that.
- If you have the ball, it comes with you.
- If the ball is loose on the destination, you take it.
- After you queue a move onto a loose ball, you can plan as if you already have it (pass, shoot, dribble). If you do not actually collect it — for example someone else wins that square — those ball actions are ignored.
- After the step, the player faces the direction they just moved.

### Turn

- Face a new direction without leaving the square.
- Click (or **right-click**) any adjacent tile. You do not move there. Straight ahead is not a turn.
- **1 AP** turns you up to **90°** (45° or 90° either side).
- **2 AP** turns you **135° or 180°**.
- You cannot queue a turn you cannot afford. With 1 AP left you can still face 45°/90°, but not 135°/180°.

### Done

- Costs **0 AP**. The player is finished planning even with leftover AP.
- Choosing it from the action bar queues immediately — no tile click.
- They still occupy one of the **3 player slots**. A mint check on the piece marks them finished.
- They no longer count as an unmoved player for auto-end. Filling 3 players who are out of AP **or** Done ends the turn.
- **Backspace** undoes Done (or their last queued action). Click the piece twice to clear their plan and pick someone else.

### Swap places

- Costs **2 AP** straight or **3 AP** diagonally, same as a walk.
- Adjacent teammate in the **move cone** only.
- You take their tile, they take yours.
- Whoever had the ball keeps it and carries it to their new tile.
- Offered together with **pass** when the carrier clicks an adjacent teammate.

### Dribble

- Costs **2 AP** straight or **3 AP** diagonally, same as a walk.
- Carrier steps onto an opponent in the **move cone**.
- Roll: your **CTR** vs their **DEF**.
- You win: you take the square, they are shoved back to where you came from, you keep the ball.
- You lose: you stay put, they steal the ball.
- A **tie** (both dice show the same number): both players stay put and the ball **bounces** to a random cell of the 3×3 centred on where it was, including staying put. An occupied landing gives that player the ball; an empty landing leaves it loose.

### Tackle

- Costs **2 AP** straight or **3 AP** diagonally, same as a walk.
- Player **without** the ball steps onto the **carrier** in the **move cone**.
- Roll: your **DEF** vs their **CTR**.
- Approach angle is measured from the **carrier’s facing** to the cell you are coming from (the square you occupy, or the meeting square on an arrival tackle). Front is head-on; back is from behind.
- That angle subtracts percentage points from tackle success (clamped at 0%):

| Approach | Penalty |
|---|---|
| Front (0°) | none |
| 45° | −15% |
| Side (90°) | −30% |
| 135° | −50% |
| Back (180°) | −85% |

- Hover a tackle to see the penalised chance, e.g. `tackle NAME 13 DEF vs 9 CTR = 32% success (side -30%)`.
- You win: you swap onto their square, take the ball, and turn your back to the player you stole from.
- You lose: nothing changes.
- A **tie**: both stay put and the ball bounces the same way as a tied dribble. The approach penalty does not turn a bounce into a win or a loss.

### Square fight

- Costs **2 AP** straight or **3 AP** diagonally, same as a walk.
- Player without the ball steps onto an opponent in the **move cone** who also does not have the ball.
- Roll: **CTR vs CTR**.
- You win: you swap onto that square. No ball changes hands.
- You lose: nothing changes.

### Pass

- Costs **1 AP**.
- Only the player with the ball.
- Range: a **circle** of radius **5 tile lengths** (cell centre to cell centre). Orthogonal 5 is in; diagonal 4 is out. To a **teammate** or an **empty square**.
- Cannot pass into the **rear cone**: directly back and **43°** to each side. **Adjacent** tiles are excepted — you may still pass to a neighbouring cell even if it is behind you.
- You stay put. The ball travels to the target.
- Empty square: the ball becomes **loose** there. You cannot lay the ball into an empty net.
- Teammate: they receive it and become the carrier. This includes the keeper standing in the net.
- Adjacent empty square can be a **Move** or a **Pass** — pick the action first, then the tile.
- Adjacent teammate can be a **Pass** or a **Swap** — pick the action first, then the teammate.
- Pass still uses the 5-tile-length circle once Pass is selected.
- A pass to a teammate in an **offside position** is still legal. If it is not intercepted, it is offside (see below). Empty-square passes are never offside.
- After you queue a pass to a teammate, that teammate can plan as if they already have the ball (pass on, shoot, dribble). If the incoming pass is intercepted or cancelled, those ball actions do not play.
- After you queue a pass onto an empty square, a teammate who then queues a step onto that square can plan as if they will collect it. If they never get the ball, those follow-up actions are ignored.

## Simultaneous resolution

Actions are planned against the current board, then resolve in **six waves**, one per action point. Each action plays in the wave equal to the cumulative AP that player has spent when that action finishes. A first action that costs 2 AP plays in wave 2; a first action that costs 3 AP plays in wave 3; a second 2-AP action on the same player plays in wave 4. Wave 1 is empty unless someone queued a 1-AP action (a 45°/90° turn or a pass). A 2-AP 135°/180° turn plays in wave 2. Empty waves are skipped.

Example: Aether queues a 2-AP step then another 2-AP step. Helix queues a 3-AP step.

- Wave 1 — nothing
- Wave 2 — Aether’s first step
- Wave 3 — Helix’s step
- Wave 4 — Aether’s second step

Inside a wave:

1. **Tackles**
2. **Passes and shots** — the ball travels next, following the current carrier so a pass can feed another pass or a shot. A pass to a teammate who also queued a move arrives first; they then move with the ball. A pass to an empty square lands there loose; a player who then steps onto that square collects it.
3. **Dribbles**
4. **Square fights**
5. **Destination contests** — if two or more remaining **moves** target the same empty square:
   - **Opposite teams, one has the ball:** a **tackle** (the player without the ball rolls **DEF**, the carrier rolls **CTR**). Winner takes the square. If the tackler wins, they also steal the ball.
   - **Opposite teams, neither has the ball:** a **CTR vs CTR** square fight. Winner takes the square (and collects a loose ball there).
   - **Same team:** **1dCTR**; a tie goes to the player with the ball if one has it, otherwise the lower-id player (first claimer).
   Losers stay put.
6. **Moves and swaps**

So if Aether tackles the Helix carrier and that carrier also queued a pass, the tackle is resolved first. If the tackle wins the ball, the pass is cancelled and the log says why.

If a player was shoved before their action, the action is tried from their new tile when it is still legal; otherwise it is cancelled.

A **goal** stops the rest of the cycle. Remaining planned actions are cancelled. Kickoff rebuilds with the conceding side in the kicking shape (Helix’s restart is the 180° of Aether’s). That side has the ball and plans first.

The **match log** (right panel) lists every plan, clash, contest roll, pass, intercept, offside, shot, and cancellation — in the order they resolved.

## Offside

A teammate is in an **offside position** when all of these are true at the moment the ball is played:

- They are in the **opponent’s half** (Aether: `x ≥ 13`; Helix: `x ≤ 12`). The halfway line is between columns 12 and 13.
- They are **nearer the opponent goal than the ball** (Aether: larger `x`; Helix: smaller `x`). Level with the ball is onside.
- **Fewer than two opponents** are as near the opponent goal as they are (same `x` comparison; level counts as covering). The keeper counts.

Only **receiving a pass** is an offence. Standing offside, carrying the ball yourself, swapping, or collecting a loose ball is not.

If a pass is intercepted, play continues. If it arrives to an offside teammate:

- The **closest opponent** (Chebyshev, then lowest id) **moves onto the offside tile** and takes the ball.
- The offside player is swapped onto that opponent’s old tile.
- Remaining planned actions in the cycle continue from the new state.

Hover an offside teammate to see the restart. Those tiles highlight **red**. The chooser labels the pass **Pass (offside)**.

## Intercepts

When the carrier is selected and you hover a legal **pass** tile, or hover the opponent net with **Shoot** selected:

- A line is drawn from passer / shooter centre to target centre.
- Opponents whose **1-tile radius** circle the line **crosses or touches** can intercept.
- Standing only next to the passer (not along the lane) does not count.
- Teammates and the intended receiver never intercept. On a shot, a keeper standing **in the net** is that occupant — they do not intercept; they save if the ball arrives.

Each interceptor is an **ACC vs DEF** contest (passer’s ACC, interceptor’s DEF), checked in order along the pass or shot. Ties go to the **passer / shooter**. Standing off the line then cuts intercept chance: `reach = 1 / (1 + dist)`, so a player 1 tile off the lane keeps **half** their intercept chance. They must win the dice **and** make the reach.

- Preview lists each interceptor’s intercept / through chance and how far they sit off the lane.
- **Pass success** (or shot **through**) is the chance of beating every interceptor (independent rolls, multiplied).
- First interceptor who wins the dice and makes the reach: they **move to the cut-off tile** (nearest square to the point where their circle meets the line) and take the ball there. Their old tile is left empty.
- If that landing square is occupied, they take the closest free square to the intercept point.
- If every interceptor fails, the pass arrives as planned — unless the receiver is offside, in which case the offside restart happens instead. A shot that beats every interceptor then rolls hit and save as usual.

## Contests (dice)

All contested actions use the same roll:

- Each side rolls **1dSTAT** (faces `1` through that side’s live stat)
- Higher roll wins
- A **numeric tie** on a **dribble or tackle** (including an arrival tackle) bounces the ball to a random cell of the 3×3 centred on it, including the cell it already occupies. Both players stay put. Occupied landings give that player the ball; empty landings leave it loose.
- Other ties go to **the team with the ball**: a pass beats the interceptor, a shot beats the keeper’s save. If neither contestant’s team has the ball, the occupant / first claimer keeps the square.

Hover an adjacent opponent to see `action NAME stat vs stat = N% success`.

## Possession

- The ball is either **on a player** or **loose** on a tile.
- Walking onto a loose ball takes it.
- A completed pass to an empty tile leaves it loose.
- A completed pass to a teammate gives it to them.
- A failed dribble or a successful tackle / intercept (pass or shot) changes the carrier.
- A tied dribble or tackle can leave the ball loose, or give it to whoever stands on the bounce cell.

### Shoot

Shooting **spends every leftover AP** and **ends that player’s turn**. Each leftover point adds **+3 percentage points** to hit chance: 1 AP left → +3%, 5 AP left → +15%, a first-action shot with all 6 AP → +18%.

You may shoot if you have the ball, you are **not on a goal tile**, and the shot’s **hit chance is at least 5%**. Distance no longer gates the action, but it is scaled to a **105 × 68 m** pitch, so a midfield striker needs leftover AP to clear 5%. Leftover AP is added after the geometry/skill hit.

The goal tile highlights gold. Choose **Shoot**, then hover the net to see chances — the same pass line and intercept circles are drawn. Click the net to shoot. If the tile also allows move or dribble, a chooser appears.

Hover the goal to see:

```
d       = cell distance converted to metres (105 m / 26 tiles along the pitch, 68 m / 13 across)
theta_w = (7.32 x max(0.15, cos theta)) / max(d, 1)
theta_h = 2.44 / max(d, 1)
sigma   = lerp(12°, 1°, (ACC/100)^1.2)     ACC clamped 1–100
hit     = erf(theta_w / (2 sigma √2)) x erf(theta_h / (2 sigma √2)) + leftover
leftover = 0.03 x remaining AP
through = chance of beating every interceptor on the shot line (same as a pass)
save = P(keeper 1dDEF > shooter 1dACC)   if a keeper is on the goal tile, else 0
goal = through x hit x (1 - save)
```

`d` is metres, not tiles. One length-tile is about 4 m; the goal mouth is 7.32 × 2.44 m. `theta` is the angle between the shot and the goal axis (0 degrees = straight in), not the randomized miss. Hit is then clamped to 5–98%.

Resolution:

1. Intercepts, same as a pass. First interceptor who wins the dice and makes the reach takes the ball on the cut-off tile. The shot never reaches the net.
2. If it is not intercepted, roll hit against `hit`.
3. If it hits and a keeper is in the net, they try a save (shooter **1dACC** vs keeper **1dDEF**; ties to the shooter).
4. Goal: score +1, kickoff reset, the team that conceded starts with the ball and plans first. Helix’s restart uses the mirrored 4-4-2.
5. Save: the keeper has the ball.
6. Miss: the ball is loose on the goal tile.

Walking or dribbling the ball onto the opponent goal tile also counts as a goal.

## Not implemented yet

- Fouls and a clock.
- Pass misses other than intercepts (a pass that is not intercepted always arrives).

## How to run

```bash
~/.local/bin/godot --path /home/ivan/Projects/sci-fi-football
```
