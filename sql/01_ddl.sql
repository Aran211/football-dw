-- =====================================================================
-- Football DW – Project 1 (LTAT.02.007 Data Engineering)
-- Star schema DDL for PostgreSQL 16
--
-- Layers
--   raw      : 1:1 copies of source files (all text, + load metadata)
--   staging  : typed, de-duplicated, conformed (team-name mapping)
--   dw       : star schema used by BI / demo queries
-- In Project 2 the staging and dw layers are built by dbt models;
-- this file is the target design they materialise.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dw;

-- ---------------------------------------------------------------------
-- RAW LAYER (selected columns shown; loader keeps every source column)
-- ---------------------------------------------------------------------

-- football-data.co.uk  mmz4281/<season>/<div>.csv  (one row per match)
CREATE TABLE IF NOT EXISTS raw.fd_matches (
    load_id       BIGINT       NOT NULL,          -- one id per Airflow run
    source_file   TEXT         NOT NULL,          -- e.g. 2627/E0.csv
    loaded_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    div           TEXT, date TEXT, time TEXT,
    hometeam      TEXT, awayteam TEXT,
    fthg TEXT, ftag TEXT, ftr TEXT, hthg TEXT, htag TEXT, htr TEXT,
    referee TEXT,
    hs TEXT, "as" TEXT, hst TEXT, ast TEXT, hf TEXT, af TEXT,
    hc TEXT, ac TEXT, hy TEXT, ay TEXT, hr TEXT, ar TEXT,
    avgh TEXT, avgd TEXT, avga TEXT,              -- market-average pre-match odds
    avgch TEXT, avgcd TEXT, avgca TEXT,           -- market-average closing odds
    home_xg TEXT, away_xg TEXT                    -- published from 2026/27 only
);

-- Transfermarkt dataset (dcaribou/transfermarkt-datasets) – clubs.csv
CREATE TABLE IF NOT EXISTS raw.tm_clubs (
    load_id BIGINT NOT NULL, loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    club_id TEXT, club_code TEXT, name TEXT, domestic_competition_id TEXT,
    squad_size TEXT, average_age TEXT, stadium_name TEXT, stadium_seats TEXT,
    coach_name TEXT, last_season TEXT
);

-- Transfermarkt – players.csv (one row per player, current profile)
CREATE TABLE IF NOT EXISTS raw.tm_players (
    load_id BIGINT NOT NULL, loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    player_id TEXT, name TEXT, current_club_id TEXT, current_club_name TEXT,
    current_club_domestic_competition_id TEXT, position TEXT, sub_position TEXT,
    foot TEXT, height_in_cm TEXT, date_of_birth TEXT, country_of_citizenship TEXT,
    market_value_in_eur TEXT, highest_market_value_in_eur TEXT,
    contract_expiration_date TEXT, last_season TEXT
);

-- Transfermarkt – games.csv (one row per game). Used only for the
-- coach (manager) of each club on each match date -> SCD2 history of dim_team.
CREATE TABLE IF NOT EXISTS raw.tm_games (
    load_id BIGINT NOT NULL, loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    game_id TEXT, competition_id TEXT, season TEXT, date TEXT,
    home_club_id TEXT, away_club_id TEXT, home_club_goals TEXT, away_club_goals TEXT,
    home_club_manager_name TEXT, away_club_manager_name TEXT,
    stadium TEXT, attendance TEXT, referee TEXT
);

-- Transfermarkt – player_valuations.csv (one row per valuation event)
CREATE TABLE IF NOT EXISTS raw.tm_player_valuations (
    load_id BIGINT NOT NULL, loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    player_id TEXT, date TEXT, market_value_in_eur TEXT,
    current_club_id TEXT, player_club_domestic_competition_id TEXT
);

-- ---------------------------------------------------------------------
-- STAGING LAYER
-- ---------------------------------------------------------------------

-- Manually curated + fuzzy-matched bridge between the two sources.
-- e.g. 'Man United' (football-data)  ->  985 (Transfermarkt club_id)
CREATE TABLE IF NOT EXISTS staging.team_name_map (
    fd_team_name   TEXT PRIMARY KEY,
    tm_club_id     INTEGER     NOT NULL,
    match_method   TEXT        NOT NULL CHECK (match_method IN ('exact','fuzzy','manual')),
    match_score    NUMERIC(4,3),                -- similarity for fuzzy matches
    reviewed       BOOLEAN     NOT NULL DEFAULT false
);

