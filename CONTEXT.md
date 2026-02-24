# Haunted Asylum Research Database — Project Context

This document gives a complete picture of what is being built, how the database is structured, and how to continue the work in a new session. Read this before touching anything.

---

## Project Summary

A Postgres (Supabase) research database for cataloguing **haunted asylum / institutional tourism sites** with full auditable evidence trails. The goal is to classify sites against a structured rule framework (R1/R2/R3) by linking official web pages, local captures (screenshots/PDFs), TV appearances, YouTube videos, and review platform profiles to each site.

Ingestion is automated via a single Postgres RPC (`ingest_site`) that is fully idempotent — re-running the same payload is always safe.

---

## Infrastructure

| Component | Detail |
|---|---|
| Database | Supabase Postgres (project: `yyhdksrmxxerijfvuraa`) |
| Project URL | `https://yyhdksrmxxerijfvuraa.supabase.co` |
| Dashboard | `https://supabase.com/dashboard/project/yyhdksrmxxerijfvuraa` |
| Edge Function | `https://yyhdksrmxxerijfvuraa.supabase.co/functions/v1/ingest-site` |
| GitHub repo | `https://github.com/karennagrace/haunted-asylum-db` (private) |
| Local path | `C:\Users\K\haunted-asylum-db` |
| Supabase CLI | `C:\Users\K\bin\supabase.exe` |
| GitHub CLI | `C:\Program Files\GitHub CLI\gh.exe` |
| Researcher ID | `36339282-36e1-41b8-ad8b-bba0fff72e64` |

Credentials are in `.env` (gitignored). Do not commit `.env`.

---

## Rule Framework (R1 / R2 / R3)

The database is built around three classification rules. Every evidence item is tagged to one of these.

| Rule | Meaning |
|---|---|
| **R1** | Institution history — confirms the site was a real qualifying institution (asylum, hospital, school, etc.) |
| **R2** | Ticket/booking or authorization — confirms the public can pay to access the site for tourism |
| **R3** | Third-party corroboration — confirms the site has a visible presence in media, reviews, YouTube, TV, etc. |

---

## Enums

These are exact Postgres enum values. Use them verbatim in payloads.

### `doc_source`
`official` · `third_party` · `review` · `youtube` · `tv` · `reddit` · `other`

### `capture_kind`
`html` · `pdf` · `screenshot` · `text` · `other`

### `evidence_kind`
`r1_institution_history` · `r2_ticket_booking` · `r2_calendar_season` · `r2_authorization` · `r3_official_page` · `r3_third_party` · `r3_review_ecosystem` · `r3_youtube` · `r3_tv` · `r3_reddit`

### `official_page_category`
`history_about` · `tour_event` · `ticket_booking` · `rules_faq_waiver` · `schedule_calendar` · `other`

### `programming_type`
`ghost_tour` · `paranormal_investigation` · `flashlight_tour` · `haunted_attraction_halloween` · `after_hours_night_tour` · `dark_history_tour` · `other`

### `rule_code`
`R1` · `R2` · `R3`

### `yesno`
`Y` · `N`

---

## Table Structures

Tables already exist in Supabase. Do not recreate them.

### `sites`
The primary entity. One row per tourism site.

| Column | Type | Notes |
|---|---|---|
| `site_id` | uuid PK | `gen_random_uuid()` |
| `site_name` | text NOT NULL | |
| `official_site_url` | text UNIQUE | Natural dedup key |
| `country` | text | |
| `region` | text | State/province |
| `city` | text | |
| `address` | text | |
| `notes` | text | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | Updated on every upsert |

### `site_aliases`
Alternative names for a site.

| Column | Type | Notes |
|---|---|---|
| `site_alias_id` | uuid PK | |
| `site_id` | uuid FK → sites | |
| `alias` | text | **Column is `alias`, not `alias_name`** |

### `documents`
Web pages and documents associated with a site.

| Column | Type | Notes |
|---|---|---|
| `document_id` | uuid PK | |
| `site_id` | uuid FK → sites | |
| `source` | `doc_source` | |
| `url` | text | |
| `title` | text | |
| `publisher` | text | |
| `published_date` | date | Nullable |
| `official_category` | `official_page_category` | Nullable; only set for `source = 'official'` |

### `captures`
Local snapshots of documents (screenshots, PDFs, HTML saves).

