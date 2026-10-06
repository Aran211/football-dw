-- =====================================================================
-- Sample DML – populates the star schema so the demo queries run.
--
-- !! ILLUSTRATIVE DATA ONLY !!
-- Team / league names are real so the mapping problem is realistic,
-- but scores, odds, coaches and market values below are GENERATED
-- (seeded random) and are NOT real results. The real pipeline loads
-- them from football-data.co.uk and Transfermarkt (see README).
-- =====================================================================

-- ---------- dim_date (static, generated) -----------------------------
INSERT INTO dw.dim_date
SELECT to_char(d, 'YYYYMMDD')::int, d::date,
       extract(year FROM d), extract(quarter FROM d), extract(month FROM d),
       trim(to_char(d, 'Month')), extract(week FROM d), extract(isodow FROM d),
       trim(to_char(d, 'Day')), extract(isodow FROM d) IN (6, 7)
FROM generate_series(DATE '2023-07-01', DATE '2027-06-30', INTERVAL '1 day') AS d
ON CONFLICT DO NOTHING;

-- ---------- dim_season (static) --------------------------------------
INSERT INTO dw.dim_season VALUES
 (1, '2324', '2023/24', '2023-08-01', '2024-06-30', true),
 (2, '2425', '2024/25', '2024-08-01', '2025-06-30', true),
 (3, '2526', '2025/26', '2025-08-01', '2026-06-30', true),
 (4, '2627', '2026/27', '2026-08-01', '2027-06-30', false)
ON CONFLICT DO NOTHING;

-- ---------- dim_competition (SCD1) -----------------------------------
INSERT INTO dw.dim_competition VALUES
 (1, 'E0',  'GB1', 'Premier League', 'England', 1, 20),
 (2, 'SP1', 'ES1', 'LaLiga',         'Spain',   1, 20),
 (3, 'I1',  'IT1', 'Serie A',        'Italy',   1, 20),
 (4, 'D1',  'L1',  'Bundesliga',     'Germany', 1, 18),
 (5, 'F1',  'FR1', 'Ligue 1',        'France',  1, 18)
ON CONFLICT DO NOTHING;

-- ---------- team name mapping (staging) ------------------------------
INSERT INTO staging.team_name_map VALUES
 ('Man United',  985, 'manual', NULL,  true),
 ('Man City',    281, 'manual', NULL,  true),
 ('Arsenal',      11, 'exact',  1.000, true),
 ('Liverpool',    31, 'exact',  1.000, true),
 ('Real Madrid', 418, 'exact',  1.000, true),
 ('Barcelona',   131, 'exact',  1.000, true),
 ('Ath Madrid',   13, 'manual', NULL,  true),
 ('Sevilla',     368, 'exact',  1.000, true)
ON CONFLICT DO NOTHING;

-- ---------- dim_team (SCD2) ------------------------------------------
INSERT INTO dw.dim_team (team_key, tm_club_id, team_name, fd_team_name, country,
                         current_competition_key, coach_name, stadium_name,
                         stadium_seats, valid_from, valid_to, is_current) VALUES
 (-1, -1, 'Unknown', 'Unknown', 'Unknown', NULL, NULL, NULL, NULL, '1900-01-01', '9999-12-31', true),
 ( 1, 985, 'Manchester United', 'Man United', 'England', 1, 'Coach A', 'Old Trafford', 74310, '2023-07-01', '9999-12-31', true),
 ( 2, 281, 'Manchester City',   'Man City',   'England', 1, 'Coach B', 'Etihad Stadium', 53400, '2023-07-01', '9999-12-31', true),
 ( 3,  11, 'Arsenal FC',        'Arsenal',    'England', 1, 'Coach C', 'Emirates Stadium', 60704, '2023-07-01', '9999-12-31', true),
 ( 4,  31, 'Liverpool FC',      'Liverpool',  'England', 1, 'Coach D', 'Anfield', 61276, '2023-07-01', '9999-12-31', true),
 ( 5, 418, 'Real Madrid',       'Real Madrid','Spain',   2, 'Coach E', 'Santiago Bernabeu', 83186, '2023-07-01', '9999-12-31', true),
 ( 6, 131, 'FC Barcelona',      'Barcelona',  'Spain',   2, 'Coach F', 'Spotify Camp Nou', 99354, '2023-07-01', '9999-12-31', true),
 ( 7,  13, 'Atletico de Madrid','Ath Madrid', 'Spain',   2, 'Coach G', 'Metropolitano', 70460, '2023-07-01', '9999-12-31', true),
 ( 8, 368, 'Sevilla FC',        'Sevilla',    'Spain',   2, 'Coach H', 'Ramon Sanchez-Pizjuan', 43883, '2023-07-01', '9999-12-31', true)
ON CONFLICT DO NOTHING;

-- SCD2 change: Liverpool changes coach on 2024-06-01.
-- (In Project 2 this is done automatically by a dbt snapshot.)
UPDATE dw.dim_team SET valid_to = DATE '2024-05-31', is_current = false
 WHERE tm_club_id = 31 AND is_current AND coach_name <> 'Coach X';
INSERT INTO dw.dim_team (team_key, tm_club_id, team_name, fd_team_name, country,
                         current_competition_key, coach_name, stadium_name,
                         stadium_seats, valid_from)
