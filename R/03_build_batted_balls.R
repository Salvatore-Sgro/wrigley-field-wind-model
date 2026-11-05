# Builds batted_balls: one row per ball in play, joined to its game's weather, with spray angle and
# tailwind. MLB reports one wind direction per game, but each ball goes its own way, so the wind is
# projected onto each ball's path: tailwind = wind speed * cos(angle between ball and wind).
# Usage: Rscript R/03_build_batted_balls.R

source("R/config.R")
source("R/analysis_helpers.R")

con <- db_connect()

invisible(dbExecute(con, "
  CREATE OR REPLACE TABLE batted_balls AS
  SELECT
    p.game_pk, p.game_date, p.game_year AS season, p.batter, p.stand,
    p.events, p.bb_type, p.launch_speed, p.launch_angle, p.hit_distance_sc,
    -- Degrees from straightaway center: negative = left field, positive = right field.
    -- Statcast's coordinates come from an image, where y increases going down.
    degrees(atan2(p.hc_x - 125.42, 198.27 - p.hc_y)) AS spray_angle,
    -- Home runs that left the park. Statcast also records inside-the-park home runs as 'home_run',
    -- but those stay in the field, so wind carry isn't what made them home runs.
    CASE WHEN p.events = 'home_run' AND coalesce(p.des, '') NOT ILIKE '%inside-the-park%'
         THEN 1 ELSE 0 END AS is_hr,
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

save_table(dbGetQuery(con, "
  SELECT season,
         sum(CASE WHEN events = 'home_run' THEN 1 ELSE 0 END) AS all_home_runs,
         sum(CASE WHEN events = 'home_run' AND is_hr = 0 THEN 1 ELSE 0 END) AS inside_the_park,
         sum(CASE WHEN events = 'home_run' AND is_hr = 0 AND is_wrigley = 1 THEN 1 ELSE 0 END) AS inside_the_park_wrigley
  FROM batted_balls GROUP BY season ORDER BY season
"), "inside_the_park_home_runs")

save_table(dbGetQuery(con, "
  SELECT (SELECT count(*) FROM pitches) AS pitches,
         (SELECT count(*) FROM batted_balls) AS batted_balls,
         (SELECT count(DISTINCT game_pk) FROM batted_balls) AS games
"), "data_size")

# Fair balls can't land outside the foul lines, so if spray angle is on the right scale almost every
# ball in play falls between -45 and +45 degrees.
save_table(dbGetQuery(con, "
  SELECT CASE WHEN is_hr = 1 THEN 'Home runs' ELSE 'Other balls in play' END AS balls,
         count(*) AS n,
         round(quantile_cont(spray_angle, 0.005), 1) AS pct_0_5,
         round(quantile_cont(spray_angle, 0.995), 1) AS pct_99_5,
         round(100 * avg(CASE WHEN abs(spray_angle) > 45 THEN 1 ELSE 0 END), 2) AS pct_outside_45
  FROM batted_balls GROUP BY balls ORDER BY balls
"), "spray_angle_check")

dbDisconnect(con, shutdown = TRUE)