| Column | Type | Notes |
|---|---|---|
| `capture_id` | uuid PK | |
| `document_id` | uuid FK → documents | |
| `captured_by` | uuid FK → researchers | Must be a valid researcher_id |
| `capture_ts` | timestamptz | When the capture was taken |
| `kind` | `capture_kind` | |
| `http_status` | int | e.g. 200 |
| `file_path` | text | Local disk path; future: Supabase Storage object path |
| `content_hash` | text | SHA-256 hex of the file. Required for dedup. |
| `text_excerpt` | text | Short excerpt from the page |
| `notes` | text | |

**Note:** `file_path` is plain text. When Supabase Storage is adopted later, swap local paths for Storage object paths — no schema change needed.

### `evidence_items`
Structured rule evidence linking sites to documents and/or captures.

| Column | Type | Notes |
|---|---|---|
| `evidence_id` | uuid PK | |
| `site_id` | uuid FK → sites | |
| `rule` | `rule_code` | R1, R2, or R3 |
| `evidence_type` | `evidence_kind` | Specific sub-type |
| `document_id` | uuid FK → documents | **Nullable** |
| `capture_id` | uuid FK → captures | **Nullable** |
| `evidence_date` | date | Date of the evidence (nullable) |
| `access_date` | date | Date researcher accessed it |
| `description` | text | Researcher's note on why this qualifies |

Evidence can be attached at two levels:
- **Capture-level**: both `document_id` and `capture_id` set — strongest evidence, tied to a saved snapshot
- **Document-level**: `document_id` set, `capture_id` NULL — document seen but not yet captured

### `tv_episodes`

| Column | Type | Notes |
|---|---|---|
| `tv_episode_id` | uuid PK | |
| `site_id` | uuid FK → sites | |
| `show_name` | text | |
| `season_number` | int | Use 0 for specials |
| `episode_number` | int | Use 0 for specials |
| `episode_title` | text | |
| `air_date` | date | |
| `synopsis` | text | |
| `channel` | text | |
| `viewers` | bigint | Nullable |
| `imdb_rating` | numeric(4,1) | Nullable |
| `imdb_quantity` | int | Number of IMDb votes; nullable |

### `youtube_videos`

| Column | Type | Notes |
|---|---|---|
| `youtube_video_id` | uuid PK | |
| `site_id` | uuid FK → sites | |
| `url` | text UNIQUE | |
| `video_title` | text | |
| `channel_name` | text | |
| `upload_date` | date | |
| `view_count` | bigint | |
| `like_count` | bigint | |
| `comment_count` | bigint | |
| `description_text` | text | |
| `duration` | text | ISO 8601, e.g. `PT42M17S` |
| `category` | text | |
| `channel_subscribers` | bigint | |

### `site_review_profiles`

| Column | Type | Notes |
|---|---|---|
| `site_review_profile_id` | uuid PK | |
| `site_id` | uuid FK → sites | |
| `platform_id` | uuid FK → review_platforms | |
| `profile_url` | text | |

### `review_platforms` (lookup, do not modify)

| platform_id | platform_name | platform_type |
|---|---|---|
| `27136a13-65da-4e03-995e-e60c33cecd10` | TripAdvisor | reviews |
| `71d104c1-b450-4f8e-ad2c-d7be3b8920a3` | Yelp | reviews |
| `e6432503-3900-4821-8df4-e9e8f6c27df7` | Google | reviews |
| `6dcb0833-aaa9-40b8-bb9a-a9725efa96d8` | Facebook | reviews |
| `18de7256-bd98-4002-a0f2-ccc495f05fb1` | Wanderlog | aggregator |
| `23d601bf-962b-4752-a8c3-2674cc0a5ba5` | HauntScout | aggregator |

### `researchers` (lookup, do not modify)

| researcher_id | Notes |
|---|---|
| `36339282-36e1-41b8-ad8b-bba0fff72e64` | Primary researcher (Karenna) |

---

## Unique Constraints / Indexes

All added via `sql/01_unique_constraints.sql`. These power the idempotent upserts.

