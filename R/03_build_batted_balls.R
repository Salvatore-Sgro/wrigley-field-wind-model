# Builds batted_balls: one row per ball in play, joined to its game's weather, with spray angle and
# tailwind. MLB reports one wind direction per game, but each ball goes its own way, so the wind is
# projected onto each ball's path: tailwind = wind speed * cos(angle between ball and wind).
# Usage: Rscript R/03_build_batted_balls.R

source("R/config.R")

con <- db_connect()

invisible(dbExecute(con, "
  CREATE OR REPLACE TABLE batted_balls AS
  SELECT
    p.game_pk, p.game_date, p.game_year AS season, p.batter, p.stand,
    p.events, p.bb_type, p.launch_speed, p.launch_angle, p.hit_distance_sc,
    -- Degrees from straightaway center: negative = left field, positive = right field.
    -- Statcast's coordinates come from an image, where y increases going down.
    degrees(atan2(p.hc_x - 125.42, 198.27 - p.hc_y)) AS spray_angle,
    CASE WHEN p.events = 'home_run' THEN 1 ELSE 0 END AS is_hr,
    g.venue_name, g.temp, g.wind_speed, g.wind_label, g.wind_dir_deg, g.indoor,
    CASE WHEN g.venue_name = 'Wrigley Field' THEN 1 ELSE 0 END AS is_wrigley,
    g.wind_speed * cos(radians(spray_angle - g.wind_dir_deg)) AS wind_out
  FROM pitches p
  JOIN games g ON p.game_pk = g.game_pk
  WHERE p.type = 'X'
    AND p.launch_speed IS NOT NULL
    AND p.launch_angle IS NOT NULL
    AND p.hc_x IS NOT NULL
"))

# Checks that must hold if the table is right.
print(dbGetQuery(con, "SELECT season, count(*) AS batted_balls FROM batted_balls GROUP BY season ORDER BY season"))
print(dbGetQuery(con, "SELECT max(wind_speed) AS max_wind_speed, max(wind_out) AS max_tailwind FROM batted_balls"))
print(dbGetQuery(con, "
  SELECT stand, count(*) AS home_runs, round(avg(spray_angle), 1) AS avg_spray_angle
  FROM batted_balls WHERE is_hr = 1 AND stand IN ('L', 'R') GROUP BY stand ORDER BY stand
"))

dbDisconnect(con, shutdown = TRUE)
