# Data dictionary

Generated from the PostgreSQL catalog of `sql/01_ddl.sql`; descriptions maintained by hand.

Raw tables (`raw.*`) mirror source files with all columns as TEXT plus `load_id` and `loaded_at`; see the source documentation linked in the README.

## dw.fact_match

Transaction fact. **Grain: one row per league match.**

| Column | Type | Nullable | Description |
|---|---|---|---|
| `match_key` | bigint | no | Surrogate key of a match |
| `date_key` | integer | no | Match date (FK dim_date) |
| `season_key` | smallint | no | Season (FK dim_season) |
| `competition_key` | smallint | no | League (FK dim_competition) |
| `home_team_key` | integer | no | Home team version valid on match day (FK dim_team) |
| `away_team_key` | integer | no | Away team version valid on match day (FK dim_team) |
| `referee_key` | integer | no | Referee (FK dim_referee); -1 outside England |
| `value_snapshot_date_key` | integer | no | Month-end snapshot used for squad values (FK dim_date) |
| `kickoff_time` | time without time zone | yes | Local kick-off time |
| `full_time_result` | character(1) | no | H = home win, D = draw, A = away win (degenerate dim) |
| `home_goals` | smallint | no | Full-time goals home |
| `away_goals` | smallint | no | Full-time goals away |
| `home_ht_goals` | smallint | yes | Half-time goals home |
| `away_ht_goals` | smallint | yes | Half-time goals away |
| `home_points` | smallint | no | League points home (3/1/0), derived |
| `away_points` | smallint | no | League points away (3/1/0), derived |
| `home_shots` | smallint | yes | Shots by home team |
| `away_shots` | smallint | yes | Shots by away team |
| `home_shots_on_target` | smallint | yes | Shots on target, home |
| `away_shots_on_target` | smallint | yes | Shots on target, away |
| `home_corners` | smallint | yes | Corners, home |
| `away_corners` | smallint | yes | Corners, away |
| `home_fouls` | smallint | yes | Fouls committed, home |
| `away_fouls` | smallint | yes | Fouls committed, away |
| `home_yellow_cards` | smallint | yes | Yellow cards, home |
| `away_yellow_cards` | smallint | yes | Yellow cards, away |
| `home_red_cards` | smallint | yes | Red cards, home |
| `away_red_cards` | smallint | yes | Red cards, away |
| `home_xg` | numeric(4,2) | yes | Expected goals, home (NULL before 2026/27) |
| `away_xg` | numeric(4,2) | yes | Expected goals, away (NULL before 2026/27) |
| `odds_home` | numeric(6,2) | yes | Market-average decimal odds home win, pre-match |
| `odds_draw` | numeric(6,2) | yes | Market-average odds draw, pre-match |
| `odds_away` | numeric(6,2) | yes | Market-average odds away win, pre-match |
| `odds_home_close` | numeric(6,2) | yes | Market-average closing odds home win |
| `odds_draw_close` | numeric(6,2) | yes | Market-average closing odds draw |
| `odds_away_close` | numeric(6,2) | yes | Market-average closing odds away win |
| `home_squad_value_eur` | bigint | yes | Home squad market value (EUR), latest snapshot ≤ match date |
| `away_squad_value_eur` | bigint | yes | Away squad market value (EUR), latest snapshot ≤ match date |
| `source_file` | character varying(20) | no | Source file, e.g. 2627/E0.csv |
| `load_id` | bigint | no | Airflow load that last wrote the row |

## dw.fact_team_value_snapshot

Periodic snapshot fact. **Grain: one row per team per month-end.**

