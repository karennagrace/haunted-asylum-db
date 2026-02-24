#!/usr/bin/env python3
"""
add_captures.py — sync PDFs from the local captures folder to the database.

Usage:
    python scripts/add_captures.py --site trans-allegheny --date 2026-02-16

For each PDF in Documents/PhD/Captures/<site>/<date>/, the script:
  1. Computes the SHA-256 hash
  2. Looks up the matching document via mapping.json in the site folder
     (if the file isn't mapped yet, shows available documents and asks you to assign it)
  3. Upserts the capture row — safe to re-run, skips files already in the DB

Mapping file:
  Documents/PhD/Captures/<site>/mapping.json
  Format: { "filename_stem": "https://document-url" }
  Built interactively on first run, reused on subsequent runs.
"""

import argparse
import hashlib
import json
import os
import sys
import uuid
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

CAPTURES_BASE = Path.home() / "Documents" / "PhD" / "Captures"
ENV_PATH      = Path(__file__).parent.parent / ".env"
RESEARCHER_ID = "36339282-36e1-41b8-ad8b-bba0fff72e64"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest().upper()


def load_mapping(site_dir: Path) -> dict:
    mapping_file = site_dir / "mapping.json"
    if mapping_file.exists():
        with open(mapping_file) as f:
            return json.load(f)
    return {}


def save_mapping(site_dir: Path, mapping: dict):
    mapping_file = site_dir / "mapping.json"
    with open(mapping_file, "w") as f:
        json.dump(mapping, f, indent=2, sort_keys=True)
    print(f"  Mapping saved → {mapping_file}")


def get_site_documents(conn, site_folder: str) -> list[dict]:
    """Return all documents for the site whose folder name matches."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT d.document_id, d.url, d.title, d.official_category
            FROM documents d
            JOIN sites s ON s.site_id = d.site_id
            WHERE s.site_name ILIKE %s
               OR s.official_site_url ILIKE %s
            ORDER BY d.official_category NULLS LAST, d.url
        """, (
            f"%{site_folder.replace('-', ' ')}%",
            f"%{site_folder}%",
        ))
        rows = cur.fetchall()
    return [
        {"document_id": str(r[0]), "url": r[1], "title": r[2], "category": r[3]}
        for r in rows
    ]


def resolve_document(stem: str, docs: list[dict], mapping: dict, site_dir: Path) -> str | None:
    """
    Return the document_id for a filename stem.
    If the stem is already in mapping.json, look it up directly.
    Otherwise, prompt the user to assign it.
    """
    if stem in mapping:
        url = mapping[stem]
        match = next((d for d in docs if d["url"] == url), None)
        if match:
            return match["document_id"]
        print(f"  WARNING: '{url}' from mapping.json not found in DB — re-assigning.")

    # Interactive assignment
    print(f"\n  Unrecognised file: {stem}.pdf")
    print("  Available documents for this site:")
    for i, doc in enumerate(docs):
        label = doc["title"] or doc["url"]
        cat   = f"  [{doc['category']}]" if doc["category"] else ""
        print(f"    [{i}] {label}{cat}")
    print("    [s] Skip this file")

    choice = input("  Assign to document number (or s to skip): ").strip().lower()
    if choice == "s":
        return None

    try:
        idx = int(choice)
        doc = docs[idx]
        mapping[stem] = doc["url"]
        save_mapping(site_dir, mapping)
        print(f"  Mapped '{stem}' → {doc['url']}")
        return doc["document_id"]
    except (ValueError, IndexError):
        print("  Invalid choice — skipping.")
        return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Sync capture PDFs from the local folder to the database."
    )
    parser.add_argument("--site", required=True,
                        help="Site folder name, e.g. trans-allegheny")
    parser.add_argument("--date", required=True,
                        help="Date folder, e.g. 2026-02-16")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print what would happen without writing to the DB")
    args = parser.parse_args()

    # ── Environment ──────────────────────────────────────────────────────────
    load_dotenv(ENV_PATH)
    db_url = os.getenv("DATABASE_URL", "").replace("postgresql://", "postgres://", 1)
    if not db_url:
        print("ERROR: DATABASE_URL not set in .env")
        sys.exit(1)

    # ── Locate files ─────────────────────────────────────────────────────────
    site_dir = CAPTURES_BASE / args.site
    date_dir = site_dir / args.date

    if not date_dir.exists():
        print(f"ERROR: Folder not found: {date_dir}")
        sys.exit(1)

    pdfs = sorted(date_dir.glob("*.pdf"))
    if not pdfs:
        print(f"No PDFs found in {date_dir}")
        sys.exit(0)

    print(f"Found {len(pdfs)} PDF(s) in {date_dir}")
    if args.dry_run:
        print("DRY RUN — no changes will be written.\n")

    # ── Connect ───────────────────────────────────────────────────────────────
    conn = psycopg2.connect(db_url)
    conn.autocommit = False

    try:
        docs    = get_site_documents(conn, args.site)
        mapping = load_mapping(site_dir)

        if not docs:
            print(f"ERROR: No documents found in the DB for site '{args.site}'.")
            print("       Ingest the site first using the Edge Function.")
            sys.exit(1)

        capture_ts = f"{args.date}T12:00:00+00:00"
        inserted   = 0
        updated    = 0
        skipped    = 0

        for pdf in pdfs:
            stem = pdf.stem
            print(f"\n{'[DRY RUN] ' if args.dry_run else ''}Processing: {pdf.name}")

            doc_id = resolve_document(stem, docs, mapping, site_dir)
            if not doc_id:
                print("  Skipped.")
                skipped += 1
                continue

            hash_val = sha256(pdf)
            # Store path relative to home directory for portability
            rel_path = str(pdf.relative_to(Path.home())).replace("\\", "/")

            print(f"  document_id : {doc_id}")
            print(f"  SHA-256     : {hash_val}")
            print(f"  file_path   : {rel_path}")

            if args.dry_run:
                inserted += 1
                continue

            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO captures (
                        capture_id, document_id, captured_by, capture_ts,
                        kind, http_status, file_path, content_hash, notes
                    )
                    VALUES (
                        %s, %s, %s, %s,
                        'pdf', 200, %s, %s, NULL
                    )
                    ON CONFLICT (document_id, content_hash) DO UPDATE
                        SET file_path  = EXCLUDED.file_path,
                            capture_ts = EXCLUDED.capture_ts
                    RETURNING capture_id,
                              (xmax = 0) AS was_inserted
                """, (
                    str(uuid.uuid4()), doc_id, RESEARCHER_ID,
                    capture_ts, rel_path, hash_val
                ))
                row = cur.fetchone()
                capture_id   = row[0]
                was_inserted = row[1]

            conn.commit()

            if was_inserted:
                print(f"  INSERTED — capture_id: {capture_id}")
                inserted += 1
            else:
                print(f"  UPDATED  — capture_id: {capture_id}")
                updated += 1

    except Exception as e:
        conn.rollback()
        print(f"\nERROR: {e}")
        sys.exit(1)
    finally:
        conn.close()

    print("\n" + "-"*40)
    if args.dry_run:
        print(f"Dry run complete. {inserted} would be inserted, {skipped} skipped.")
    else:
        print(f"Done. {inserted} inserted, {updated} updated, {skipped} skipped.")


if __name__ == "__main__":
    main()