-- ---------------------------------------------------------------------
-- DW LAYER – DIMENSIONS
-- ---------------------------------------------------------------------

-- Static: generated once for 2015-01-01 .. 2030-12-31
CREATE TABLE IF NOT EXISTS dw.dim_date (
    date_key      INTEGER     PRIMARY KEY,      -- yyyymmdd, -1 = unknown
    full_date     DATE        NOT NULL UNIQUE,
    year          SMALLINT    NOT NULL,
    quarter       SMALLINT    NOT NULL,
    month         SMALLINT    NOT NULL,
    month_name    VARCHAR(9)  NOT NULL,
    iso_week      SMALLINT    NOT NULL,
    day_of_week   SMALLINT    NOT NULL,         -- 1 = Monday
    day_name      VARCHAR(9)  NOT NULL,
    is_weekend    BOOLEAN     NOT NULL
);

-- Static: one row per football season
CREATE TABLE IF NOT EXISTS dw.dim_season (
    season_key    SMALLINT    PRIMARY KEY,
    season_code   CHAR(4)     NOT NULL UNIQUE,  -- '2627' as in source path
    season_label  VARCHAR(7)  NOT NULL,         -- '2026/27'
    start_date    DATE        NOT NULL,
    end_date      DATE        NOT NULL,
    is_complete   BOOLEAN     NOT NULL
);

-- SCD Type 1: names/countries are reference data; corrections overwrite
CREATE TABLE IF NOT EXISTS dw.dim_competition (
    competition_key   SMALLINT    PRIMARY KEY,
    fd_division_code  VARCHAR(4)  NOT NULL UNIQUE,  -- E0, SP1, I1, D1, F1
    tm_competition_id VARCHAR(4)  NOT NULL UNIQUE,  -- GB1, ES1, IT1, L1, FR1
    competition_name  VARCHAR(50) NOT NULL,
    country           VARCHAR(30) NOT NULL,
    tier              SMALLINT    NOT NULL,
    teams_per_season  SMALLINT    NOT NULL           -- 20 or 18; drives row-count check
);

