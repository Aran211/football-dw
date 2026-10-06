"""Builds Report.pdf (max 3 pages) for Project 1.  Edit AUTHOR / REPO / CHAT below."""
import sys
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
                                Image, KeepTogether)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from PIL import Image as PILImage

AUTHOR = sys.argv[1] if len(sys.argv) > 1 else "[Your name]"
REPO = sys.argv[2] if len(sys.argv) > 2 else "https://github.com/[user]/football-dw"
CHAT = sys.argv[3] if len(sys.argv) > 3 else "[link to the shared Claude chat]"
OUT = sys.argv[4] if len(sys.argv) > 4 else "Report.pdf"

F = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("Sans", F + "DejaVuSansCondensed.ttf"))
pdfmetrics.registerFont(TTFont("Sans-B", F + "DejaVuSansCondensed-Bold.ttf"))
pdfmetrics.registerFont(TTFont("Sans-I", F + "DejaVuSansCondensed-Oblique.ttf"))
pdfmetrics.registerFont(TTFont("Mono", F + "DejaVuSansMono.ttf"))
from reportlab.lib.fonts import addMapping
addMapping("Sans", 0, 0, "Sans"); addMapping("Sans", 1, 0, "Sans-B"); addMapping("Sans", 0, 1, "Sans-I")

INK = colors.HexColor("#1f2a37"); ACC = colors.HexColor("#33415c"); RULE = colors.HexColor("#c9d1dc")
HEAD_BG = colors.HexColor("#e8edf4")

body = ParagraphStyle("b", fontName="Sans", fontSize=8.3, leading=10.4, textColor=INK, spaceAfter=2)
small = ParagraphStyle("s", parent=body, fontSize=7.4, leading=9.0, spaceAfter=0)
h1 = ParagraphStyle("h1", fontName="Sans-B", fontSize=14, leading=17, textColor=ACC, spaceAfter=1)
meta = ParagraphStyle("m", parent=body, fontSize=8, textColor=colors.HexColor("#5b6b7b"), spaceAfter=4)
h2 = ParagraphStyle("h2", fontName="Sans-B", fontSize=10, leading=12.5, textColor=ACC, spaceBefore=5, spaceAfter=2, keepWithNext=1)
bul = ParagraphStyle("bul", parent=body, leftIndent=9, bulletIndent=1, spaceAfter=0.6)
code = ParagraphStyle("c", fontName="Mono", fontSize=6.5, leading=7.9, textColor=INK,
                      backColor=colors.HexColor("#f5f7fa"), borderPadding=3, leftIndent=3, rightIndent=3)

def P(t, s=body): return Paragraph(t, s)
def B(t): return Paragraph(t, bul, bulletText="•")

def table(rows, widths, fs=7.4):
    st = ParagraphStyle("t", parent=small, fontSize=fs, leading=fs * 1.22)
    sth = ParagraphStyle("th", parent=st, fontName="Sans-B")
    data = [[Paragraph(str(c), sth if i == 0 else st) for c in r] for i, r in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
        ("LINEBELOW", (0, 0), (-1, 0), 0.6, ACC),
        ("LINEBELOW", (0, 1), (-1, -1), 0.3, RULE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 1.6), ("BOTTOMPADDING", (0, 0), (-1, -1), 1.6),
        ("LEFTPADDING", (0, 0), (-1, -1), 3), ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ]))
    return t

def img(path, width):
    w, h = PILImage.open(path).size
    return Image(path, width=width, height=width * h / w)

W = A4[0] - 2 * 15 * mm
s = []

# ---------------- Title ----------------
s += [P("Project 1 – Data Architecture &amp; Modeling: European Football Results DW", h1),
      P(f"LTAT.02.007 Data Engineering, University of Tartu, autumn 2026 · Group 14 · Author: {AUTHOR} (individual project) · "
        f"Repository: {REPO}", meta)]

# ---------------- 1. Business brief ----------------
s += [P("1. Business brief", h2),
      P("<b>Objective.</b> Build an analytics model that shows how squad market value and bookmaker expectations "
        "translate into actual results in Europe's top-5 football leagues (2023/24 – 2026/27)."),
      P("<b>Stakeholders.</b> Club performance &amp; recruitment analysts (value for money of a squad), "
        "sports-betting / trading analysts (how well the market prices matches), sports journalists and "
        "fans' media (data-driven stories on home advantage, referees, upsets)."),
      P("<b>KPIs.</b> (1) <i>Points per €100 m of squad value</i> – efficiency of spending; "
        "(2) <i>Favourite hit rate</i> – % of matches won by the pre-match bookmaker favourite (and its complement, upset rate); "
        "(3) <i>Home advantage</i> – home win % and average home-minus-away goal difference."),
      P("<b>Business questions</b> (each has a demo SQL query, section 7):")]
