# Sci-Fi Football — current rules

This is what the game actually does today. Shooting is reserved for a later slice and is not playable.

## Setup

- Pitch: **12×7** tiles plus **two extra goal tiles**. `x` runs goal to goal (0 = Aether goal line, 11 = Helix goal line). `y` runs touchline to touchline (`y = 0` is the top / Aether’s left wing).
- Goal tiles sit **outside** the rectangle, on the old out-line: Aether net `(-1, 3)`, Helix net `(12, 3)`. Keepers start in the net so they do not occupy a pitch tile.
- From a net tile the keeper can step to the three adjacent pitch squares in front of goal.
- Teams: **Aether** (home, cyan, attacks +x) vs **Helix** (away, magenta, attacks −x).
- **11v11**, 4-4-2 kickoff. Two players never share a tile.
- Aether **#9 ST** starts on the centre spot `(5, 3)` **with the ball**. Helix does not start in possession.
- Turns alternate. Aether kicks off. One action ends the turn.

Distance is **Chebyshev**: `max(|dx|, |dy|)`. One tile in any of 8 directions is adjacent.

## Attributes

Every player has four stats. Hover or select a player to see them.

| Stat | Used for |
|---|---|
| **ACC** | Reserved for shooting (not implemented) |
| **PAS** | Completing a pass against interceptors |
| **DEF** | Stopping a dribble; tackling the carrier; intercepting a pass |
| **CTR** | Dribbling; holding the ball when tackled; fighting for an empty square |

Kickoff values by role:

| Role | ACC | PAS | DEF | CTR |
|---|---|---|---|---|
| ST | 13 | 6 | 4 | 9 |
| Central mid (LCM/RCM) | 6 | 12 | 8 | 7 |
| Wide mid (LM/RM) | 8 | 10 | 6 | 9 |
| Centre back (LCB/RCB) | 4 | 6 | 13 | 7 |
| Full back (LB/RB) | 5 | 7 | 11 | 8 |
| GK | 4 | 6 | 13 | 11 |

## How to take a turn

1. Click any player on the team whose turn it is.
2. Click a highlighted tile.
3. If that tile has more than one legal action, pick from the menu.
4. Right-click or Escape cancels a menu or deselects.

Highlights:

- **Green** — walk there
- **Amber** — contest an opponent on that square
- **Blue** — pass only
- **Purple** — more than one action (move/pass, or pass/swap)

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
- 2–3 tiles away: pass happens immediately (no menu).

## Intercepts

When the carrier is selected and you hover a legal pass tile:

- A line is drawn from passer centre to target centre.
- Opponents whose **1-tile radius** circle the line **crosses or touches** can intercept.
- Standing only next to the passer (not along the lane) does not count.
- Teammates and the intended receiver never intercept.

Each interceptor is a **PAS vs DEF** contest (passer’s PAS, interceptor’s DEF), checked in order along the pass. Ties go to the interceptor.

- Preview lists each interceptor’s intercept / through chance.
- **Pass success** is the chance of beating every interceptor (independent rolls, multiplied).
- First interceptor who wins: they **move to the cut-off tile** (nearest square to the point where their circle meets the pass line) and take the ball there. Their old tile is left empty.
- If that landing square is occupied, they take the closest free square to the intercept point.
- If every interceptor fails, the pass arrives as planned.

## Contests (dice)

All contested actions use the same roll:

- Each side: **stat + 2d6**
- The acting player wins only if **strictly higher**
- Ties go to the occupant / interceptor

Hover an adjacent opponent to see `action NAME stat vs stat = N% success`.

## Possession

- The ball is either **on a player** or **loose** on a tile.
- Walking onto a loose ball takes it.
- A completed pass to an empty tile leaves it loose.
- A completed pass to a teammate gives it to them.
- A failed dribble or a successful tackle / intercept changes the carrier.

## Not implemented yet

- **Shoot** (planned: only in the opponent’s last third, two rolls — shooter ACC to hit the net, then keeper to save).
- Last thirds are already marked: Aether attacks `x ≥ 8`, Helix attacks `x ≤ 3`.
- Pass misses other than intercepts (a pass that is not intercepted always arrives).
- Goals, offside, fouls, stamina, and time.

## How to run

```bash
~/.local/bin/godot --path /home/ivan/Projects/sci-fi-football
```
