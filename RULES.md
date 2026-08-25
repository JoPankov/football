# Sci-Fi Football — current rules

This is what the game actually does today.

## Setup

- Pitch: **12×7** tiles plus **two extra goal tiles**. `x` runs goal to goal (0 = Aether goal line, 11 = Helix goal line). `y` runs touchline to touchline (`y = 0` is the top / Aether’s left wing).
- Goal tiles sit **outside** the rectangle, on the old out-line: Aether net `(-1, 3)`, Helix net `(12, 3)`. Keepers start in the net so they do not occupy a pitch tile.
- From a net tile the keeper can step to the three adjacent pitch squares in front of goal.
- Teams: **Aether** (home, cyan, attacks +x) vs **Helix** (away, magenta, attacks −x).
- **11v11**, 4-4-2 kickoff. Two players never share a tile.
- Aether **#9 ST** starts on the centre spot `(5, 3)` **with the ball**. Helix does not start in possession.
- **Simultaneous cycles.** Aether plans **up to 3 actions** (one per player). The third action ends the turn automatically; **End Turn** can finish early with fewer. Helix then plans the same way. All queued actions then resolve together. Then Aether plans again.

Distance is **Chebyshev**: `max(|dx|, |dy|)`. One tile in any of 8 directions is adjacent.

## Attributes

Every player has four stats plus an **energy** pool. Hover or select a player to see them. A bar under each piece shows remaining energy.

| Stat | Used for |
|---|---|
| **ACC** | Completing a pass against interceptors; hitting a shot |
| **DEF** | Stopping a dribble; tackling the carrier; intercepting a pass |
| **CTR** | Dribbling; holding the ball when tackled; fighting for an empty square |
| **STA** | Size of the energy pool |

Kickoff values by role:

| Role | ACC | DEF | CTR | STA |
|---|---|---|---|---|
| ST | 26 | 4 | 9 | 9 |
| Central mid (LCM/RCM) | 12 | 8 | 7 | 13 |
| Wide mid (LM/RM) | 16 | 6 | 9 | 11 |
| Centre back (LCB/RCB) | 8 | 13 | 7 | 8 |
| Full back (LB/RB) | 10 | 11 | 8 | 10 |
| GK | 8 | 13 | 11 | 7 |

### Energy

- Max energy is **STA × 10**. Players start each kickoff full.
- Each resolved action (move, swap, pass, dribble, tackle, square fight, shot) costs **1 energy**. Cancelled actions do not.
- Live ACC / DEF / CTR scale with remaining energy: full energy is 100% of the printed stat; **empty energy halves them**. In between, the drop is linear. The inspector shows `ACC 10 (13)` when fatigue has reduced the live value.

## How to take a turn

1. Click any player on the team that is planning.
2. Click a highlighted tile (or pick from the menu). That **queues** the action — nothing moves yet.
3. Repeat for up to **3 different players**. A gold ring marks a planned player; an arrow shows their destination.
4. The **third** action ends the turn automatically. Click **End Turn** (or press Enter) to finish with fewer than 3.
5. After Helix’s turn ends (third action or End Turn), all queued actions resolve. The match log lists every public event and roll (tackles, contests, moves, passes, shots).
6. Click a planned player twice to clear their action and pick someone else — do this before the third action if you want to change who acts. Right-click or Escape cancels a menu or deselects.

You cannot pick a fourth player. The third action locks the turn.

Hotseat: plan arrows, gold rings, and plan log lines are visible only to the team that queued them — including past cycles. Resolution events (who tackled whom, rolls, and results) are public.

Highlights:

- **Green** — walk there
- **Amber** — contest an opponent on that square
- **Blue** — pass only
- **Red** — pass to an offside teammate
- **Purple** — more than one action (move/pass, pass/swap, or shoot plus move/dribble)
- **Gold** — shoot at the opponent net

## Actions

### Move

- 1 tile, 8 directions.
- Empty tiles only (or an opponent tile, which is a contest instead).
- Cannot walk onto a teammate. Use **swap** for that.
- If you have the ball, it comes with you.
- If the ball is loose on the destination, you take it.

### Swap places

- Adjacent teammate only.
- You take their tile, they take yours.
- Whoever had the ball keeps it and carries it to their new tile.
- Offered together with **pass** when the carrier clicks an adjacent teammate.

### Dribble

- Carrier steps onto an adjacent opponent.
- Roll: your **CTR** vs their **DEF**.
- You win: you take the square, they are shoved back to where you came from, you keep the ball.
- You lose: you stay put, they steal the ball.

### Tackle

- Player **without** the ball steps onto the **carrier**.
- Roll: your **DEF** vs their **CTR**.
- You win: you swap onto their square and take the ball.
- You lose: nothing changes.

### Square fight

- Player without the ball steps onto an opponent who also does not have the ball.
- Roll: **CTR vs CTR**.
- You win: you swap onto that square. No ball changes hands.
- You lose: nothing changes.

### Pass