qs = ["Q1 Which teams over- or under-perform relative to their squad market value in each season?",
      "Q2 How often does the bookmaker favourite win, and which league is the least predictable?",
      "Q3 How large is home advantage per league, and is it changing across seasons?",
      "Q4 Which teams convert chances best (goals per shot on target), and does it go with more points?",
      "Q5 Do referees differ in cards and fouls per match? (referees are published for England only)",
      "Q6 Did a team's results change after a coach change? (uses SCD2 history of dim_team)",
      "Q7 Which were the biggest upsets (winners with the longest pre-match odds)?"]
s += [B(q) for q in qs]

# ---------------- 2. Datasets ----------------
s += [P("2. Datasets", h2),
      table([["Dataset", "Content (grain)", "Size", "Update / access", "Why"],
             ["A. football-data.co.uk<br/>mmz4281/&lt;season&gt;/&lt;div&gt;.csv",
              "One row per league match: date, kick-off, teams, full/half-time score, shots, shots on target, "
              "corners, fouls, cards, referee (England), xG (from 2026/27, most leagues), 1X2 odds of many bookmakers + market "
              "average, opening and closing",
              "~1,750 matches per season across the 5 leagues (3×380 + 2×306) → ~5,500 rows for 3 full seasons + current; 100+ columns",
              "CSV over HTTP, free, no key; updated during the season about twice a week",
              "Results, match events and the market's expectation per match"],
             ["B. Transfermarkt dataset<br/>(dcaribou/transfermarkt-datasets, Kaggle &amp; GitHub)",
              "12 joinable tables; used: <i>clubs</i> (stadium, league), <i>players</i> (current club, "
              "position, value), <i>player_valuations</i> (one row per valuation event), <i>games</i> (manager of each club per match → coach history)",
              "players 50,000+ rows × 20+ cols; valuations 650,000+; games 88,000+ × 20+ cols; clubs 790+",
              "CSV files, weekly pipeline – <b>paused since July 2026</b> (valuations end 2026-06-12)",
              "Squad market value and team attributes (coach, stadium) the match files lack"]],
            [32 * mm, 58 * mm, 36 * mm, 30 * mm, W - 156 * mm]),
      Spacer(1, 2),
      P("<b>Sources.</b> [A] football-data.co.uk, https://www.football-data.co.uk/data.php (key: /notes.txt); "
        "[B] D. Cereijo, transfermarkt-datasets, https://github.com/dcaribou/transfermarkt-datasets, "
        "Kaggle: https://www.kaggle.com/datasets/davidcariboo/player-scores (data © Transfermarkt.com).", small),
      Spacer(1, 2),
      P("<b>Combining the datasets.</b> Sources share no key: team names differ (\"Man United\" vs. \"Manchester "
        "United\", \"Ath Madrid\" vs. \"Atlético de Madrid\"). A curated bridge <i>staging.team_name_map</i> "
        "(exact → fuzzy → manual match, reviewed flag) maps every football-data name to a Transfermarkt "
        "<i>club_id</i>; a DQ test blocks the load if any name is unmapped. Player valuations are aggregated per club "
        "and month-end into a squad-value snapshot, which is attached to each match as of the match date. "
        "<b>Risk:</b> because Transfermarkt updates are paused, 2026/27 matches use the June 2026 snapshot; this "
        "is exposed through <i>value_snapshot_date_key</i> and a freshness check rather than hidden; coach changes after "
        "July 2026 are captured once upstream resumes.")]

# ---------------- 3. Tooling ----------------
s += [P("3. Tooling by lifecycle stage (tools covered in the course)", h2),
      table([["Stage", "Tool", "Use in this project"],
             ["Ingestion", "Python + Apache Airflow", "DAGs download CSVs (requests / Kaggle API), write to landing zone, COPY into raw schema; retries, scheduling, alerting"],
             ["Storage", "Docker (volume) + PostgreSQL", "Landing zone of immutable files per load date; PostgreSQL holds raw, staging and dw schemas"],
             ["Transformation", "dbt", "Staging models (cast, de-dup, mapping), dbt snapshots for SCD2 dim_team, mart models for the star schema, dbt tests = DQ gate"],
             ["Serving / BI", "Superset, Streamlit", "Dashboards for KPIs; Streamlit page for 'team vs. its value' exploration"],
             ["Packaging", "Docker Compose", "One stack: postgres, airflow, dbt, superset – reproducible for Project 2"],
             ["Not used", "MongoDB, Neo4j", "Both sources are already tabular; no document or graph workload needed"]],
            [24 * mm, 40 * mm, W - 64 * mm])]

