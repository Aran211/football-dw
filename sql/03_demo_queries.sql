-- =====================================================================
-- Demo queries – one per business question in the brief
-- =====================================================================

-- Team-perspective view: every match appears twice (home + away row).
-- Joins via the durable key tm_club_id so a team's SCD2 versions
-- (e.g. coach change) still roll up into one team.
CREATE OR REPLACE VIEW dw.v_team_match AS
SELECT f.match_key, f.date_key, f.season_key, f.competition_key,
       t.tm_club_id, t.team_name, t.coach_name, 'home' AS venue,
       f.home_goals AS goals_for, f.away_goals AS goals_against,
       f.home_points AS points, f.home_shots_on_target AS sot,
       f.odds_home AS odds_win, f.home_squad_value_eur AS squad_value_eur
FROM dw.fact_match f JOIN dw.dim_team t ON t.team_key = f.home_team_key
UNION ALL
SELECT f.match_key, f.date_key, f.season_key, f.competition_key,
       t.tm_club_id, t.team_name, t.coach_name, 'away',
       f.away_goals, f.home_goals, f.away_points, f.away_shots_on_target,
       f.odds_away, f.away_squad_value_eur
FROM dw.fact_match f JOIN dw.dim_team t ON t.team_key = f.away_team_key;


-- Q1. Which teams over- or under-perform relative to squad market value?
--     KPI: points per match and points per EUR 100m of squad value.
SELECT s.season_label, c.competition_name, tm.team_name,
       count(*)                                         AS matches,
       round(avg(tm.points), 2)                          AS points_per_match,
       round(avg(tm.squad_value_eur) / 1e6)              AS avg_squad_value_m_eur,
       round(sum(tm.points) / (avg(tm.squad_value_eur) / 1e8), 2) AS points_per_100m_eur
FROM dw.v_team_match tm
JOIN dw.dim_season s       ON s.season_key = tm.season_key
JOIN dw.dim_competition c  ON c.competition_key = tm.competition_key
GROUP BY s.season_label, c.competition_name, tm.team_name
ORDER BY s.season_label, c.competition_name, points_per_100m_eur DESC;


-- Q2. How often does the bookmaker favourite win? Which league is the
--     least predictable?  KPI: favourite hit rate, upset rate.
WITH fav AS (
    SELECT f.*,
           CASE WHEN f.odds_home <= LEAST(f.odds_draw, f.odds_away) THEN 'H'
                WHEN f.odds_away <= LEAST(f.odds_home, f.odds_draw) THEN 'A'
                ELSE 'D' END AS favourite
    FROM dw.fact_match f
    WHERE f.odds_home IS NOT NULL
)
SELECT c.competition_name, s.season_label,
       count(*)                                                        AS matches,
       round(100.0 * avg((favourite = full_time_result)::int), 1)      AS favourite_hit_rate_pct,
       round(100.0 * avg((favourite <> full_time_result
                          AND full_time_result <> 'D')::int), 1)       AS upset_rate_pct
FROM fav f
JOIN dw.dim_competition c ON c.competition_key = f.competition_key
JOIN dw.dim_season s      ON s.season_key = f.season_key
GROUP BY c.competition_name, s.season_label
ORDER BY favourite_hit_rate_pct;


-- Q3. How big is home advantage per league and is it changing?
--     KPI: home win %, average goal difference (home - away).
SELECT c.competition_name, s.season_label,
       round(100.0 * avg((f.full_time_result = 'H')::int), 1) AS home_win_pct,
       round(100.0 * avg((f.full_time_result = 'D')::int), 1) AS draw_pct,
       round(100.0 * avg((f.full_time_result = 'A')::int), 1) AS away_win_pct,
       round(avg(f.home_goals - f.away_goals), 2)              AS avg_home_goal_diff
FROM dw.fact_match f
JOIN dw.dim_competition c ON c.competition_key = f.competition_key
JOIN dw.dim_season s      ON s.season_key = f.season_key
GROUP BY c.competition_name, s.season_label
ORDER BY c.competition_name, s.season_label;


-- Q4. Which teams convert chances best (goals per shot on target),
--     and does finishing efficiency go with more points?
SELECT tm.team_name,
       sum(tm.goals_for)                                         AS goals,
       sum(tm.sot)                                               AS shots_on_target,
       round(sum(tm.goals_for)::numeric / NULLIF(sum(tm.sot), 0), 3) AS goals_per_sot,
       round(avg(tm.points), 2)                                  AS points_per_match
FROM dw.v_team_match tm
GROUP BY tm.team_name
HAVING sum(tm.sot) > 0
ORDER BY goals_per_sot DESC
LIMIT 10;


-- Q5. Do referees differ in how many cards they give?
--     (Referee is only published for English leagues.)
SELECT r.referee_name,
       count(*)                                                       AS matches,
       round(avg(f.home_yellow_cards + f.away_yellow_cards), 2)       AS yellows_per_match,
       round(avg(f.home_red_cards + f.away_red_cards), 2)             AS reds_per_match,
       round(avg(f.home_fouls + f.away_fouls), 1)                     AS fouls_per_match
FROM dw.fact_match f
JOIN dw.dim_referee r ON r.referee_key = f.referee_key
WHERE f.referee_key <> -1
GROUP BY r.referee_name
HAVING count(*) >= 3
ORDER BY yellows_per_match DESC;


-- Q6. Did results change after a coach change?  (uses SCD2 history:
--     each fact row points to the team version valid on match day)
SELECT tm.team_name, tm.coach_name,
       min(d.full_date) AS first_match, max(d.full_date) AS last_match,
       count(*)         AS matches,
       round(avg(tm.points), 2) AS points_per_match,
       round(avg(tm.goals_for - tm.goals_against), 2) AS avg_goal_diff
FROM dw.v_team_match tm
JOIN dw.dim_date d ON d.date_key = tm.date_key
WHERE tm.tm_club_id IN (SELECT tm_club_id FROM dw.dim_team GROUP BY tm_club_id HAVING count(*) > 1)
GROUP BY tm.team_name, tm.coach_name
ORDER BY tm.team_name, first_match;


-- Q7. Biggest upsets: wins by the team with the longest pre-match odds.
SELECT d.full_date, c.competition_name,
       th.team_name AS home_team, ta.team_name AS away_team,
       f.home_goals || '-' || f.away_goals AS score,
       CASE f.full_time_result WHEN 'H' THEN f.odds_home ELSE f.odds_away END AS winner_odds
FROM dw.fact_match f
JOIN dw.dim_date d        ON d.date_key = f.date_key
JOIN dw.dim_competition c ON c.competition_key = f.competition_key
JOIN dw.dim_team th       ON th.team_key = f.home_team_key
JOIN dw.dim_team ta       ON ta.team_key = f.away_team_key
WHERE f.full_time_result <> 'D'
ORDER BY winner_odds DESC
LIMIT 10;
