# How Much Does the Wind Change Home Runs at Wrigley Field?


Wrigley Field has a reputation for playing very differently depending on
the wind. I wanted to measure that: how much distance and how many home
runs the wind adds or removes, and how many home runs to expect given a
weather forecast.

**The short answer:** each mph of tailwind adds about 1 foot to a fly
ball at Wrigley, compared with about 0.2 feet at other open-air parks. A
15 mph tailwind multiplies a ball’s odds of being a home run by about 5,
and the effect is largest on balls that land near the wall. When tested
on seasons it hadn’t seen, the wind effect held up, but the model
predicted too many home runs. That problem is covered in [Testing on new
seasons](#testing-on-new-seasons).

## Data

- **Batted balls:** about 4.3 million regular-season pitches from
  Baseball Savant (Statcast) for 2019 and 2021-2025. I left out the
  shortened 2020 season.
- **Weather:** game-time temperature and wind from the MLB Stats API,
  joined on MLB’s game ID.
- **Storage:** a local DuckDB database, with a resumable download so an
  interruption can’t leave duplicate or partial data.

The models use fly balls and line drives. Ground balls and popups
produced no home runs in this data, so wind can’t change that outcome
for them.

## Measuring the wind on each ball

MLB reports one wind reading per game, relative to the field, like “12
mph, Out To CF.” But each ball goes in its own direction. So I converted
each ball’s landing spot into a spray angle and calculated its tailwind:

> tailwind = wind speed × cos(angle between the ball’s path and the
> wind)

A ball hit straight with a 10 mph wind gets +10, a ball at a right angle
to it gets 0, and a ball hit straight into it gets -10. This also shows
why crosswinds aren’t simply neutral: they help balls hit to one side
and hurt balls hit to the other.

## What the raw data shows

Wrigley games with the wind blowing out average 3.52 home runs, compared
with 1.81 when it’s blowing in. But that comparison can’t be taken at
face value, because wind-out days are also about 10 degrees warmer
(75.7° vs. 66.0°), and warm air helps the ball carry too.

The bigger surprise came from comparing Wrigley with other parks, using
fly balls hit equally hard:

![Average fly-ball distance by tailwind at Wrigley and at other open-air
parks](../output/distance_by_tailwind.png)

Distance rises steadily with tailwind at Wrigley, and it’s nearly flat
elsewhere. My hypothesis is ballpark design: Wrigley is low and open to
the wind off Lake Michigan, while many parks have tall grandstands that
block or redirect it, so one wind reading says less about what the ball
experiences. I haven’t tested this. Estimating the effect separately for
each park would be a good way to do it.

## Models

I built up the distance model in steps, tracking the tailwind estimate
at each one.

| Model | R² | AIC | Feet per mph of tailwind |
|----|---:|---:|---:|
| Tailwind only | 0.009 | 66,718 | 0.81 |
| Add exit velocity, launch angle, temperature | 0.876 | 54,284 | 1.01 |
| Launch angle as a quadratic | 0.901 | 52,928 | 1.08 |
| Smooth launch angle (GAM) | 0.904 | 52,742 | 1.07 |
| Smooth exit velocity too | 0.907 | 52,567 | 1.06 |
| Exit velocity and launch angle interact | 0.919 | 51,723 | 1.04 |
| Add hit direction | 0.925 | 51,314 | 1.01 |

Three things stand out:

- **A low R² didn’t mean wind was unimportant.** Wind alone explains
  about 1% of the variation in distance, because contact dominates. But
  about 1 foot per mph means a 15 mph tailwind adds about 15 feet, which
  can turn a warning-track out into a home run.
- **Controls pushed the estimate in both directions.** Temperature was
  inflating it, since warm days and tailwinds go together. Slightly
  softer and higher contact on tailwind balls was hiding part of it.
- **The estimate is stable.** It stayed close to 1 foot per mph through
  major changes to the model, so the result doesn’t depend on one
  modeling choice.

Fitting Wrigley and other open-air parks in one model with an
interaction gives **1.10 feet per mph at Wrigley and 0.18 elsewhere**.

The effect also isn’t the same on every fly ball:

![Feet of distance per mph of tailwind at each launch
angle](../output/tailwind_effect_by_launch_angle.png)

It rises from about 0.5 feet per mph at 20° to about 1.45 at 50-55°. It
appears to fall at higher angles, but only 49 of 5,992 fly balls were
hit above 60°, so that part is uncertain.

## From distance to home runs

Home runs are a yes-or-no outcome, so I used a logistic GAM with the
same terms. In this model, each mph of tailwind raises the odds of a
home run by about 11%, or about 5 times the odds for a 15 mph tailwind.
Odds aren’t probability, though, and the same multiplier matters very
differently depending on the ball:

| Ball, hit to center          | 15 mph headwind |       Calm | 15 mph tailwind |
|------------------------------|----------------:|-----------:|----------------:|
| Weak: 90 mph, 30°            |      under 0.1% | under 0.1% |            0.1% |
| **Borderline: 101 mph, 28°** |        **5.5%** |  **22.5%** |       **59.1%** |
| Crushed: 110 mph, 28°        |           63.2% |      89.5% |           97.7% |

Weak contact stays in the park, and crushed balls mostly go out anyway.
**The wind matters most on balls that land near the wall**, because
that’s where 30 feet can decide the outcome.

## Testing on new seasons

To test the model, I trained it only on earlier seasons and scored it on
each later one. I split by season rather than at random, because balls
from one game share conditions, and a random split would also let the
model train on the future.

**What held up.** Adding weather improved the Brier score in all four
test seasons, and the wind effect stayed stable, at about 10-12% higher
odds per mph.

| Test season | Brier, no weather | Brier, with weather | Odds ratio per mph |
|-------------|------------------:|--------------------:|-------------------:|
| 2022        |            0.0317 |              0.0275 |              1.118 |
| 2023        |            0.0306 |              0.0272 |              1.107 |
| 2024        |            0.0325 |              0.0302 |              1.111 |
| 2025        |            0.0350 |              0.0267 |              1.103 |

**What didn’t.** Calibration had looked excellent on the training data,
but the model predicted too many home runs in every test season, even
when given each ball’s actual contact:

![Predicted and actual home runs at Wrigley by test
season](../output/predicted_vs_actual_by_season.png)

The miss is about 18% for 2025, and it’s largest for balls predicted at
25-50%, where the model said 36.9% and 22.8% actually left the park.
That’s the part of the S-curve where a small change in carry matters
most. The model still ranked balls well, so this mainly matters for
forecasting totals.

**Why it happens.** This is drift rather than overfitting: the
relationship itself changed. Among hard-hit balls at good launch angles,
exit velocity barely moved, but distance and home-run rate fell:

| Season | Avg. exit velocity | Avg. distance | HR rate | Avg. tailwind |
|--------|-------------------:|--------------:|--------:|--------------:|
| 2019   |              104.5 |        402 ft |   73.2% |          +0.7 |
| 2021   |              104.9 |        399 ft |   76.4% |          +1.3 |
| 2022   |              104.5 |        392 ft |   62.5% |          +0.9 |
| 2023   |              104.4 |        395 ft |   66.8% |          +0.3 |
| 2024   |              104.6 |        390 ft |   58.3% |          -2.0 |
| 2025   |              104.0 |        386 ft |   58.8% |          -0.9 |

Less tailwind explains only about 2 of the 13 feet lost from 2021 to
2025, and it’s already in the model. Something else changed how far the
same contact carries. It could be the ball, how balls are stored, or air
conditions I don’t measure, and this data can’t separate those.

**The partial fix.** Training only on 2022-2024 improved the 2025 test,
from 238 predicted home runs to 224 (201 actual), and the Brier score
from 0.0267 to 0.0252. It’s still too high, and I only tested this fix
on one season. The final model uses 2022-2025.

## Results

The what-if question: for each ball, what’s its home-run chance with the
actual wind, compared with no wind?

![Home runs per game added or removed by each wind
direction](../output/wind_effect_by_direction.png)

- **By game:** the middle half of games fall between about -0.34 and
  +0.21 home runs from wind. On the biggest days it’s much larger: the
  top estimate is +4.6, on May 20, 2022, with 25 mph out to center and
  85°. That game had 11 home runs, and it’s an extreme case.
- **By season:** it mostly cancels, adding or removing about 1-6% of a
  season’s home runs. The largest is 2024, at about 9 fewer out of 153.
- **Skew:** the wind can add more than it can remove, since a game can
  only lose the home runs it would otherwise have had.

## The forecast

Before a game, nobody knows what contact there will be. So the forecast
replays Wrigley’s 2022-2025 batted balls under the forecast weather and
adds up their home-run chances per game.

| Weather                    | Expected home runs |
|----------------------------|-------------------:|
| Calm, 70°                  |               2.23 |
| 10 mph out to center, 75°  |               3.02 |
| 20 mph out to center, 85°  |               4.01 |
| 10 mph in from center, 60° |               1.46 |
| 20 mph in from center, 50° |               0.86 |
| 15 mph left to right, 70°  |               2.20 |

**Does it work?** I tested it on 2025 using a model trained on
2022-2024. Its average miss was 1.46 home runs per game, about 13%
better than always guessing the past average (1.67). That’s still a
large miss for one game, because a lot of a game’s home runs can’t be
known in advance.

| Forecast group | Games | Forecast | Actual |
|----------------|------:|---------:|-------:|
| Low            |    27 |     1.46 |   1.41 |
| Middle         |    26 |     1.99 |   2.12 |
| High           |    26 |     2.69 |   4.15 |

It’s good at ranking days, but it underestimates the biggest ones.

It also ran low overall in 2025, at 2.04 forecast vs. 2.54 actual, even
though the model runs high when it knows the contact. Both are true
because two errors push in opposite directions. 2025 had more and better
contact than the seasons being replayed, at 3.2 hard-hit balls at good
angles per game vs. 2.3. The forecast assumed the old contact, which
made it too low, while contact has been carrying less than the model
expects, which pushes it too high.

## Limitations

- **One wind reading per game.** Gusts and changes during a game are
  missed. This kind of measurement error tends to understate the true
  wind effect.
- **The what-if assumes players don’t adjust.** Pitchers may pitch
  differently, and outfielders may play deeper, on windy days.
- **The forecast describes a typical game.** It knows nothing about the
  lineups or starting pitchers.
- **Drift isn’t explained.** I can show that contact is carrying less,
  but not why.

## What I’d do next

- Add lineups and starting pitchers to the pre-game forecast.
- Handle drift directly with a rolling training window or a season
  effect, tested across several seasons.
- Estimate the wind effect separately for each park to test the
  ballpark-design hypothesis.
