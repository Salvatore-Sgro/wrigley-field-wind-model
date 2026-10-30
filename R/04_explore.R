# Looks at the data before any modeling: how the wind behaves at Wrigley, what the raw home-run gap
# looks like, and whether tailwind relates to distance at Wrigley and elsewhere.
# Usage: Rscript R/04_explore.R

source("R/config.R")
source("R/analysis_helpers.R")
library(ggplot2)

con <- read_only_connection()

save_table(dbGetQuery(con, "
  SELECT CASE WHEN wind_label LIKE 'Out%' THEN 'Out'
              WHEN wind_label LIKE 'In%' THEN 'In'
              ELSE 'Cross, varying or calm' END AS wind_group,
         count(*) AS games,
         round(avg(wind_speed), 1) AS avg_mph,
         round(avg(temp), 1) AS avg_temp
  FROM games
  WHERE venue_name = 'Wrigley Field'
  GROUP BY wind_group
  ORDER BY games DESC
"), "wrigley_wind_conditions")

# The raw comparison. It mixes wind with everything else that differs between those games.
save_table(dbGetQuery(con, "
  SELECT CASE WHEN g.wind_label LIKE 'Out%' THEN 'Out'
              WHEN g.wind_label LIKE 'In%' THEN 'In'
              ELSE 'Cross, varying or calm' END AS wind_group,
         count(DISTINCT p.game_pk) AS games,
         sum(CASE WHEN p.events = 'home_run' THEN 1 ELSE 0 END) AS home_runs,
         round(home_runs / games, 2) AS hr_per_game
  FROM pitches p
  JOIN games g ON p.game_pk = g.game_pk
  WHERE g.venue_name = 'Wrigley Field'
  GROUP BY wind_group
  ORDER BY hr_per_game DESC
"), "wrigley_raw_hr_by_wind")

save_table(dbGetQuery(con, "
  SELECT bb_type, count(*) AS batted_balls,
         round(avg(hit_distance_sc)) AS avg_distance_ft,
         sum(is_hr) AS home_runs
  FROM batted_balls
  WHERE bb_type IS NOT NULL
  GROUP BY bb_type
  ORDER BY batted_balls DESC
"), "batted_ball_types")

# Hard-hit fly balls by tailwind, so contact quality doesn't muddy the comparison.
buckets <- dbGetQuery(con, "
  SELECT CASE WHEN is_wrigley = 1 THEN 'Wrigley Field' ELSE 'Other open-air parks' END AS parks,
         round(wind_out / 5) * 5 AS tailwind_bucket,
         count(*) AS fly_balls,
         round(avg(hit_distance_sc), 1) AS avg_distance_ft
  FROM batted_balls
  WHERE bb_type = 'fly_ball'
    AND NOT indoor
    AND launch_speed BETWEEN 95 AND 105
    AND wind_out IS NOT NULL
    AND hit_distance_sc IS NOT NULL
  GROUP BY parks, tailwind_bucket
  ORDER BY parks, tailwind_bucket
")
save_table(buckets, "distance_by_tailwind")

dbDisconnect(con, shutdown = TRUE)

# Small buckets are noise, so the chart only shows those with at least 30 fly balls.
plot_data <- subset(buckets, fly_balls >= 30)
chart <- ggplot(plot_data, aes(tailwind_bucket, avg_distance_ft, colour = parks)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2.5) +
  scale_colour_manual(values = c("Wrigley Field" = COLOR_WRIGLEY, "Other open-air parks" = COLOR_MUTED)) +
  labs(title = "Tailwind changes fly-ball distance at Wrigley, and barely anywhere else",
       subtitle = "Fly balls hit 95-105 mph, in 5-mph tailwind groups with at least 30 balls. Negative = headwind.",
       x = "Tailwind on the ball (mph)", y = "Average distance (ft)") +
  chart_theme()
save_chart(chart, "distance_by_tailwind")
