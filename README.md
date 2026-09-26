# Instagram Trend Tracker

A full-stack tracker for Instagram trend signals — trending **audio**, **explosive hashtags** and **viral Reels formats** — with a velocity-scored ranking engine, historical time-series analytics and CSV/JSON report export.

```
React + Vite + Tailwind + Recharts   ──/api──>   Express + TypeScript   ──>   SQLite
        (client, :5173)                             (server, :4000)         (snapshot history)
```

---

## Table of contents

- [What it does](#what-it-does)
- [Quick start](#quick-start)
- [Architecture](#architecture)
- [Metrics methodology](#metrics-methodology)
- [The ingestion pipeline](#the-ingestion-pipeline)
- [API reference](#api-reference)
- [Data model](#data-model)
- [Configuration](#configuration)
- [Testing](#testing)
- [Design system](#design-system)
- [Make targets](#make-targets)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)

---

## What it does

**Dashboard**

- Headline KPIs: tracked trends, total engagement, accounts reached, average velocity, median daily growth.
- Three ranked panels — *Top trending audio*, *Explosive hashtags*, *Viral Reels formats* — each with an inline sparkline and per-day growth.
- Engagement growth over time with a metric switch (engagement / reach / volume / velocity).
- Momentum mix, engagement by niche (click a bar to filter), and biggest movers in both directions.

**Trend explorer**

- Every tracked trend in a sortable table: velocity, daily growth, engagement, engagement rate, reach, post volume, saturation and a 7-day sparkline.
- Filter by type, niche, audio type, momentum, minimum velocity and free-text search. Filters live in the URL, so any view is shareable.
- Click a row for a detail drawer: full metric set, rank within its cohort, observation window and a 7-day projection.

**Analytics**

- Engagement growth bucketed hourly or daily.
- *Velocity vs saturation* scatter — the "is this still early?" view — with bubble area for engagement.
- Velocity leaderboard and per-type comparison.

**Export**

- CSV (one row per trend, spreadsheet-ready) or JSON (filters, summary, metric definitions and the full dashboard overview). The export always matches the filters on screen.

---

## Quick start

### Requirements

| | Version | Why |
|---|---|---|
| Node.js | **≥ 22.5** (24 recommended) | the data layer uses the built-in `node:sqlite` driver — no native compilation, no `better-sqlite3` toolchain |
| npm | ≥ 10 | workspace-free, two independent packages |
| Docker | optional | only for `make up` |

### Local development

```bash
make install     # install both packages
make dev         # API on :4000, client on :5173
```

Open <http://localhost:5173>. The API self-seeds on first boot, so the dashboard is populated immediately — there is no separate bootstrap step.

Running the two halves separately:

```bash
make dev-server  # cd server && npm run dev
make dev-client  # cd client && npm run dev
```

The Vite dev server proxies `/api` to `http://localhost:4000`, so the browser only ever talks to one origin and CORS never enters the picture.

### Docker

```bash
make up          # build + start; client :8080, API :4000
make logs
make down
```

`docker compose` builds both images, runs the API against a named volume (`trend-data`) so snapshot history survives rebuilds, and serves the client through nginx, which proxies `/api` to the API container and falls back to `index.html` for deep links.

### Useful one-offs

```bash
make seed        # backfill history if the database is empty
make reseed      # wipe and regenerate from the configured seed
make ingest      # run a single ingestion cycle
make test        # backend test suite
make build       # compile the API and bundle the client
```

---

## Architecture

```text
instagram-trend-tracker/
├── server/
│   ├── src/
│   │   ├── config/env.ts              # typed, defaulted environment
│   │   ├── controllers/               # HTTP shape only: no business logic
│   │   ├── db/
│   │   │   ├── client.ts              # node:sqlite handle, transactions
│   │   │   ├── schema.sql             # tables, indexes, latest-snapshot view
│   │   │   └── migrate.ts
│   │   ├── middleware/                # validation (zod) + error mapping
│   │   ├── models/                    # SQL lives here and nowhere else
│   │   ├── routes/                    # route tables per resource
│   │   ├── services/
│   │   │   ├── ingestion/
│   │   │   │   ├── catalog.ts         # the synthetic trend vocabulary
│   │   │   │   ├── mock.generator.ts  # deterministic dataset generator
│   │   │   │   ├── scraper.service.ts # live fetch + graceful degradation
│   │   │   │   └── ingestion.service.ts
│   │   │   ├── metrics.service.ts     # the velocity engine (pure functions)
│   │   │   ├── trend.service.ts       # read model: filter, rank, paginate
│   │   │   ├── analytics.service.ts   # dashboard aggregations
│   │   │   └── export.service.ts      # CSV / JSON reports
│   │   ├── scripts/                   # seed + ingest CLIs
│   │   ├── utils/                     # csv, time, seeded rng, numbers
│   │   └── index.ts                   # bootstrap, scheduler, shutdown
│   ├── tests/                         # vitest + supertest (66 tests)
│   └── Dockerfile
├── client/
│   ├── src/
│   │   ├── components/
│   │   │   ├── charts/                # Recharts wrappers + chart chrome
│   │   │   ├── dashboard/             # KPI row, top panels, movers
│   │   │   ├── layout/                # shell, nav, theme toggle
│   │   │   ├── trends/                # filter bar, table, drawer, export
│   │   │   └── ui/                    # primitives (tiles, badges, inputs)
│   │   ├── hooks/                     # data fetching, filters, theme, colours
│   │   ├── lib/                       # api client, formatting, viz tokens
│   │   ├── pages/                     # Dashboard, Trends, Analytics
│   │   └── App.jsx
│   ├── nginx.conf
│   └── Dockerfile
├── docker-compose.yml
├── Makefile
└── README.md
```

### Design decisions worth knowing

**SQL stays in `models/`.** Services never write SQL and models never compute metrics. The one deliberate exception to "filter in the database" is velocity: it is a *derived* value, so filtering and sorting on velocity/momentum happens in `trend.service.ts` after the metrics are computed. The working set is a few hundred rows, which makes this both simpler and faster than expressing the formula in SQL.

**`node:sqlite` over an ORM.** The schema is three tables. Prisma or SQLAlchemy would add a code-generation step and a native engine download for no benefit at this size, and `better-sqlite3` needs a C++ toolchain that many machines (including Windows without Visual Studio) do not have. `node:sqlite` ships with Node ≥ 22.5.

**Cohorts are per trend type.** Audio, hashtags and formats operate at different orders of magnitude, so volume is normalised *within* a type. A hashtag with 900k posts does not automatically outrank an audio clip that is genuinely accelerating.

**Filters live in the URL.** One filter row scopes the whole page; every chart and table renders against the same slice, and a filtered view can be pasted to a colleague.

---

## Metrics methodology

### Velocity

The headline ranking metric, exactly as specified:

$$
\text{Velocity} = \frac{\Delta \text{Engagement}}{\Delta \text{Time (hours)}} \times \text{VolumeRatio}
$$

- **ΔEngagement** — change in `likes + comments + shares + saves` between two observations.
- **ΔTime** — hours between them. A non-positive interval yields `0`, never `Infinity`.
- **VolumeRatio** — `posts / averagePostsInItsType`, clamped to `[0.1, 5]` so one outlier cannot dominate the ranking.

The score reads as *weighted engagement gained per hour*.

### The baseline window

The comparison snapshot is not simply "the previous row" — it is the newest snapshot at least `METRIC_BASELINE_HOURS` (default 24) older than the latest one, falling back to the previous row for trends too young to have one.

This matters: consecutive snapshots can be minutes apart, and their per-capture jitter would otherwise dominate the reading. Measuring against a fixed window makes velocity comparable across trends regardless of how often ingestion ran.

### Momentum

| Label | Condition |
|---|---|
| **Explosive** | daily growth ≥ 12% **and** velocity ≥ 250 |
| **Rising** | daily growth ≥ 3% |
| **Steady** | daily growth ≥ −0.5% |
| **Cooling** | below that |

Classification runs on the **daily** growth rate — window growth normalised to 24h — because that is scale-free: a small audio clip and a 900k-post hashtag are judged on the same axis. The velocity floor then stops a statistically noisy micro-trend from being labelled explosive on the back of a tiny absolute gain. All four thresholds are environment variables.

### Other derived values

| Metric | Definition |
|---|---|
| `dailyGrowthPct` | window growth normalised to 24h, clamped to `[-95%, +400%]` |
| `engagementRate` | engagement ÷ plays (or reach when plays are absent), as a percentage |
| `projectedReach7d` | reach compounded 7 days forward at the daily rate, clamped to ±60%/day |
| `saturation` | post volume as a percentage of the largest volume in its type |
| `volumeRatio` | see above — the weighting term in the velocity formula |

A projection is an extrapolation, not a forecast; the UI labels it as such and draws it as a dashed arm.

### Time-series aggregation

Engagement and reach are cumulative **levels**, not per-period flows. Each bucket therefore takes the *latest snapshot per trend* inside it and sums across trends. Summing every snapshot in the bucket would make the series depend on how often ingestion happened to run that day — a regression test covers exactly this.

---

## The ingestion pipeline

Instagram exposes no stable public endpoint for trend discovery, and unauthenticated requests are aggressively rate-limited. The tracker therefore treats **structured generation as a first-class ingestion source**, not a stub:

```
runIngestionCycle()
   ├─ fetchLiveTrends()            INGESTION_MODE=live + INGESTION_SOURCE_URL
   │     ├─ ok               ──>   validate with zod ──> upsert trends + snapshots   [success]
   │     ├─ 429 / 403        ──>   rate_limited          ┐
   │     ├─ network / timeout──>   unavailable           ├──> generator fallback     [degraded]
   │     └─ bad payload      ──>   invalid_payload       ┘
   └─ INGESTION_MODE=mock    ──>   generator                                         [success]
```

Every run is recorded in `ingestion_runs` with its status and message, surfaced in the UI's provenance strip — a degraded run silently filling the dashboard would be misleading, so the app always says where its numbers came from.

### The generator

Each trend gets a growth **archetype** — `breakout`, `climber`, `plateau`, `fading` or `spike` — which shapes a bounded curve across the whole window (a breakout multiplies ~6–22× over a month; a fading trend loses ground). Bounding the *window* rather than compounding a per-step rate is what keeps a 30-day series in a realistic range.

Each trend also carries a stable **audience profile** (interaction split, plays per interaction, reach fraction). Those ratios belong to the trend, not the observation — redrawing them per snapshot would make reach and plays jitter between consecutive captures and turn every derived chart into noise.

The whole pipeline is seeded: **same seed in, same dataset out**, which keeps tests, demos and screenshots stable.

### Pointing at a real source

Set `INGESTION_MODE=live` and `INGESTION_SOURCE_URL=https://your-collector/trends`. The endpoint must return:

```json
{
  "capturedAt": "2026-09-26T10:00:00.000Z",
  "trends": [
    {
      "id": "hashtag-aitools",
      "type": "hashtag",
      "name": "#aitools",
      "niche": "Tech",
      "posts": 184203,
      "likes": 920144,
      "comments": 41002,
      "shares": 28114,
      "saves": 19883,
      "plays": 14200000,
      "reach": 7100000
    }
  ]
}
```

Anything that fails the schema is rejected before it reaches the database, and the cycle degrades to the generator rather than writing partial data.

---

## API reference

Base URL: `http://localhost:4000/api`. Every response is wrapped in `{ data, meta? }`; every error in `{ error: { status, message, details? } }`.

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/health` | Liveness plus row counts |
| `GET` | `/` | Self-describing endpoint index |
| `GET` | `/trends` | Filterable, sortable trend list with derived metrics |
| `GET` | `/trends/filters` | Filter values present in the dataset |
| `GET` | `/trends/:id` | One trend with history, projection and ranks |
| `GET` | `/trends/:id/history` | Raw snapshot series for one trend |
| `GET` | `/analytics/overview` | Dashboard payload (KPIs, top panels, breakdowns) |
| `GET` | `/analytics/timeseries` | Aggregated engagement/reach/volume series |
| `GET` | `/analytics/leaderboard` | Velocity ranking |
| `GET` | `/analytics/definitions` | Metric formulas, as served to the UI |
| `POST` | `/ingest/run` | Run one ingestion cycle |
| `POST` | `/ingest/bootstrap` | Backfill history (`?force=true` to re-seed) |
| `GET` | `/ingest/status` | Provenance and recent runs |
| `GET` | `/export` | CSV or JSON report |

### `GET /trends`

| Query | Values | Default |
|---|---|---|
| `type` | `audio` · `hashtag` · `format` | — |
| `niche` | `Tech` · `Fitness` · `Fashion` · `Food` · `Travel` · `Beauty` · `Gaming` · `Finance` · `Music` · `Comedy` | — |
| `audioType` | `original` · `remix` · `trending_song` · `voiceover` · `sound_effect` | — |
| `formatKind` | `POV` · `Transition` · `Tutorial` · … | — |
| `momentum` | `explosive` · `rising` · `steady` · `cooling` | — |
| `minVelocity`, `minGrowth` | number | — |
| `search` | free text (name, creator, niche) | — |
| `sort` | `velocity` · `growth` · `engagement` · `reach` · `volume` · `engagementRate` · `name` · `discoveredAt` | `velocity` |
| `order` | `asc` · `desc` | `desc` |
| `limit`, `offset` | 1–500, ≥ 0 | 25, 0 |

```bash
curl "http://localhost:4000/api/trends?type=hashtag&momentum=explosive&sort=growth&limit=5"
```

```jsonc
{
  "data": [
    {
      "id": "hashtag-deadpanhumor-26",
      "name": "#deadpanhumor",
      "type": "hashtag",
      "niche": "Comedy",
      "metrics": {
        "engagement": 13291147,
        "engagementDelta": 3110285,
        "hoursElapsed": 24,
        "volumeRatio": 5,
        "velocityScore": 647851.04,
        "growthRatePct": 30.54,
        "dailyGrowthPct": 30.54,
        "momentum": "explosive",
        "engagementRate": 11.08,
        "reach": 12428869,
        "projectedReach7d": 79112004,
        "saturation": 100,
        "capturedAt": "2026-09-26T09:20:53.810Z"
      },
      "sparkline": [{ "capturedAt": "…", "engagement": 168351783 }]
    }
  ],
  "meta": {
    "total": 17,
    "limit": 5,
    "offset": 0,
    "summary": { "trends": 17, "totalEngagement": 39398115, "averageVelocity": 43798, "explosive": 17, "rising": 0, "cooling": 0 },
    "filters": { "type": "hashtag", "momentum": "explosive", "sort": "growth", "order": "desc" }
  }
}
```

### Time ranges

`range` accepts `24h`, `7d`, `4w`, `3m` or `all`; `granularity` accepts `hour` or `day`. Anything else is a `400` with the offending field named.

### `GET /export`

Accepts every `/trends` filter plus `format=csv|json` and `includeOverview=true`. Responds with `Content-Disposition: attachment` and a timestamped filename; `Access-Control-Expose-Headers` is set so a `fetch()`-based download can read it.

```bash
curl -OJ "http://localhost:4000/api/export?format=csv&niche=Tech"
curl "http://localhost:4000/api/export?format=json&momentum=explosive" | jq .summary
```

The JSON envelope carries `metricDefinitions`, so an exported report explains its own columns.

---

## Data model

```sql
trends              -- identity of a trend
  id, slug, type, name, niche, creator, audio_type, format_kind,
  region, source, discovered_at, last_seen_at, is_active, metadata

trend_snapshots     -- the time series every metric is derived from
  id, trend_id, captured_at, posts, likes, comments, shares,
  saves, plays, reach, engagement        UNIQUE (trend_id, captured_at)

ingestion_runs      -- provenance
  id, started_at, finished_at, source, mode, trends_seen,
  snapshots_written, status, message
```

Indexes cover the hot paths (`type`, `niche`, `is_active`, `(trend_id, captured_at DESC)`), and a `latest_snapshots` view exposes the newest observation per trend. Snapshot inserts are `INSERT OR IGNORE` inside a transaction, so re-running a cycle is idempotent for a given timestamp.

---

## Configuration

Copy `server/.env.example` to `server/.env`. All values have working defaults.

| Variable | Default | Purpose |
|---|---|---|
| `PORT` / `HOST` | `4000` / `0.0.0.0` | listen address |
| `DATABASE_URL` | `data/trends.db` | SQLite path; `:memory:` for tests |
| `CORS_ORIGINS` | `localhost:5173,4173` | comma-separated allow-list (`*` mirrors the origin) |
| `INGESTION_MODE` | `mock` | `mock` or `live` |
| `INGESTION_SOURCE_URL` | — | collector endpoint for live mode |
| `INGESTION_SEED` | `20260926` | determinism seed |
| `INGESTION_TREND_COUNT` | `72` | trends to generate |
| `INGESTION_HISTORY_DAYS` | `30` | history depth |
| `INGESTION_SNAPSHOTS_PER_DAY` | `2` | capture cadence |
| `INGESTION_SCHEDULE_ENABLED` | `false` | in-process ingestion scheduler |
| `METRIC_BASELINE_HOURS` | `24` | velocity comparison window |
| `METRIC_EXPLOSIVE_DAILY_GROWTH_PCT` | `12` | explosive threshold |
| `METRIC_RISING_DAILY_GROWTH_PCT` | `3` | rising threshold |
| `METRIC_EXPLOSIVE_VELOCITY_FLOOR` | `250` | anti-noise floor |
| `RATE_LIMIT_MAX` | `300` / min | per-IP API limit |

Client (`client/.env`): `VITE_API_URL` (default `/api`) and `VITE_API_PROXY` (default `http://localhost:4000`).

---

## Testing

```bash
make test        # 66 tests across 3 files
```

| Suite | Covers |
|---|---|
| `tests/metrics.test.ts` | the velocity formula, volume-ratio clamping, growth normalisation, momentum boundaries, projection clamps, empty/single-snapshot cases |
| `tests/generator.test.ts` | determinism, type coverage, series length and ordering, magnitude bounds, engagement-breakdown consistency, CSV escaping, range parsing |
| `tests/api.test.ts` | every endpoint: filtering, sorting, pagination, validation `400`s, `404`s, export headers and payload shape, ingestion cycles, and the bucket-aggregation regression |

Each test file runs against its own in-memory database (`DATABASE_URL=:memory:`), so suites cannot bleed state into one another.

---

## Design system

The interface is built on a small set of semantic tokens (`client/src/index.css`) declared once for light and re-declared for dark under both the OS preference and an explicit `data-theme` stamp, so the in-app toggle wins in both directions. The toggle cycles **dark → light → system**.

Chart colour follows the job it does, not decoration:

- **Categorical** (slots 1–3: blue / orange / aqua) for the three trend types — validated all-pairs for colour-vision deficiency in both themes, which is what a scatter needs since any two marks can end up adjacent.
- **Sequential** (one blue ramp, light → dark) for magnitude — niche bars, area fills, sparklines.
- **Diverging** (blue → grey → red) for momentum, because it has polarity. It is always paired with an icon and a label, so state never depends on colour alone.

Every chart ships a legend when it has two or more series, a table-view twin (so no value is reachable by hover only), solid hairline gridlines, 2px lines, 4px rounded bar ends, and a container sized to include the axis band. Charts read their colours from the resolved CSS custom properties, so a theme change repaints them correctly.

---

## Make targets

| Target | What it does |
|---|---|
| `make help` | list every target |
| `make install` | install both packages |
| `make dev` | API + client together |
| `make seed` / `make reseed` | backfill / regenerate history |
| `make ingest` | one ingestion cycle (cron-friendly) |
| `make test` / `make typecheck` | backend checks |
| `make build` / `make preview` | compile and serve the bundle |
| `make up` / `make down` / `make logs` | Docker stack |
| `make reset` | drop the local database and regenerate |
| `make clean` | remove build output, modules and the Docker volume |

---

## Troubleshooting

**`Could not find any Visual Studio installation`** — you are on an older checkout that still pulls `better-sqlite3`. The current data layer uses `node:sqlite`; run `rm -rf server/node_modules server/package-lock.json && cd server && npm install`.

**Client loads but every panel errors** — the API is not running, or is on another port. Check `curl localhost:4000/api/health`, and `VITE_API_PROXY` if you moved it.

**`ERR_ERL_PERMISSIVE_TRUST_PROXY` or rate limiting behind a proxy** — set `RATE_LIMIT_MAX` higher, or terminate the proxy in front of nginx rather than the API.

**Dashboard looks empty after a rebuild** — the SQLite file is gone. `make seed` restores it; under Docker the `trend-data` volume preserves it (`make clean` deletes it deliberately).

**Charts render with grey marks** — a theme token failed to resolve. Hard-reload; the colours are read from CSS custom properties on `<html>`.

---

## Known limitations

- **The default dataset is generated, not scraped.** This is deliberate and the UI says so on every screen. Point `INGESTION_SOURCE_URL` at a real collector to track live data.
- **Velocity needs two observations.** A trend seen only once reports zero velocity until the next cycle, by design — the alternative is inventing a baseline.
- **Projections are extrapolations.** They compound the observed daily rate with a ±60%/day clamp; they do not model seasonality, platform pushes or saturation.
- **Filtering and sorting on derived metrics happen in memory.** Correct and fast for hundreds to low thousands of trends; past that, materialise the metrics into a table on ingest.
- **No authentication.** The API is unauthenticated and intended to run behind your own gateway.

---

This project is not affiliated with, endorsed by, or connected to Instagram or Meta. If you connect it to a live source, make sure that source complies with the relevant platform terms.