SELECT 9, tm_club_id, team_name, fd_team_name, country, current_competition_key,
       'Coach X', stadium_name, stadium_seats, DATE '2024-06-01'
FROM dw.dim_team WHERE team_key = 4
ON CONFLICT DO NOTHING;

-- ---------- dim_referee (SCD1) ---------------------------------------
INSERT INTO dw.dim_referee VALUES (1, 'Referee One'), (2, 'Referee Two'), (3, 'Referee Three')
ON CONFLICT DO NOTHING;

-- ---------- fact_team_value_snapshot (month-end) ---------------------
SELECT setseed(0.42);
INSERT INTO dw.fact_team_value_snapshot
SELECT to_char(m, 'YYYYMMDD')::int, t.team_key, t.current_competition_key,
       v.val, 25, v.val / 25, (v.val / 25) * 3, (random() * 40)::int
FROM generate_series(DATE '2023-07-31', DATE '2026-06-30', INTERVAL '1 month') g(m0)
CROSS JOIN LATERAL (SELECT (date_trunc('month', g.m0) + INTERVAL '1 month - 1 day')::date AS m) mm
JOIN dw.dim_team t
  ON t.team_key > 0 AND mm.m BETWEEN t.valid_from AND t.valid_to
CROSS JOIN LATERAL (SELECT ((400 + t.tm_club_id % 7 * 120 + random() * 150) * 1e6)::bigint AS val) v
ON CONFLICT DO NOTHING;

-- ---------- fact_match (double round robin per league & season) ------
SELECT setseed(0.17);
WITH teams AS (
    SELECT DISTINCT tm_club_id, current_competition_key AS comp FROM dw.dim_team WHERE team_key > 0
), fixtures AS (
    SELECT s.season_key, s.season_code, h.comp, h.tm_club_id AS home_id, a.tm_club_id AS away_id,
           s.start_date + (row_number() OVER (PARTITION BY s.season_key, h.comp ORDER BY h.tm_club_id, a.tm_club_id) * 14)::int AS mdate
    FROM dw.dim_season s
    JOIN teams h ON true
    JOIN teams a ON a.comp = h.comp AND a.tm_club_id <> h.tm_club_id
    WHERE s.season_key <= 3
), scored AS (
    SELECT f.*, (random() * 3.4)::int AS hg, (random() * 2.6)::int AS ag,
           round((1.4 + random() * 2.6)::numeric, 2) AS oh,
           round((3.0 + random() * 1.2)::numeric, 2) AS od,
           round((1.6 + random() * 4.0)::numeric, 2) AS oa,
           (random() * 2 + 1)::int AS ref
    FROM fixtures f
)
INSERT INTO dw.fact_match
SELECT row_number() OVER (ORDER BY s.mdate, s.home_id),
       to_char(s.mdate, 'YYYYMMDD')::int, s.season_key, s.comp,
       ht.team_key, at.team_key,
       CASE WHEN s.comp = 1 THEN s.ref ELSE -1 END,       -- referee only for England
       COALESCE((SELECT max(snapshot_date_key) FROM dw.fact_team_value_snapshot
                  WHERE snapshot_date_key <= to_char(s.mdate, 'YYYYMMDD')::int), -1),
       TIME '15:00',
       CASE WHEN s.hg > s.ag THEN 'H' WHEN s.hg < s.ag THEN 'A' ELSE 'D' END,
       s.hg, s.ag, LEAST(s.hg, 1), LEAST(s.ag, 1),
       CASE WHEN s.hg > s.ag THEN 3 WHEN s.hg = s.ag THEN 1 ELSE 0 END,
       CASE WHEN s.ag > s.hg THEN 3 WHEN s.hg = s.ag THEN 1 ELSE 0 END,
       12 + s.hg * 2, 9 + s.ag * 2, 4 + s.hg, 3 + s.ag, 5, 4, 11, 12, 2, 2, 0, 0,
       NULL, NULL,
       s.oh, s.od, s.oa, s.oh, s.od, s.oa,
       hv.squad_market_value_eur, av.squad_market_value_eur,
       s.season_code || '/' || c.fd_division_code || '.csv', 1
FROM scored s
JOIN dw.dim_competition c ON c.competition_key = s.comp
JOIN dw.dim_team ht ON ht.tm_club_id = s.home_id AND s.mdate BETWEEN ht.valid_from AND ht.valid_to
JOIN dw.dim_team at ON at.tm_club_id = s.away_id AND s.mdate BETWEEN at.valid_from AND at.valid_to
LEFT JOIN dw.fact_team_value_snapshot hv ON hv.team_key = ht.team_key
      AND hv.snapshot_date_key = (SELECT max(snapshot_date_key) FROM dw.fact_team_value_snapshot x
                                  WHERE x.team_key = ht.team_key AND x.snapshot_date_key <= to_char(s.mdate, 'YYYYMMDD')::int)
LEFT JOIN dw.fact_team_value_snapshot av ON av.team_key = at.team_key
      AND av.snapshot_date_key = (SELECT max(snapshot_date_key) FROM dw.fact_team_value_snapshot x
                                  WHERE x.team_key = at.team_key AND x.snapshot_date_key <= to_char(s.mdate, 'YYYYMMDD')::int)
ON CONFLICT DO NOTHING;