| Table | Index/Constraint | Key Columns |
|---|---|---|
| `sites` | `uq_sites_official_url` | `official_site_url` |
| `site_aliases` | `uq_site_aliases` | `(site_id, alias)` |
| `documents` | `uq_documents_site_url` | `(site_id, url)` |
| `captures` | `uq_captures_doc_hash` | `(document_id, content_hash)` |
| `evidence_items` | `uq_evidence_natural_key` | `(site_id, rule, evidence_type, COALESCE(document_id, nil_uuid), COALESCE(capture_id, nil_uuid))` |
| `tv_episodes` | `uq_tv_episodes_natural_key` | `(site_id, show_name, season_number, episode_number)` |
| `youtube_videos` | existing unique | `url` |
| `site_review_profiles` | `uq_site_review_profiles` | `(site_id, platform_id, profile_url)` |

The `evidence_items` index uses `COALESCE(col, '00000000-0000-0000-0000-000000000000'::uuid)` as a sentinel for NULL FKs, enabling `ON CONFLICT` to work correctly when either FK is NULL.

---

## RPC Function: `ingest_site(payload jsonb)`

Defined in `sql/02_rpc_ingest_site.sql`. Deployed to Supabase.

**Purpose:** Single-call idempotent ingestion of a site and its entire corpus. All writes use `ON CONFLICT ... DO UPDATE` or `DO NOTHING`. Re-running with the same payload is always safe and returns the same `site_id`.

**Returns:** `{"ok": true, "site_id": "<uuid>"}` on success, `{"ok": false, "error": "...", "sqlstate": "..."}` on failure.

**Execution order inside the function:**
1. Upsert `sites` → captures `site_id`
2. Upsert `site_aliases`
3. For each document → upsert `documents` → for each capture → upsert `captures` → upsert capture-level `evidence_items` → upsert document-level `evidence_items`
4. Upsert `tv_episodes`
5. Upsert `youtube_videos`
6. For each review profile → upsert `site_review_profiles` → process nested review documents/captures/evidence

**Call from Supabase SQL Editor:**
```sql
SELECT ingest_site('{ ... }'::jsonb);
```

**Call via Edge Function (curl):**
```bash
curl -X POST https://yyhdksrmxxerijfvuraa.supabase.co/functions/v1/ingest-site \
  -H "Authorization: Bearer <service_role_key>" \
  -H "Content-Type: application/json" \
  -d @payloads/your_site.json
```

**Note:** The Edge Function uses a direct Postgres connection (`SUPABASE_DB_URL`) via the `postgresjs` Deno library, not the Supabase JS client. This avoids PostgREST schema cache issues. After deploying or modifying the RPC, run `NOTIFY pgrst, 'reload schema';` in the SQL Editor to refresh PostgREST.

---

## Payload Structure

Full JSON structure accepted by `ingest_site`. All top-level array keys are optional (omit or pass `[]` to skip that section).

```jsonc
{
  "researcher_id": "<uuid>",          // Required. Must exist in researchers table.

  "site": {
    "site_name": "...",               // Required.
    "official_site_url": "...",       // Required. Natural dedup key.
    "country": "US",
    "region": "...",                  // State/province
    "city": "...",
    "address": "...",
    "notes": "..."
  },

  "aliases": [                        // Array of strings
    "Alternate Name 1",
    "Alternate Name 2"
  ],

  "documents": [
    {
      "source": "official",           // doc_source enum
      "url": "https://...",           // Dedup key with site_id
      "title": "...",
      "publisher": "...",
      "published_date": "2024-01-15", // date string or null
      "official_category": "history_about", // official_page_category enum or null

      "captures": [                   // Optional. Add when you have a local file.
        {
          "capture_ts": "2025-08-15T14:22:00Z",
          "kind": "screenshot",       // capture_kind enum
          "http_status": 200,
          "file_path": "captures/site/file.png",  // local path or Storage object path
          "content_hash": "<sha256-hex>",          // Required for dedup
          "text_excerpt": "Short excerpt...",
          "notes": null,

          "evidence": [               // Evidence tied to THIS specific capture
            {
              "rule": "R1",           // rule_code enum
              "evidence_type": "r1_institution_history", // evidence_kind enum
              "evidence_date": null,  // date or null
              "access_date": "2025-08-15",
              "description": "Why this qualifies..."
            }
          ]
        }
      ],

      "evidence": [                   // Document-level evidence (no capture yet)
        {
          "rule": "R3",
          "evidence_type": "r3_official_page",
          "evidence_date": null,
          "access_date": "2025-08-15",
          "description": "..."
        }
      ]
    }
  ],

  "tv_episodes": [
    {
      "show_name": "Ghost Adventures",
      "season_number": 3,             // Use 0 for specials
      "episode_number": 1,            // Use 0 for specials
      "episode_title": "...",
      "air_date": "2009-11-06",
      "synopsis": "...",
      "channel": "Travel Channel",
      "viewers": null,                // bigint or null
      "imdb_rating": 7.8,            // numeric or null
      "imdb_quantity": null           // number of IMDb votes or null
    }
  ],

  "youtube_videos": [
    {
      "url": "https://www.youtube.com/watch?v=...", // Dedup key
      "video_title": "...",
      "channel_name": "...",
      "upload_date": "2023-10-28",
      "view_count": 2180000,
      "like_count": 54200,
      "comment_count": 3710,
      "description_text": "...",
      "duration": "PT42M17S",         // ISO 8601
      "category": "Entertainment",
      "channel_subscribers": 3400000
    }
  ],

  "review_profiles": [
    {
      "platform_id": "<uuid>",        // Must exist in review_platforms table
      "profile_url": "https://...",

      "documents": [                  // Optional review documents/captures/evidence
        {
          "source": "review",         // doc_source enum
          "url": "https://...",
          "title": "...",
          "publisher": "TripAdvisor",
          "published_date": null,
          // official_category is always null for review documents
          "captures": [ /* same structure as above */ ]
        }
      ]
    }
  ]
}
```