- Only the player with the ball.
- Range: **3 tiles** (Chebyshev), to a **teammate** or an **empty square**.
- You stay put. The ball travels to the target.
- Empty square: the ball becomes **loose** there.
- Teammate: they receive it and become the carrier.
- Adjacent empty square also allows **move** — you choose.
- Adjacent teammate also allows **swap** — you choose.
- 2–3 tiles away: pass is queued immediately (no menu).
- A pass to a teammate in an **offside position** is still legal. If it is not intercepted, it is offside (see below). Empty-square passes are never offside.
- After you queue a pass to a teammate, that teammate can plan as if they already have the ball (pass on, shoot, dribble). If the incoming pass is intercepted or cancelled, those ball actions do not play.

## Simultaneous resolution

Actions are planned against the current board, then resolve in this order:

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

A **goal** stops the rest of the cycle. Remaining planned actions are cancelled. The team that conceded then plans first from the new kickoff.

The **match log** (right panel) lists every plan, clash, contest roll, pass, intercept, offside, shot, and cancellation — in the order they resolved.

## Offside

A teammate is in an **offside position** when all of these are true at the moment the ball is played:

- They are in the **opponent’s half** (Aether: `x ≥ 6`; Helix: `x ≤ 5`). The halfway line is between columns 5 and 6.
- They are **nearer the opponent goal than the ball** (Aether: larger `x`; Helix: smaller `x`). Level with the ball is onside.
- **Fewer than two opponents** are as near the opponent goal as they are (same `x` comparison; level counts as covering). The keeper counts.

Only **receiving a pass** is an offence. Standing offside, carrying the ball yourself, swapping, or collecting a loose ball is not.

If a pass is intercepted, play continues. If it arrives to an offside teammate:

- The **closest opponent** (Chebyshev, then lowest id) **moves onto the offside tile** and takes the ball.
- The offside player is swapped onto that opponent’s old tile.
- Remaining planned actions in the cycle continue from the new state.

Hover an offside teammate to see the restart. Those tiles highlight **red**. The chooser labels the pass **Pass (offside)**.

## Intercepts

When the carrier is selected and you hover a legal pass tile:

- A line is drawn from passer centre to target centre.
- Opponents whose **1-tile radius** circle the line **crosses or touches** can intercept.
- Standing only next to the passer (not along the lane) does not count.
- Teammates and the intended receiver never intercept.

Each interceptor is an **ACC vs DEF** contest (passer’s ACC, interceptor’s DEF), checked in order along the pass. Ties go to the interceptor.

- Preview lists each interceptor’s intercept / through chance.
- **Pass success** is the chance of beating every interceptor (independent rolls, multiplied).
- First interceptor who wins: they **move to the cut-off tile** (nearest square to the point where their circle meets the pass line) and take the ball there. Their old tile is left empty.
- If that landing square is occupied, they take the closest free square to the intercept point.
- If every interceptor fails, the pass arrives as planned — unless the receiver is offside, in which case the offside restart happens instead.

## Contests (dice)

All contested actions use the same roll:

- Each side rolls **1dSTAT** (faces `1` through that side’s live stat)
- Higher roll wins
- A tie goes to **the team with the ball**: a pass beats the interceptor, a dribble beats the defender, a tackle fails, a shot beats the keeper’s save. If neither contestant’s team has the ball, the occupant / first claimer keeps the square.

Hover an adjacent opponent to see `action NAME stat vs stat = N% success`.

## Possession

- The ball is either **on a player** or **loose** on a tile.
- Walking onto a loose ball takes it.
- A completed pass to an empty tile leaves it loose.
- A completed pass to a teammate gives it to them.
- A failed dribble or a successful tackle / intercept changes the carrier.

### Shoot

You may shoot if you have the ball and stand in the **shooting zone** of the opponent net:

- The **penalty box**: the three pitch tiles adjacent to that goal tile. Aether box `(0, 2) (0, 3) (0, 4)`. Helix box `(11, 2) (11, 3) (11, 4)`.
- The **ring** around the box: every pitch tile that touches the box, including by a corner.

The goal tile highlights gold. Click it to shoot. If the tile also allows move or dribble, a chooser appears.

Hover the goal to see:

```
hit = ACC/(ACC+1) x range x angle
range = 1 / (1 + 0.35 x (d-1))
angle = max(0.15, cos theta)
save = P(keeper 1dDEF > shooter 1dACC)   if a keeper is on the goal tile, else 0
goal = hit x (1 - save)
```

`d` is Euclidean distance in tiles from shooter centre to goal centre. `theta` is the angle between the shot and the goal axis (0 degrees = straight in).

Resolution:

1. Roll hit against `hit`.
2. If it hits and a keeper is in the net, they try a save (shooter **1dACC** vs keeper **1dDEF**; ties to the shooter).
3. Goal: score +1, kickoff reset, the team that conceded starts with the ball.
4. Save: the keeper has the ball.
5. Miss: the ball is loose on the goal tile.

Walking or dribbling the ball onto the opponent goal tile also counts as a goal.

## Not implemented yet

- Fouls and a clock.
- Pass misses other than intercepts (a pass that is not intercepted always arrives).

## How to run

```bash
~/.local/bin/godot --path /home/ivan/Projects/sci-fi-football
```