| Column | Type | Nullable | Description |
|---|---|---|---|
| `snapshot_date_key` | integer | no | Month-end date (FK dim_date) |
| `team_key` | integer | no | Team version (FK dim_team) |
| `competition_key` | smallint | no | League at snapshot date (FK dim_competition) |
| `squad_market_value_eur` | bigint | no | Sum of latest valuations of players at the club (EUR) |
| `valued_players` | smallint | no | Number of players with a valuation |
| `avg_player_value_eur` | bigint | no | Average player value (EUR) |
| `max_player_value_eur` | bigint | no | Most valuable player (EUR) |
| `days_since_last_valuation` | smallint | no | Age of the newest valuation in the squad (freshness) |

## dw.dim_team

SCD Type 2 (coach, league) with Type 1 stadium attributes. Role-playing: home and away team.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `team_key` | integer | no | Surrogate key of a team version (SCD2); -1 = unknown |
| `tm_club_id` | integer | no | Natural key: Transfermarkt club_id |
| `team_name` | character varying(80) | no | Canonical club name (Transfermarkt) |
| `fd_team_name` | character varying(50) | no | Club name used in match files |
| `country` | character varying(30) | no | Country of the club |
| `current_competition_key` | smallint | yes | League the club plays in during this version (Type 2) |
| `coach_name` | character varying(80) | yes | Head coach during this version (Type 2) |
| `stadium_name` | character varying(80) | yes | Home stadium (Type 1) |
| `stadium_seats` | integer | yes | Stadium capacity (Type 1, overwritten in all versions) |
| `valid_from` | date | no | First day this version is valid |
| `valid_to` | date | no | Last day valid; 9999-12-31 for current |
| `is_current` | boolean | no | True for the latest version |

## dw.dim_date

Static calendar dimension.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `date_key` | integer | no | Surrogate key yyyymmdd; -1 = unknown |
| `full_date` | date | no | Calendar date |
| `year` | smallint | no | Calendar year |
| `quarter` | smallint | no | Quarter 1–4 |
| `month` | smallint | no | Month 1–12 |
| `month_name` | character varying(9) | no | Month name |
| `iso_week` | smallint | no | ISO week number |
| `day_of_week` | smallint | no | ISO day of week, 1 = Monday |
| `day_name` | character varying(9) | no | Day name |
| `is_weekend` | boolean | no | Saturday or Sunday |

## dw.dim_season

Static.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `season_key` | smallint | no | Surrogate key |
| `season_code` | character(4) | no | Season code used in source paths, e.g. '2627' |
| `season_label` | character varying(7) | no | Readable label, e.g. '2026/27' |
| `start_date` | date | no | First day of season window |
| `end_date` | date | no | Last day of season window |
| `is_complete` | boolean | no | True when all matches have been played |

## dw.dim_competition

SCD Type 1.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `competition_key` | smallint | no | Surrogate key |
| `fd_division_code` | character varying(4) | no | Division code in football-data.co.uk (E0, SP1, I1, D1, F1) |
| `tm_competition_id` | character varying(4) | no | Competition id in Transfermarkt (GB1, ES1, IT1, L1, FR1) |
| `competition_name` | character varying(50) | no | League name |
| `country` | character varying(30) | no | Country of the league |
| `tier` | smallint | no | Level in national pyramid (1 = top) |
| `teams_per_season` | smallint | no | Number of teams; expected matches = n·(n−1) |

## dw.dim_referee

SCD Type 1. Referees are published for English leagues only.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `referee_key` | integer | no | Surrogate key; -1 = not published |
| `referee_name` | character varying(60) | no | Referee name as published |

## staging.team_name_map

Bridge between the two sources (football-data team name → Transfermarkt club_id).

| Column | Type | Nullable | Description |
|---|---|---|---|
| `fd_team_name` | text | no | Team name as spelled in football-data.co.uk files (PK) |
| `tm_club_id` | integer | no | Matching Transfermarkt club_id |
| `match_method` | text | no | How the match was found: exact, fuzzy or manual |
| `match_score` | numeric(4,3) | yes | String-similarity score for fuzzy matches (0–1) |
| `reviewed` | boolean | no | True once a human has confirmed the mapping |