---

## Workflow for Adding a New Site

### Step 1 — Research
Gather: official site URL, address, official page URLs, TV appearances, YouTube videos, review platform profiles.

### Step 2 — Create the payload file
Copy `payloads/pennhurst_asylum.json` as a template. Save as `payloads/<site_slug>.json`.

Fill in:
- `site` block
- `aliases` array
- `documents` array — one entry per official page, with document-level `evidence` (no captures needed yet)
- `tv_episodes` array
- `youtube_videos` array
- `review_profiles` array — use platform UUIDs from the `review_platforms` table above

Leave `captures: []` on documents until you have taken the actual screenshots/PDFs.

### Step 3 — Ingest
```bash
curl -X POST https://yyhdksrmxxerijfvuraa.supabase.co/functions/v1/ingest-site \
  -H "Authorization: Bearer <service_role_key>" \
  -H "Content-Type: application/json" \
  -d @payloads/<site_slug>.json
```

Expect: `{"ok": true, "site_id": "<uuid>"}`.

### Step 4 — Add captures
When you have taken screenshots or PDFs, use `add_captures.py` (see section below).
The script handles SHA-256 hashing and DB upserts automatically.

### Step 5 — Commit
```bash
git add payloads/<site_slug>.json
git commit -m "ingest <site name>"
git push origin master
```

---

## File Layout

```
haunted-asylum-db/
├── .env                                      # Credentials — NEVER commit
├── .gitignore                                # Excludes .env
├── CONTEXT.md                                # This file
├── sql/
│   ├── 01_unique_constraints.sql             # Run once to enable upserts
│   └── 02_rpc_ingest_site.sql               # ingest_site() function definition
├── payloads/
│   ├── example_ingest_site.json              # Full annotated example (Pennhurst test)
│   └── pennhurst_asylum.json                 # Real Pennhurst ingestion payload
├── scripts/
│   └── add_captures.py                       # Syncs local PDF captures to the database
└── supabase/
    └── functions/
        └── ingest-site/
            └── index.ts                      # Edge Function (Deno/TypeScript)
```

---

## Adding Captures (add_captures.py)

Captures live at: `C:\Users\K\Documents\PhD\Captures\[sitename]\[date]\[filename].pdf`

**Run from Windows terminal (cmd or PowerShell):**
```
C:\Users\K\AppData\Local\Programs\Python\Python312\python.exe C:\Users\K\haunted-asylum-db\scripts\add_captures.py --site trans-allegheny --date 2026-02-16
```

**What it does:**
1. Finds all PDFs in the date folder
2. Looks up the site's documents from the database
3. For unrecognised filenames, shows a numbered list of documents and asks you to assign one
4. Saves the filename → document URL assignment to `mapping.json` in the site folder (never asks again for the same filename)
5. Computes SHA-256 hash of each PDF
6. Upserts the capture row — safe to re-run

**Dry run (no DB writes):**
```
... add_captures.py --site trans-allegheny --date 2026-02-16 --dry-run
```