# ---------------- 4. Architecture ----------------
s += [P("4. Data architecture", h2),
      img("diagrams/architecture.png", W * 0.82),
      Spacer(1, 2),
      table([["Flow step", "Method", "Frequency"],
             ["Source → ingestion (matches)", "Batch file pull over HTTP (current-season CSV per league); full history back-filled once", "Mon + Thu 06:00 during season (matches are played weekends + midweek)"],
             ["Source → ingestion (values)", "Batch file pull via Kaggle API (clubs, players, player_valuations, games)", "Monthly (1st day); source itself updates at most weekly"],
             ["Landing → raw", "COPY into append-only raw tables with load_id; files kept for replay", "After each pull"],
             ["raw → staging → dw", "dbt run: incremental fact_match upsert on natural key, dbt snapshot for dim_team, full rebuild of small dims", "Triggered by Airflow after each load"],
             ["dw → reporting", "Superset / Streamlit read dw.* directly", "On demand"]],
            [36 * mm, 88 * mm, W - 124 * mm]),
      Spacer(1, 2),
      P("<b>Data quality checks</b> (run as dbt tests; <i>error</i> stops the DAG, <i>warn</i> alerts): "
        "uniqueness of (division, date, home, away) and not-null on mandatory fields [error]; "
        "every team name mapped to a Transfermarkt club [error]; result letter consistent with the score [error]; "
        "odds &gt; 1.01 and shots on target ≤ shots [warn]; completeness – a finished season has "
        "n·(n−1) matches (380 / 306) [warn]; freshness – newest valuation ≤ 45 days old [warn, currently failing by design]. "
        "SQL in <i>sql/04_data_quality_checks.sql</i>.")]

# ---------------- 5. Data model ----------------
s += [P("5. Data model (star schema)", h2),
      img("diagrams/star_schema.png", W * 0.86),
      P("<b>Grain.</b> <i>fact_match</i>: one row per league match (one fixture between a home and an away team "
        "in one competition and season), as published by football-data.co.uk. It is a transaction fact; dim_team "
        "is used twice (role-playing home/away), result is a degenerate dimension. Goals, shots, cards and points "
        "are additive; odds are non-additive (averaged or converted to implied probabilities); squad value is "
        "semi-additive. <i>fact_team_value_snapshot</i>: one row per team per month-end – a periodic snapshot, "
        "because valuations arrive irregularly per player and analysts need a consistent squad value at a point in time."),
      KeepTogether(table([["Dimension", "SCD type", "Justification"],
             ["dim_team", "Type 2 (coach, league); Type 1 (stadium seats)",
              "Coaches change and teams are promoted/relegated; Q6 and season comparisons need the version valid on "
              "match day, so changes add a new row (valid_from/valid_to/is_current). History is back-filled from the "
              "manager name per match (TM games) and the league per season (match files); new changes via dbt snapshot. "
              "Stadium capacity corrections are not analytically meaningful → overwrite."],
             ["dim_competition", "Type 1", "Reference data (codes, country, tier). A sponsor/name change should "
              "relabel all history, not split it."],
             ["dim_referee", "Type 1", "Only the name is known; corrections of spelling overwrite. Unknown member −1 "
              "for leagues without referee data."],
             ["dim_date, dim_season", "Static", "Generated calendars; values never change after creation."]],
            [26 * mm, 36 * mm, W - 62 * mm]))]

# ---------------- 6. Data dictionary ----------------
COLS = {}
for line in open("/tmp/claude-0/cols.txt"):
    sc, tn, c, ty = line.rstrip("\n").split("|")
    COLS.setdefault(f"{sc}.{tn}", []).append(f"<b>{c}</b> {ty.replace('TIMESTAMP','TIMESTAMPTZ') if False else ty}")
