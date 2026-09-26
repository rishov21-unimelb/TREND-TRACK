# TASK: Build a Full-Stack Instagram Trend Tracker Application

## Objective
Build a complete, full-stack Instagram Trend Tracker web application with a modern visual UI, robust backend API, data scraper/mock pipeline, and production-grade documentation. The application must track trending audio, hashtags, reels formats, and engagement metrics over time.

---

## 1. Project Architecture & Stack

### Backend (`/server`):
- **Framework:** Node.js (Express) or Python (FastAPI).
- **Core Engine:**
  - Data ingestion module for trend scraping/parsing (or structured mock generation fallback when rate-limited).
  - Metrics processor calculating trend velocity score: $Velocity = \frac{\Delta \text{Engagement}}{\Delta \text{Time}} \times \text{Volume Ratio}$.
  - RESTful API endpoints serving trend analytics, historical time-series data, and category filtering.
- **Database:** PostgreSQL (with Prisma or SQLAlchemy) or SQLite for storing historical trend snapshots.

### Frontend (`/client`):
- **Framework:** React (Vite) + Tailwind CSS + Lucide Icons + Recharts / Chart.js.
- **Key UI/UX Features:**
  - **Dashboard Overview:** High-level cards for Top Trending Audio, Explosive Hashtags, and Viral Reels Formats.
  - **Analytics Charts:** Time-series charts showing engagement growth and reach projection.
  - **Filters & Search:** Filter trends by niche (e.g., Tech, Fitness, Fashion), audio type, and growth rate.
  - **Export Feature:** Export trend report summaries as CSV or JSON.

---

## 2. Directory Structure

```text
instagram-trend-tracker/
├── server/
│   ├── src/
│   │   ├── controllers/
│   │   ├── services/
│   │   ├── models/
│   │   ├── routes/
│   │   └── index.ts
│   ├── tests/
│   ├── package.json / requirements.txt
│   └── Dockerfile
├── client/
│   ├── src/
│   │   ├── components/
│   │   ├── pages/
│   │   ├── hooks/
│   │   └── App.jsx
│   ├── package.json
│   └── Dockerfile
├── docker-compose.yml
├── Makefile
└── README.md