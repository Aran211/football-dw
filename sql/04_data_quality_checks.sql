-- =====================================================================
-- Data quality checks. Each query returns the offending rows;
-- 0 rows = PASS. In Project 2 these become dbt tests run by Airflow
-- after every load (severity: error = stop the DAG, warn = alert only).
-- =====================================================================

-- DQ1 [error] Uniqueness: one row per match in the latest raw load
SELECT div, date, hometeam, awayteam, count(*)
FROM raw.fd_matches
WHERE load_id = (SELECT max(load_id) FROM raw.fd_matches)
GROUP BY div, date, hometeam, awayteam
HAVING count(*) > 1;

-- DQ2 [error] Null check on mandatory match fields
SELECT * FROM raw.fd_matches
WHERE div IS NULL OR date IS NULL OR hometeam IS NULL OR awayteam IS NULL
   OR fthg IS NULL OR ftag IS NULL OR ftr IS NULL;

-- DQ3 [error] Cross-source integrity: every team name in the match
--     files must be mapped to a Transfermarkt club (team_name_map)
SELECT DISTINCT n.team
FROM (SELECT hometeam AS team FROM raw.fd_matches
      UNION SELECT awayteam FROM raw.fd_matches) n
LEFT JOIN staging.team_name_map m ON m.fd_team_name = n.team
WHERE m.fd_team_name IS NULL;

-- DQ4 [error] Consistency: result letter must agree with the score
SELECT match_key, home_goals, away_goals, full_time_result
FROM dw.fact_match
WHERE full_time_result <> CASE WHEN home_goals > away_goals THEN 'H'
                               WHEN home_goals < away_goals THEN 'A' ELSE 'D' END;

-- DQ5 [warn] Completeness: finished seasons must have
--     teams * (teams - 1) matches per league (380 or 306)
SELECT s.season_label, c.competition_name, count(f.match_key) AS loaded,
       c.teams_per_season * (c.teams_per_season - 1) AS expected
FROM dw.dim_season s
CROSS JOIN dw.dim_competition c
LEFT JOIN dw.fact_match f ON f.season_key = s.season_key AND f.competition_key = c.competition_key
WHERE s.is_complete
GROUP BY s.season_label, c.competition_name, c.teams_per_season
HAVING count(f.match_key) <> c.teams_per_season * (c.teams_per_season - 1);

-- DQ6 [warn] Freshness: newest Transfermarkt valuation older than 45 days
--     (expected to FAIL now: upstream updates paused since July 2026)
SELECT max(date::date) AS newest_valuation, current_date - max(date::date) AS age_days
FROM raw.tm_player_valuations
HAVING current_date - max(date::date) > 45;

-- DQ7 [warn] Plausible ranges: odds > 1.01, shots on target <= shots
SELECT match_key FROM dw.fact_match
WHERE odds_home <= 1.01 OR odds_draw <= 1.01 OR odds_away <= 1.01
   OR home_shots_on_target > home_shots OR away_shots_on_target > away_shots;