DICT = [
 ("dw.fact_match", "Transaction fact, 1 row per league match. Keys *_key are FKs (home/away → dim_team version valid on match day; "
  "referee −1 = not published; value_snapshot_date_key = month-end of squad values used). full_time_result H/D/A = degenerate dim. "
  "*_points 3/1/0 derived. xG NULL before 2026/27. odds_* = market-average decimal odds, pre-match and *_close. "
  "*_squad_value_eur = latest snapshot ≤ match date. source_file, load_id = lineage."),
 ("dw.fact_team_value_snapshot", "Periodic snapshot, 1 row per team per month-end. squad_market_value_eur = sum of latest player valuations "
  "(semi-additive); days_since_last_valuation = freshness."),
 ("dw.dim_team", "SCD2. team_key surrogate (−1 unknown); tm_club_id natural key; fd_team_name = spelling in match files; "
  "coach_name, current_competition_key tracked Type 2; stadium_* Type 1; valid_to 9999-12-31 for the current row."),
 ("dw.dim_competition", "SCD1. Codes of both sources (E0↔GB1, SP1↔ES1, I1↔IT1, D1↔L1, F1↔FR1); teams_per_season drives completeness check."),
 ("dw.dim_season", "Static. season_code as in source path ('2627'), season_label '2026/27', is_complete = all matches played."),
 ("dw.dim_date", "Static calendar, date_key yyyymmdd (−1 unknown), day_of_week ISO (1 = Monday)."),
 ("dw.dim_referee", "SCD1. Referee name as published (English leagues only)."),
 ("staging.team_name_map", "Bridge football-data team name → Transfermarkt club_id; match_method exact/fuzzy/manual, match_score 0–1 for fuzzy."),
]
s += [P("6. Data dictionary (all columns and types; per-column descriptions also in docs/data_dictionary.md)", h2),
      table([["Table", "Columns and data types", "Description / notes"]] +
            [[t, ", ".join(COLS[t]), d] for t, d in DICT],
            [27 * mm, 92 * mm, W - 119 * mm], fs=6.6)]

# ---------------- 7. Demo queries ----------------
s += [P("7. Demo queries", h2),
      P("All seven questions are answered in <i>sql/03_demo_queries.sql</i> (tested on PostgreSQL 16 with the sample "
        "data in <i>sql/02_sample_dml.sql</i>). A helper view <i>dw.v_team_match</i> unpivots each match into a home "
        "and an away row; it groups by the durable key tm_club_id so SCD2 versions roll up to one team. Example (Q2):"),
      Paragraph("""WITH fav AS (SELECT f.*, CASE WHEN odds_home &lt;= LEAST(odds_draw, odds_away) THEN 'H'<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;WHEN odds_away &lt;= LEAST(odds_home, odds_draw) THEN 'A' ELSE 'D' END AS favourite<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FROM dw.fact_match f WHERE odds_home IS NOT NULL)<br/>
SELECT c.competition_name, s.season_label, count(*) AS matches,<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;round(100.0*avg((favourite = full_time_result)::int),1) AS favourite_hit_rate_pct<br/>
FROM fav f JOIN dw.dim_competition c USING (competition_key) JOIN dw.dim_season s USING (season_key)<br/>
GROUP BY 1, 2 ORDER BY favourite_hit_rate_pct;""", code),
      Spacer(1, 3),
      P("Other queries: Q1 points per €100 m squad value per team/season; Q3 home/draw/away % and goal difference "
        "by league/season; Q4 goals per shot on target vs. points; Q5 cards per match by referee; Q6 points per "
        "match per coach version (SCD2); Q7 top-10 upsets by winner's odds.")]

# ---------------- Contribution + LLM ----------------
s += [P("Contribution and LLM disclosure", h2),
      table([["Member", "Role", "Contribution"],
             [AUTHOR, "All roles (individual project): business analysis, data sourcing, architecture, modelling, SQL, report", "100%"]],
            [40 * mm, W - 62 * mm, 22 * mm]),
      Spacer(1, 2),
      P(f"<b>LLM use.</b> Claude (Anthropic) was used to brainstorm the topic, check data source availability, "
        f"draft the schema, SQL, diagrams and this report; all output was reviewed and edited by the author. "
        f"Chat: {CHAT}")]

doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=15 * mm, rightMargin=15 * mm,
                        topMargin=12 * mm, bottomMargin=12 * mm,
                        title="Project 1 – Data Architecture & Modeling", author=AUTHOR)

def footer(c, d):
    c.saveState(); c.setFont("Sans", 7); c.setFillColor(colors.HexColor("#8794a3"))
    c.drawRightString(A4[0] - 15 * mm, 7 * mm, f"{d.page} / 3"); c.restoreState()

doc.build(s, onFirstPage=footer, onLaterPages=footer)
print("built", OUT)