**mapping.json** is stored at `Documents/PhD/Captures/[sitename]/mapping.json`.
Format: `{ "filename_stem": "https://document-url" }`
Do not commit mapping.json files — they live alongside the captures on disk.

**Python location:** `C:\Users\K\AppData\Local\Programs\Python\Python312\python.exe`
**Dependencies:** `psycopg2-binary`, `python-dotenv` (already installed)

### Sites ingested and captures synced

| Site | site_id | Captures synced |
|---|---|---|
| Trans-Allegheny Lunatic Asylum | *(query DB)* | 14 PDFs across 2026-02-16 and 2026-02-18 |
| Pennhurst Asylum | `8166f2d3-2360-4e18-8ea4-dd5c8bf803b7` | None yet |

### Trans-Allegheny mapping.json (for reference)
```json
{
  "talaghosttours":    "https://trans-alleghenylunaticasylum.com/ghost-tours/",
  "talahauntedhouse":  "https://trans-alleghenylunaticasylum.com/haunted-house/",
  "talaheritagetours": "https://trans-alleghenylunaticasylum.com/historic-tours/",
  "talahomepage":      "https://trans-alleghenylunaticasylum.com/",
  "talaschedule":      "https://trans-alleghenylunaticasylum.com/schedule-of-events/",
  "talafaq":           "https://trans-alleghenylunaticasylum.com/faq/",
  "talahistory1":      "https://trans-alleghenylunaticasylum.com/explore-our-history/",
  "talahistory2":      "https://trans-alleghenylunaticasylum.com/the-pre-asylum-era/",
  "talahistory3":      "https://trans-alleghenylunaticasylum.com/dorothea-dix-2/",
  "talahistory4":      "https://trans-alleghenylunaticasylum.com/the-kirkbride-plan/",
  "talahistory5":      "https://trans-alleghenylunaticasylum.com/the-civil-war/",
  "www_facebook_com_TALAWV_reviews": "https://www.facebook.com/TALAWV/reviews/",
  "www_tripadvisor_com_Attraction_Review-g59638-d1049077": "https://www.tripadvisor.com/Attraction_Review-g59638-d1049077-Reviews-Trans_Allegheny_Lunatic_Asylum-Weston_West_Virginia.html",
  "www_yelp_com_biz_trans_allegheny_lunatic_asylum_weston": "https://www.yelp.com/biz/trans-allegheny-lunatic-asylum-weston"
}
```

---

## Deploy / Maintenance Commands

**Redeploy Edge Function after changes:**
```bash
C:\Users\K\bin\supabase.exe functions deploy ingest-site --no-verify-jwt
```

**Refresh PostgREST schema cache (run in SQL Editor after RPC changes):**
```sql
NOTIFY pgrst, 'reload schema';
```

**Push to GitHub:**
```bash
git push origin master
```

**Test the Edge Function:**
```bash
curl -X POST https://yyhdksrmxxerijfvuraa.supabase.co/functions/v1/ingest-site \
  -H "Authorization: Bearer <service_role_key>" \
  -H "Content-Type: application/json" \
  -d @payloads/pennhurst_asylum.json
```

---

## Known Issues / Decisions Made

- **`alias` not `alias_name`**: The `site_aliases` table column is `alias`. The SQL files reflect this.
- **`CREATE UNIQUE INDEX` not `ALTER TABLE ADD CONSTRAINT`**: The Supabase SQL Editor had a parser issue with multi-line `ALTER TABLE ... ADD CONSTRAINT` statements. All constraints were created with `CREATE UNIQUE INDEX` instead, which is functionally equivalent.
- **Evidence dedup with nullable FKs**: Standard `UNIQUE` constraints treat NULLs as distinct. The expression index using `COALESCE(col, nil_uuid)` solves this.
- **Edge Function uses direct Postgres, not PostgREST**: The Supabase JS client's `.rpc()` method triggered a persistent `PGRST002` schema cache error. The Edge Function now connects directly via `postgresjs` using `SUPABASE_DB_URL`.
- **TV episode specials**: Use `season_number: 0, episode_number: 0` for one-off specials with no season structure.
- **Captures are optional at ingest time**: Documents and evidence can be ingested without captures. Add captures in a follow-up payload run when files are ready.
- **Supabase Storage**: Currently `file_path` holds local disk paths. When migrating to Supabase Storage, update the values to Storage object paths — no schema change required.