-- SCD Type 2: coach and league membership change and history matters
-- (results "under coach X", promoted vs relegated seasons).
-- stadium_seats is handled as Type 1 (overwrite in all versions).
CREATE TABLE IF NOT EXISTS dw.dim_team (
    team_key          INTEGER     PRIMARY KEY,      -- surrogate, -1 = unknown
    tm_club_id        INTEGER     NOT NULL,         -- natural/business key
    team_name         VARCHAR(80) NOT NULL,         -- canonical (Transfermarkt)
    fd_team_name      VARCHAR(50) NOT NULL,         -- name used in match files
    country           VARCHAR(30) NOT NULL,
    current_competition_key SMALLINT REFERENCES dw.dim_competition,
    coach_name        VARCHAR(80),
    stadium_name      VARCHAR(80),
    stadium_seats     INTEGER,
    valid_from        DATE        NOT NULL,
    valid_to          DATE        NOT NULL DEFAULT DATE '9999-12-31',
    is_current        BOOLEAN     NOT NULL DEFAULT true,
    UNIQUE (tm_club_id, valid_from)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_team_current
    ON dw.dim_team (tm_club_id) WHERE is_current;

-- SCD Type 1: only the name is known; spelling fixes overwrite.
-- Referee is published for English leagues only -> others use key -1.
CREATE TABLE IF NOT EXISTS dw.dim_referee (
    referee_key   INTEGER     PRIMARY KEY,
    referee_name  VARCHAR(60) NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- DW LAYER – FACTS
-- ---------------------------------------------------------------------

-- GRAIN: one row per league match (one fixture between a home and an
-- away team in one competition and season), as published by
-- football-data.co.uk.  Transaction fact, rows are corrected (upserted)
-- if the source revises stats/odds after the first load.
CREATE TABLE IF NOT EXISTS dw.fact_match (
    match_key              BIGINT      PRIMARY KEY,
    date_key               INTEGER     NOT NULL REFERENCES dw.dim_date,
    season_key             SMALLINT    NOT NULL REFERENCES dw.dim_season,
    competition_key        SMALLINT    NOT NULL REFERENCES dw.dim_competition,
    home_team_key          INTEGER     NOT NULL REFERENCES dw.dim_team,   -- role-playing
    away_team_key          INTEGER     NOT NULL REFERENCES dw.dim_team,   -- role-playing
    referee_key            INTEGER     NOT NULL REFERENCES dw.dim_referee,
    value_snapshot_date_key INTEGER    NOT NULL REFERENCES dw.dim_date,   -- which TM snapshot was used
    kickoff_time           TIME,
    full_time_result       CHAR(1)     NOT NULL CHECK (full_time_result IN ('H','D','A')), -- degenerate
    -- additive measures
    home_goals             SMALLINT    NOT NULL CHECK (home_goals BETWEEN 0 AND 20),
    away_goals             SMALLINT    NOT NULL CHECK (away_goals BETWEEN 0 AND 20),
    home_ht_goals          SMALLINT,
    away_ht_goals          SMALLINT,
    home_points            SMALLINT    NOT NULL,   -- 3/1/0, derived
    away_points            SMALLINT    NOT NULL,
    home_shots             SMALLINT,
    away_shots             SMALLINT,
    home_shots_on_target   SMALLINT,
    away_shots_on_target   SMALLINT,
    home_corners           SMALLINT,
    away_corners           SMALLINT,
    home_fouls             SMALLINT,
    away_fouls             SMALLINT,
    home_yellow_cards      SMALLINT,
    away_yellow_cards      SMALLINT,
    home_red_cards         SMALLINT,
    away_red_cards         SMALLINT,
    home_xg                NUMERIC(4,2),           -- NULL before 2026/27
    away_xg                NUMERIC(4,2),
    -- non-additive measures (average with care)
    odds_home              NUMERIC(6,2) CHECK (odds_home > 1),  -- market avg, pre-match
    odds_draw              NUMERIC(6,2) CHECK (odds_draw > 1),
    odds_away              NUMERIC(6,2) CHECK (odds_away > 1),
    odds_home_close        NUMERIC(6,2),
    odds_draw_close        NUMERIC(6,2),
    odds_away_close        NUMERIC(6,2),
    -- semi-additive (from latest TM snapshot on/before match date)
    home_squad_value_eur   BIGINT,
    away_squad_value_eur   BIGINT,
    -- lineage
    source_file            VARCHAR(20) NOT NULL,
    load_id                BIGINT      NOT NULL,
    CHECK (home_team_key <> away_team_key),
    CHECK (home_shots_on_target IS NULL OR home_shots IS NULL OR home_shots_on_target <= home_shots),
    CHECK (away_shots_on_target IS NULL OR away_shots IS NULL OR away_shots_on_target <= away_shots),
    UNIQUE (competition_key, date_key, home_team_key, away_team_key)
);
CREATE INDEX IF NOT EXISTS ix_fact_match_home ON dw.fact_match (home_team_key);
CREATE INDEX IF NOT EXISTS ix_fact_match_away ON dw.fact_match (away_team_key);
CREATE INDEX IF NOT EXISTS ix_fact_match_season ON dw.fact_match (season_key, competition_key);

-- GRAIN: one row per team per month-end snapshot date.
-- Periodic snapshot fact; squad value is semi-additive (sum across teams
-- on one date is fine, never sum across dates).
CREATE TABLE IF NOT EXISTS dw.fact_team_value_snapshot (
    snapshot_date_key      INTEGER   NOT NULL REFERENCES dw.dim_date,
    team_key               INTEGER   NOT NULL REFERENCES dw.dim_team,
    competition_key        SMALLINT  NOT NULL REFERENCES dw.dim_competition,
    squad_market_value_eur BIGINT    NOT NULL CHECK (squad_market_value_eur >= 0),
    valued_players         SMALLINT  NOT NULL,
    avg_player_value_eur   BIGINT    NOT NULL,
    max_player_value_eur   BIGINT    NOT NULL,
    days_since_last_valuation SMALLINT NOT NULL,  -- freshness indicator
    PRIMARY KEY (snapshot_date_key, team_key)
);

-- Unknown members so facts never need NULL foreign keys
INSERT INTO dw.dim_date VALUES (-1, DATE '1900-01-01', 1900, 1, 1, 'Unknown', 1, 1, 'Unknown', false)
    ON CONFLICT DO NOTHING;
INSERT INTO dw.dim_referee VALUES (-1, 'Unknown / not published') ON CONFLICT DO NOTHING;
