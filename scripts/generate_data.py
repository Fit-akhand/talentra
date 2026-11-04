#!/usr/bin/env python3
"""
Talentra synthetic data generator (lifecycle steps 14, 23, 24; docket B60-B64).

Generates constraint-compliant, realistic data across the schemas, then runs the analytics
load (analytics.refresh_reporting_marts) so the star schema is populated from the operational
tables rather than invented separately.

Behaviour you can rely on
  * Reproducible: the same --seed gives the same shape (counts, mixes, relationships).
    Timestamps are anchored to the run time, so absolute dates move with the clock.
  * Not silently repeatable: if the database already holds candidates the run stops, because a
    second run used to double every table. Re-create the database, or pass --append.
  * Realistic, not uniform: job and application status mixes, a staged hiring pipeline whose
    history is consistent with the current status, gig requests in every state, and so on.
  * The reference UI translations are owned by migration 018 and are not seeded here.

Scales
  dev      500 candidates, 100 jobs, 2,000 applications
  medium   10,000 candidates, 1,000 jobs, 50,000 applications
  laptop   1,000,000 candidates, 100,000 jobs, 5,000,000 applications (docket section 6)

Connection: PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD (or the POSTGRES_* equivalents).
"""

import argparse
import hashlib
import io
import itertools
import json
import os
import random
import sys
import time
from datetime import datetime, timedelta, timezone

import psycopg2
from psycopg2.extras import execute_values

import identifier_crypto

DB_HOST = os.getenv("POSTGRES_HOST") or os.getenv("PGHOST", "127.0.0.1")
DB_PORT = int(os.getenv("POSTGRES_PORT") or os.getenv("PGPORT", "5432"))
DB_NAME = os.getenv("POSTGRES_DB") or os.getenv("PGDATABASE", "talentra")
DB_USER = os.getenv("POSTGRES_USER") or os.getenv("PGUSER", "talentra_admin")
DB_PASS = os.getenv("POSTGRES_PASSWORD") or os.getenv("PGPASSWORD")

FIRST_NAMES = [
    "Aarav", "Aditi", "Alexander", "Elena", "Wei", "Mei", "Liam", "Olivia",
    "Fatima", "Tariq", "Carlos", "Sofia", "Yuki", "Kenji", "Priya", "Rohan",
    "Niamh", "Lucas", "Astrid", "Dmitry", "Olga", "Kwame", "Amara", "Zubair",
    "Mateo", "Chiara", "Sven", "Freja", "Sunil", "Ananya", "Hassan", "Leila"
]
LAST_NAMES = [
    "Sharma", "Patel", "Smith", "Johnson", "Wang", "Zhang", "Ivanov", "Petrova",
    "Al-Mansoor", "Garcia", "Rodriguez", "Tanaka", "Sato", "Murphy", "O'Connor",
    "Dubois", "Muller", "Okafor", "Adeyemi", "Khan", "Tiwari", "Verma", "Novak",
    "Rossi", "Lindqvist", "Kowalski", "Santos", "Kim", "Chen", "Gupta", "Bauer"
]

TITLES = [
    "Software Engineer", "Senior Backend Engineer", "Lead Data Architect",
    "DevOps Specialist", "Full Stack Developer", "Machine Learning Engineer",
    "Database Administrator", "Site Reliability Engineer", "Platform Architect",
    "Frontend Developer", "Cloud Solutions Architect", "Security Analyst",
    "Distributed Systems Engineer", "Data Platform Engineer", "Systems Architect"
]


def seed_master_reference_geo(conn):
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM master.country;")
    c_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM master.city;")
    city_count = cur.fetchone()[0]

    if c_count == 0 or city_count == 0:
        print("[*] Populating master countries, states, and cities...")
        countries = [
            ('US', 'USA', 'United States', '+1'),
            ('IN', 'IND', 'India', '+91'),
            ('GB', 'GBR', 'United Kingdom', '+44'),
            ('DE', 'DEU', 'Germany', '+49'),
            ('SG', 'SGP', 'Singapore', '+65'),
            ('CA', 'CAN', 'Canada', '+1'),
            ('AU', 'AUS', 'Australia', '+61'),
            ('JP', 'JPN', 'Japan', '+81')
        ]
        execute_values(
            cur,
            "INSERT INTO master.country (iso_alpha2, iso_alpha3, name, phone_calling_code) VALUES %s ON CONFLICT DO NOTHING;",
            countries
        )
        conn.commit()

        # States
        cur.execute("SELECT id, iso_alpha2 FROM master.country;")
        c_map = {r[1]: r[0] for r in cur.fetchall()}

        states = [
            (c_map.get('US', 1), 'California', 'CA'),
            (c_map.get('US', 1), 'New York', 'NY'),
            (c_map.get('US', 1), 'Texas', 'TX'),
            (c_map.get('US', 1), 'Washington', 'WA'),
            (c_map.get('IN', 2), 'Karnataka', 'KA'),
            (c_map.get('IN', 2), 'Maharashtra', 'MH'),
            (c_map.get('IN', 2), 'Delhi', 'DL'),
            (c_map.get('GB', 3), 'England', 'ENG'),
            (c_map.get('DE', 4), 'Bavaria', 'BY'),
            (c_map.get('SG', 5), 'Singapore', 'SG')
        ]
        execute_values(
            cur,
            "INSERT INTO master.state (country_id, name, subdivision_code) VALUES %s ON CONFLICT DO NOTHING;",
            states
        )
        conn.commit()

        # Cities
        cur.execute("SELECT id, name FROM master.state;")
        s_map = {r[1]: r[0] for r in cur.fetchall()}

        cities = [
            (s_map.get('California', 1), 'San Francisco'),
            (s_map.get('California', 1), 'Los Angeles'),
            (s_map.get('New York', 2), 'New York'),
            (s_map.get('Washington', 4), 'Seattle'),
            (s_map.get('Texas', 3), 'Austin'),
            (s_map.get('Karnataka', 5), 'Bengaluru'),
            (s_map.get('Maharashtra', 6), 'Mumbai'),
            (s_map.get('Delhi', 7), 'New Delhi'),
            (s_map.get('England', 8), 'London'),
            (s_map.get('Bavaria', 9), 'Munich'),
            (s_map.get('Singapore', 10), 'Singapore')
        ]
        execute_values(
            cur,
            "INSERT INTO master.city (state_id, name) VALUES %s ON CONFLICT DO NOTHING;",
            cities
        )
        conn.commit()
    cur.close()



ORG_PREFIX = ["Northwind", "Bluepeak", "Ironbridge", "Greenfield", "Kestrel", "Lumen", "Harbor", "Summit",
              "Vertex", "Aurora", "Cobalt", "Meridian", "Pioneer", "Redwood", "Silverline", "Tidewater"]
ORG_SUFFIX = ["Systems", "Technologies", "Labs", "Analytics", "Software", "Logistics", "Health", "Finance",
              "Retail", "Networks", "Consulting", "Industries"]
SUPPORT_CATEGORIES = ["account", "billing", "technical", "privacy", "other"]
SUPPORT_SUBJECTS = ["Cannot log in on a new device", "Invoice amount looks wrong", "Resume upload fails",
                    "Request to delete my data", "Job alert emails not arriving", "Wallet recharge pending"]

# Synthetic argon2id-shaped string. It is not derived from any real password and cannot verify one.
PASSWORD_HASH = "$argon2id$v=19$m=65536,t=3,p=4$c3ludGhldGljLXNhbHQ$c3ludGhldGljLWhhc2gtZG8tbm90LXVzZQ"

SCALE_CONFIGS = {
    "dev":    {"candidates": 500,     "organizations": 20,    "jobs": 100,    "applications": 2000,
               "gig_workers": 100,    "gig_requests": 50,     "batch_size": 500},
    "medium": {"candidates": 10000,   "organizations": 200,   "jobs": 1000,   "applications": 50000,
               "gig_workers": 2000,   "gig_requests": 500,    "batch_size": 2000},
    "laptop": {"candidates": 1000000, "organizations": 10000, "jobs": 100000, "applications": 5000000,
               "gig_workers": 100000, "gig_requests": 50000,  "batch_size": 10000},
}


class Ctx:
    """Run-wide state: the seeded random generator and the instant everything is anchored to."""

    def __init__(self, seed, config):
        self.seed = seed
        self.rng = random.Random(seed)
        self.as_of = datetime.now(timezone.utc).replace(microsecond=0)
        self.cfg = config

    def days_ago(self, lo, hi):
        return self.as_of - timedelta(days=self.rng.uniform(lo, hi))

    def pick(self, items, weights):
        return self.rng.choices(items, weights=weights, k=1)[0]

    def cumulative(self, weights):
        """Running totals of `weights`. random.choices(weights=...) rebuilds these on every call, which is
        O(n) per pick; with 100,000 jobs and 5 million applications that dominated the whole run."""
        return list(itertools.accumulate(weights))

    def pick_cum(self, items, cum_weights):
        return self.rng.choices(items, cum_weights=cum_weights, k=1)[0]


def get_connection():
    return psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASS)


def one_column(cur, sql, args=None):
    cur.execute(sql, args)
    return [r[0] for r in cur.fetchall()]


def bulk(cur, sql, rows, page_size=1000, returning=False):
    return execute_values(cur, sql, rows, page_size=page_size, fetch=returning)


def _next_index(cur):
    cur.execute("SELECT COALESCE(MAX(id), 0) FROM core.user_account;")
    return cur.fetchone()[0]


def _add_roles_and_credentials(cur, users, role_name, role_ids):
    """users: list of (user_id, email). Assign one role and a password credential to each."""
    bulk(cur, "INSERT INTO core.user_role (user_account_id, role_id) VALUES %s ON CONFLICT DO NOTHING",
         [(uid, role_ids[role_name]) for uid, _ in users])
    bulk(cur, "INSERT INTO core.user_credential (user_account_id, credential_type, credential_identifier, secret_hash) VALUES %s "
              "ON CONFLICT DO NOTHING",
         [(uid, "password", email, PASSWORD_HASH) for uid, email in users])


def seed_employers(conn, ctx):
    n = ctx.cfg["organizations"]
    print(f"[*] Seeding {n:,} organisations, each with an owner and a recruiter...")
    cur = conn.cursor()
    t0 = time.time()
    role_ids = dict((r[0], r[1]) for r in _rows(cur, "SELECT name, id FROM core.role"))
    country_ids = one_column(cur, "SELECT id FROM master.country WHERE iso_alpha2 IN ('US','IN','GB','DE','SG') ORDER BY id")
    city_ids = one_column(cur, "SELECT id FROM master.city ORDER BY id")
    offset = _next_index(cur)

    owners, recruiters = [], []
    for i in range(n):
        idx = offset + i + 1
        owners.append((f"employer_{idx}@example.com", f"+9197{ctx.rng.randint(10000000, 99999999)}"))
        recruiters.append((f"recruiter_{idx}@example.com", f"+9196{ctx.rng.randint(10000000, 99999999)}"))
    mk = lambda rows: [(e, p, "IN", "active", "en") for e, p in rows]
    owner_rows = bulk(cur, "INSERT INTO core.user_account (email, phone_e164, phone_country_code, account_status, preferred_language) "
                           "VALUES %s RETURNING id, email", mk(owners), returning=True)
    recruiter_rows = bulk(cur, "INSERT INTO core.user_account (email, phone_e164, phone_country_code, account_status, preferred_language) "
                               "VALUES %s RETURNING id, email", mk(recruiters), returning=True)
    _add_roles_and_credentials(cur, owner_rows, "employer", role_ids)
    _add_roles_and_credentials(cur, recruiter_rows, "recruiter", role_ids)

    org_rows = []
    for i, (oid, _) in enumerate(owner_rows):
        name = f"{ctx.rng.choice(ORG_PREFIX)} {ctx.rng.choice(ORG_SUFFIX)} {i + 1}"
        slug = f"{name.lower().replace(' ', '-')}-{offset + i + 1}"
        org_rows.append((name, slug, "employer", "active", oid, ctx.rng.choice(country_ids)))
    org_ids = [r[0] for r in bulk(cur, "INSERT INTO recruitment.organization "
                                       "(name, slug, organization_type, organization_status, created_by_user_account_id, country_id) "
                                       "VALUES %s RETURNING id", org_rows, returning=True)]

    invited = ctx.as_of - timedelta(days=400)
    joined = invited + timedelta(days=1)
    members, locations, orgs = [], [], []
    for org_id, (owner_id, _), (rec_id, _) in zip(org_ids, owner_rows, recruiter_rows):
        members.append((org_id, owner_id, "owner", "active", invited, joined))
        members.append((org_id, rec_id, "recruiter", "active", invited, joined))
        locations.append((org_id, ctx.rng.choice(city_ids), "Corporate HQ", "1 Innovation Way", "560001", True))
        orgs.append({"id": org_id, "owner": owner_id, "recruiter": rec_id})
    bulk(cur, "INSERT INTO recruitment.organization_member (organization_id, user_account_id, organization_role, membership_status, invited_at, joined_at) VALUES %s", members)
    bulk(cur, "INSERT INTO recruitment.organization_location (organization_id, city_id, location_name, address_line1, postal_code, is_headquarters) VALUES %s", locations)
    conn.commit()
    print(f"[+] Organisations seeded in {time.time() - t0:.2f}s")
    return orgs


def _rows(cur, sql, args=None):
    cur.execute(sql, args)
    return cur.fetchall()


def seed_candidates(conn, ctx):
    num, batch = ctx.cfg["candidates"], ctx.cfg["batch_size"]
    print(f"[*] Seeding {num:,} candidates (account, profile, location, skills, credential)...")
    cur = conn.cursor()
    t0 = time.time()
    role_ids = dict((r[0], r[1]) for r in _rows(cur, "SELECT name, id FROM core.role"))
    city_ids = one_column(cur, "SELECT id FROM master.city ORDER BY id")
    skill_rows = _rows(cur, "SELECT id, normalized_name FROM master.skill ORDER BY id")
    skill_ids = [r[0] for r in skill_rows]
    key_skills = [r[0] for r in skill_rows if r[1] in ("postgresql", "python", "docker", "react", "java")] or skill_ids[:3]
    offset = _next_index(cur)
    created = 0
    while created < num:
        size = min(batch, num - created)
        users = [(f"candidate_{offset + created + i + 1}@example.com", f"+9198{ctx.rng.randint(10000000, 99999999)}",
                  "IN", "active", "en") for i in range(size)]
        user_rows = bulk(cur, "INSERT INTO core.user_account (email, phone_e164, phone_country_code, account_status, preferred_language) "
                              "VALUES %s RETURNING id, email", users, returning=True)
        _add_roles_and_credentials(cur, user_rows, "candidate", role_ids)

        profiles = []
        for uid, _ in user_rows:
            fn, ln = ctx.rng.choice(FIRST_NAMES), ctx.rng.choice(LAST_NAMES)
            exp = round(min(ctx.rng.lognormvariate(1.6, 0.7), 40.0), 1)          # right-skewed: many juniors, few veterans
            headline = f"{ctx.rng.choice(TITLES)} with {int(exp)} yrs experience"
            visibility = ctx.pick(["recruiters", "public", "private"], [0.55, 0.30, 0.15])
            status = ctx.pick(["active", "draft", "paused"], [0.85, 0.10, 0.05])
            lang = ctx.pick(["en", "hi", "es", None], [0.80, 0.10, 0.05, 0.05])       # None: language not known
            profiles.append((uid, headline, f"Experienced professional {fn} {ln}", exp, status, visibility, lang))
        prof_ids = [r[0] for r in bulk(cur, "INSERT INTO profile.candidate_profile (user_account_id, headline, professional_summary, "
                                            "total_experience_years, profile_status, visibility, summary_language_code) VALUES %s RETURNING id",
                                       profiles, returning=True)]

        bulk(cur, "INSERT INTO profile.candidate_location (candidate_profile_id, city_id, location_type) VALUES %s",
             [(pid, ctx.rng.choice(city_ids), "current") for pid in prof_ids])
        skills = []
        for pid in prof_ids:
            chosen = set(ctx.rng.sample(skill_ids, min(3, len(skill_ids))))
            if ctx.rng.random() < 0.7:
                chosen.add(ctx.rng.choice(key_skills))
            for k, sid in enumerate(sorted(chosen)):
                skills.append((pid, sid, ctx.pick(["beginner", "intermediate", "advanced", "expert"], [0.15, 0.40, 0.30, 0.15]),
                               round(ctx.rng.uniform(0.5, 10.0), 1), k == 0))
        bulk(cur, "INSERT INTO profile.candidate_skill (candidate_profile_id, skill_id, proficiency_level, experience_years, is_primary) VALUES %s", skills)

        created += size
        if created % 25000 == 0 or created == num:
            rate = created / max(time.time() - t0, 1e-9)
            print(f"    -> {created:,}/{num:,} candidates ({rate:,.0f}/s)")
        conn.commit()
    print(f"[+] Candidates seeded in {time.time() - t0:.2f}s")


JOB_STATUS = ["draft", "published", "paused", "closed", "filled", "cancelled"]
JOB_STATUS_WEIGHTS = [0.08, 0.62, 0.05, 0.15, 0.08, 0.02]


def seed_jobs(conn, ctx, orgs):
    num, batch = ctx.cfg["jobs"], ctx.cfg["batch_size"]
    print(f"[*] Seeding {num:,} job postings across {len(orgs):,} organisations...")
    cur = conn.cursor()
    t0 = time.time()
    emp_ids = one_column(cur, "SELECT id FROM master.employment_type ORDER BY id")
    work_ids = one_column(cur, "SELECT id FROM master.work_type ORDER BY id")
    city_ids = one_column(cur, "SELECT id FROM master.city ORDER BY id")
    industry_ids = one_column(cur, "SELECT id FROM master.industry ORDER BY id")
    role_ids = one_column(cur, "SELECT id FROM master.job_role ORDER BY id")
    skill_ids = one_column(cur, "SELECT id FROM master.skill ORDER BY id")
    # a few big employers post most jobs: weight organisations by a power law
    org_cum = ctx.cumulative([1.0 / (rank + 1) ** 0.7 for rank in range(len(orgs))])

    live_jobs = []                                   # (job_id, published_at) for jobs that were ever public
    created = 0
    while created < num:
        size = min(batch, num - created)
        rows, meta = [], []
        for _ in range(size):
            org = ctx.pick_cum(orgs, org_cum)
            status = ctx.pick(JOB_STATUS, JOB_STATUS_WEIGHTS)
            title = ctx.rng.choice(TITLES)
            published = None if status in ("draft", "cancelled") and ctx.rng.random() < 0.6 else ctx.days_ago(5, 330)
            if status == "published" and published is None:
                published = ctx.days_ago(5, 330)
            closed = None
            if status in ("closed", "filled", "cancelled"):
                closed = min((published or ctx.days_ago(5, 60)) + timedelta(days=ctx.rng.uniform(7, 90)), ctx.as_of)
            s_min = ctx.rng.choice([60000, 80000, 100000, 120000, 150000])
            s_max = s_min + ctx.rng.choice([20000, 40000, 60000])
            rows.append((org["id"], org["recruiter"], ctx.rng.choice(emp_ids), ctx.rng.choice(work_ids), ctx.rng.choice(city_ids),
                         ctx.rng.choice(industry_ids), ctx.rng.choice(role_ids) if role_ids else None, title,
                         f"We are hiring a {title} to build and run high-scale systems.", status, "USD", s_min, s_max, "year",
                         ctx.pick([1, 2, 3, 5], [0.7, 0.2, 0.07, 0.03]), published, closed, ctx.pick(["en", "hi", None], [0.90, 0.05, 0.05])))
            meta.append((status, published))
        ids = [r[0] for r in bulk(cur, "INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, "
                                       "work_type_id, city_id, industry_id, job_role_id, title, description, job_status, currency_code, salary_min, "
                                       "salary_max, salary_period, vacancy_count, published_at, closed_at, description_language_code) VALUES %s RETURNING id",
                                  rows, returning=True)]
        reqs = []
        for jid, (status, published) in zip(ids, meta):
            if published is not None:
                live_jobs.append((jid, published))
            for sid in ctx.rng.sample(skill_ids, min(3, len(skill_ids))):
                reqs.append((jid, sid, True, ctx.pick(["beginner", "intermediate", "advanced"], [0.2, 0.5, 0.3]), round(ctx.rng.uniform(1.0, 6.0), 1)))
        bulk(cur, "INSERT INTO recruitment.job_skill_requirement (job_posting_id, skill_id, is_required, minimum_proficiency_level, minimum_experience_years) VALUES %s", reqs)
        created += size
        conn.commit()
    print(f"[+] Jobs seeded in {time.time() - t0:.2f}s ({len(live_jobs):,} were ever public)")
    return live_jobs


PROGRESSION_SQL = """
CREATE TEMP TABLE tmp_prog ON COMMIT DROP AS
WITH h AS (
    SELECT a.id, a.applied_at,
           mod(abs(hashint8(a.id # %(seed)s)::numeric), 10000) / 10000.0           AS u,
           mod(abs(hashint8(a.id # (%(seed)s * 7 + 1))::numeric), 10000) / 10000.0  AS v,
           mod(abs(hashint8(a.id # (%(seed)s * 13 + 2))::numeric), 10000) / 10000.0 AS w
      FROM recruitment.candidate_application a
     WHERE a.id > %(min_id)s)
SELECT id, applied_at, w,
       CASE WHEN u < 0.50 THEN 0 WHEN u < 0.70 THEN 1 WHEN u < 0.82 THEN 2 WHEN u < 0.88 THEN 3
            WHEN u < 0.92 THEN 4 ELSE 5 END AS cat,
       CASE WHEN u >= 0.92 AND (u - 0.92) / 0.08 < 0.75 THEN 'rejected' ELSE 'withdrawn' END AS final_name,
       floor(v * 4)::int AS from_stage
  FROM h;

CREATE TEMP TABLE tmp_steps ON COMMIT DROP AS
SELECT p.id, s.i,
       CASE WHEN p.cat = 5 AND s.i = p.from_stage + 1 THEN p.final_name
            ELSE (ARRAY['applied','shortlisted','interviewed','offered','joined'])[s.i + 1] END AS new_status,
       (ARRAY['applied','shortlisted','interviewed','offered','joined'])[s.i] AS prev_status,
       p.applied_at + ((ARRAY[2, 9, 19, 33])[s.i] * (0.5 + p.w)) * INTERVAL '1 day' AS changed_at
  FROM tmp_prog p
  CROSS JOIN LATERAL generate_series(1, CASE WHEN p.cat = 5 THEN p.from_stage + 1 ELSE p.cat END) AS s(i);

DELETE FROM tmp_steps WHERE changed_at > %(as_of)s;

INSERT INTO recruitment.application_status_history (candidate_application_id, previous_status, new_status, changed_at)
SELECT id, prev_status, new_status, changed_at FROM tmp_steps;

UPDATE recruitment.candidate_application a
   SET application_status = l.new_status, last_status_changed_at = l.changed_at, updated_at = l.changed_at
  FROM (SELECT DISTINCT ON (id) id, new_status, changed_at FROM tmp_steps ORDER BY id, i DESC) l
 WHERE a.id = l.id;
"""


def seed_applications(conn, ctx, live_jobs):
    num, batch = ctx.cfg["applications"], ctx.cfg["batch_size"]
    print(f"[*] Seeding {num:,} applications and moving them through the hiring pipeline...")
    cur = conn.cursor()
    t0 = time.time()
    candidates = _rows(cur, "SELECT p.id, p.user_account_id FROM profile.candidate_profile p WHERE p.profile_status = 'active' ORDER BY p.id")
    cur.execute("SELECT COALESCE(MAX(id), 0) FROM recruitment.candidate_application;")
    min_id = cur.fetchone()[0]
    if not candidates or not live_jobs:
        print("[!] No active candidates or public jobs: skipping applications")
        return
    # popular jobs attract more applications
    job_cum = ctx.cumulative([1.0 / (rank + 1) ** 0.4 for rank in range(len(live_jobs))])
    seen, created = set(), 0
    cur.execute("CREATE TEMP TABLE IF NOT EXISTS tmp_app (candidate_profile_id BIGINT, job_posting_id BIGINT, applied_at TIMESTAMPTZ, "
                "source VARCHAR(30), created_by BIGINT) ON COMMIT DELETE ROWS;")
    attempts = 0
    while created < num and attempts < num * 20:
        buf = io.StringIO()
        rows = 0
        while rows < batch and created + rows < num and attempts < num * 20:
            attempts += 1
            cid, uid = ctx.rng.choice(candidates)
            jid, published = ctx.pick_cum(live_jobs, job_cum)
            if (cid, jid) in seen:
                continue
            horizon = (ctx.as_of - published).total_seconds() / 86400.0
            if horizon < 1:
                continue
            seen.add((cid, jid))
            applied_at = published + timedelta(days=ctx.rng.uniform(0, min(60.0, horizon)))
            source = ctx.pick(["direct", "job_alert", "referral", "campus", "other"], [0.62, 0.20, 0.10, 0.05, 0.03])
            buf.write(f"{cid}\t{jid}\t{applied_at.isoformat()}\t{source}\t{uid}\n")
            rows += 1
        if rows == 0:
            break
        buf.seek(0)
        cur.copy_expert("COPY tmp_app (candidate_profile_id, job_posting_id, applied_at, source, created_by) FROM STDIN", buf)
        cur.execute("INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, application_source, "
                    "applied_at, last_status_changed_at, created_by_user_account_id, updated_by_user_account_id) "
                    "SELECT candidate_profile_id, job_posting_id, 'applied', source, applied_at, applied_at, created_by, created_by FROM tmp_app "
                    "ON CONFLICT (candidate_profile_id, job_posting_id) DO NOTHING;")
        cur.execute("TRUNCATE tmp_app;")
        created += rows
        if len(seen) > 2_000_000:
            seen.clear()
    conn.commit()
    print(f"    -> {created:,} applications inserted in {time.time() - t0:.1f}s; now staging them through the pipeline")

    # The bulk move writes its own history with real dates, so the per-row triggers (history, audit columns,
    # transition check) are switched off for this one statement batch and switched back on straight after.
    cur.execute("ALTER TABLE recruitment.candidate_application DISABLE TRIGGER USER;")
    try:
        cur.execute(PROGRESSION_SQL, {"seed": ctx.seed, "min_id": min_id, "as_of": ctx.as_of})
    finally:
        cur.execute("ALTER TABLE recruitment.candidate_application ENABLE TRIGGER USER;")
    conn.commit()

    cur.execute("SELECT COUNT(*) FROM recruitment.candidate_application_partitioned;")
    if cur.fetchone()[0] == 0:
        cur.execute("INSERT INTO recruitment.candidate_application_partitioned (candidate_profile_id, job_posting_id, application_status, "
                    "application_source, applied_at, created_by_user_account_id, updated_by_user_account_id) "
                    "SELECT candidate_profile_id, job_posting_id, application_status, application_source, applied_at, "
                    "created_by_user_account_id, updated_by_user_account_id FROM recruitment.candidate_application "
                    "WHERE applied_at >= '2025-01-01' AND applied_at < '2028-01-01' ORDER BY id LIMIT 50000;")
        conn.commit()
    print(f"[+] Applications seeded in {time.time() - t0:.2f}s")


GIG_STATUS = ["open", "awarded", "in_progress", "completed", "cancelled"]
GIG_STATUS_WEIGHTS = [0.35, 0.12, 0.20, 0.28, 0.05]


def seed_gig_marketplace(conn, ctx, orgs):
    n_workers, n_requests = ctx.cfg["gig_workers"], ctx.cfg["gig_requests"]
    print(f"[*] Seeding {n_workers:,} gig workers and {n_requests:,} gig requests in every lifecycle state...")
    cur = conn.cursor()
    t0 = time.time()
    user_ids = one_column(cur, "SELECT u.id FROM core.user_account u JOIN core.user_role ur ON ur.user_account_id = u.id "
                               "JOIN core.role r ON r.id = ur.role_id AND r.name = 'candidate' "
                               "LEFT JOIN gig.gig_worker_profile g ON g.user_account_id = u.id WHERE g.id IS NULL ORDER BY u.id LIMIT %s",
                          (n_workers,))
    if not user_ids:
        print("[!] No candidate accounts available for gig workers: skipping gig marketplace")
        return
    skill_ids = one_column(cur, "SELECT id FROM master.skill ORDER BY id LIMIT 8")
    today = ctx.as_of.date()

    workers = []
    for uid in user_ids:
        hourly = round(ctx.rng.uniform(25.0, 150.0), 2)
        workers.append((uid, f"Contractor: {ctx.rng.choice(TITLES)}", hourly, round(hourly * 8, 2), "USD",
                        ctx.rng.random() < 0.8, round(ctx.rng.uniform(3.5, 5.0), 2),
                        ctx.pick(["verified", "unverified", "suspended"], [0.80, 0.15, 0.05])))
    worker_ids = [r[0] for r in bulk(cur, "INSERT INTO gig.gig_worker_profile (user_account_id, headline, hourly_rate, daily_rate, currency_code, "
                                          "is_available, average_rating, verification_status) VALUES %s RETURNING id", workers, returning=True)]
    bulk(cur, "INSERT INTO gig.gig_worker_service (gig_worker_profile_id, skill_id, custom_title, rate_override, currency_code) VALUES %s",
         [(w, s, "Senior Consulting Specialist", round(ctx.rng.uniform(40.0, 140.0), 2), "USD") for w in worker_ids
          for s in ctx.rng.sample(skill_ids, min(2, len(skill_ids)))])
    bulk(cur, "INSERT INTO gig.gig_worker_availability (gig_worker_profile_id, available_from, available_to, daily_available_hours) VALUES %s",
         [(w, today - timedelta(days=120), today + timedelta(days=180), 8.0) for w in worker_ids])

    # ---- requests, then applications and assignments consistent with each request's state ----
    req_rows, req_state = [], []
    for _ in range(n_requests):
        org = ctx.rng.choice(orgs)
        status = ctx.pick(GIG_STATUS, GIG_STATUS_WEIGHTS)
        if status == "completed":
            start = today - timedelta(days=ctx.rng.randint(35, 120)); end = start + timedelta(days=ctx.rng.randint(5, 25))
        elif status == "in_progress":
            start = today - timedelta(days=ctx.rng.randint(1, 20)); end = today + timedelta(days=ctx.rng.randint(2, 30))
        else:
            start = today + timedelta(days=ctx.rng.randint(5, 60)); end = start + timedelta(days=ctx.rng.randint(5, 25))
        pricing = ctx.pick(["fixed", "hourly_rate", "daily_rate"], [0.6, 0.25, 0.15])
        req_rows.append((org["id"], org["owner"], f"Gig: {ctx.rng.choice(TITLES)} module", "Short, well-defined project",
                         "Working code and documentation", pricing, round(ctx.rng.uniform(1000.0, 12000.0), 2), "USD", start, end, status))
        req_state.append((status, start, end, org["owner"]))
    req_ids = [r[0] for r in bulk(cur, "INSERT INTO gig.gig_request (organization_id, created_by_user_account_id, title, description, deliverables, "
                                       "pricing_type, budget_amount, currency_code, start_date, end_date, request_status) VALUES %s RETURNING id",
                                  req_rows, returning=True)]

    free_workers = worker_ids[:]
    ctx.rng.shuffle(free_workers)                      # each accepted worker is used once, so active windows never overlap
    apps, accepted = [], []
    now_ts = ctx.as_of
    for rid, (status, start, end, owner) in zip(req_ids, req_state):
        if status == "open":
            bidders = ctx.rng.sample(worker_ids, min(ctx.rng.randint(0, 4), len(worker_ids)))
            apps += [(rid, w, round(ctx.rng.uniform(800.0, 9000.0), 2), "USD", ctx.rng.randint(5, 25), "Happy to deliver this.", "submitted", None) for w in bidders]
        elif status == "cancelled":
            for w in ctx.rng.sample(worker_ids, min(ctx.rng.randint(0, 2), len(worker_ids))):
                outcome = ctx.pick(["rejected", "withdrawn"], [0.6, 0.4])
                # BR-024: a decision time exists if and only if the application was accepted or rejected
                apps.append((rid, w, round(ctx.rng.uniform(800.0, 9000.0), 2), "USD", 10, "Proposal", outcome, now_ts if outcome == "rejected" else None))
        elif free_workers:
            winner = free_workers.pop()
            bid = round(ctx.rng.uniform(1500.0, 9000.0), 2)
            apps.append((rid, winner, bid, "USD", (end - start).days + 1, "Accepted proposal", "accepted", now_ts - timedelta(days=ctx.rng.randint(1, 30))))
            accepted.append((rid, winner, bid, status, start, end, owner))
            loser_pool = [w for w in ctx.rng.sample(worker_ids, min(3, len(worker_ids))) if w != winner]
            apps += [(rid, w, round(ctx.rng.uniform(1500.0, 9000.0), 2), "USD", 10, "Proposal", "rejected", now_ts) for w in loser_pool[:ctx.rng.randint(0, 2)]]
    app_rows = bulk(cur, "INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id, bid_amount, currency_code, proposed_duration_days, "
                         "pitch, application_status, decided_at) VALUES %s ON CONFLICT DO NOTHING RETURNING id, gig_request_id, gig_worker_profile_id",
                    apps, returning=True)
    app_id_of = {(r, w): a for a, r, w in app_rows}

    assigns = []
    for rid, wid, bid, status, start, end, owner in accepted:
        aid = app_id_of.get((rid, wid))
        if aid is None:
            continue
        state = "completed" if status == "completed" else "active"
        assigns.append((rid, aid, wid, start, end, bid, "USD", state, f"HANDOFF-{aid:08d}", owner, status))
    assign_ids = [r[0] for r in bulk(cur, "INSERT INTO gig.gig_assignment (gig_request_id, gig_application_id, gig_worker_profile_id, assigned_start_date, "
                                           "assigned_end_date, agreed_amount, currency_code, assignment_status, external_handoff_ref) VALUES %s RETURNING id",
                                     [a[:9] for a in assigns], returning=True)]

    earnings, ratings = [], []
    for aid, a in zip(assign_ids, assigns):
        agreed, owner, req_status = a[5], a[9], a[10]
        total = round(float(agreed) * ctx.rng.uniform(0.85, 1.0), 2) if req_status == "completed" else 0.00
        earnings.append((aid, agreed, total, agreed, "USD", f"sync-{aid}"))
        if req_status == "completed":
            ratings.append((aid, owner, round(ctx.rng.uniform(3.0, 5.0), 2), ctx.rng.randint(3, 5), ctx.rng.randint(3, 5), "Delivered as agreed."))
    bulk(cur, "INSERT INTO gig.gig_external_earnings (gig_assignment_id, estimated_earnings, total_earnings, projected_earnings, currency_code, external_sync_hash) VALUES %s", earnings)
    bulk(cur, "INSERT INTO gig.gig_rating (gig_assignment_id, rater_user_account_id, rating_score, quality_score, communication_score, review_text) VALUES %s", ratings)

    prefs = []
    for org in ctx.rng.sample(orgs, min(len(orgs), 20)):
        for w in ctx.rng.sample(worker_ids, min(2, len(worker_ids))):
            prefs.append((org["id"], w, ctx.pick(["favourite", "blacklisted"], [0.8, 0.2]), "Past project outcome"))
    bulk(cur, "INSERT INTO gig.gig_worker_preference (organization_id, gig_worker_profile_id, preference_type, reason) VALUES %s ON CONFLICT DO NOTHING", prefs)
    conn.commit()
    print(f"[+] Gig marketplace seeded in {time.time() - t0:.2f}s ({len(assign_ids):,} assignments, {len(ratings):,} ratings)")


def seed_commercial(conn, ctx, orgs):
    print(f"[*] Seeding licences, subscriptions, payments, invoices, wallets and ledgers for {len(orgs):,} organisations...")
    cur = conn.cursor()
    t0 = time.time()
    plan_ids = one_column(cur, "SELECT id FROM commercial.subscription_plan WHERE is_active ORDER BY id")
    candidates = _rows(cur, "SELECT id FROM profile.candidate_profile ORDER BY id LIMIT 5000")
    cand_ids = [c[0] for c in candidates]
    now = ctx.as_of

    for org in orgs:
        oid, owner, rec = org["id"], org["owner"], org["recruiter"]
        cur.execute("INSERT INTO commercial.subscription_licence (organization_id, licence_key, licence_name, max_users, max_devices_per_user, "
                    "valid_from, valid_to, licence_status) VALUES (%s, %s, 'Enterprise Talent Suite', 25, %s, %s, %s, 'active') RETURNING id",
                    (oid, f"LIC-{oid:07d}", ctx.rng.choice([2, 3, 5]), now - timedelta(days=90), now + timedelta(days=275)))
        lic_id = cur.fetchone()[0]
        bulk(cur, "INSERT INTO commercial.licence_seat_allocation (subscription_licence_id, user_account_id, allocated_by_user_account_id, allocated_at) VALUES %s",
             [(lic_id, owner, owner, now - timedelta(days=89)), (lic_id, rec, owner, now - timedelta(days=89))])
        if plan_ids:
            cur.execute("INSERT INTO commercial.subscription (subscription_licence_id, subscription_plan_id, period_start, period_end, auto_renew, subscription_status) "
                        "VALUES (%s, %s, %s, %s, TRUE, 'active')", (lic_id, ctx.rng.choice(plan_ids), now - timedelta(days=90), now + timedelta(days=275)))

        # recharges (each backed by a captured payment and a paid invoice), then credit spent on profile downloads
        recharges = [float(ctx.rng.choice([500, 1000, 2000, 5000])) for _ in range(ctx.rng.randint(1, 3))]
        downloads = ctx.rng.randint(0, 8)
        balance = sum(recharges) - 10.0 * downloads
        while balance < 0:                              # never spend more than was recharged
            downloads -= 1; balance += 10.0
        cur.execute("INSERT INTO commercial.wallet (organization_id, balance, currency_code) VALUES (%s, %s, 'USD') RETURNING id", (oid, round(balance, 2)))
        wallet_id = cur.fetchone()[0]

        running, first_credit_ledger, first_order = 0.0, None, None
        for k, amount in enumerate(recharges):
            when = now - timedelta(days=ctx.rng.uniform(5, 85))
            cur.execute("INSERT INTO commercial.payment_order (organization_id, user_account_id, gateway_provider, gateway_order_id, order_amount, currency_code, order_status) "
                        "VALUES (%s, %s, 'razorpay', %s, %s, 'USD', 'captured') RETURNING id", (oid, owner, f"order_{oid}_{k}", amount))
            order_id = cur.fetchone()[0]
            tax = round(amount * 0.18, 2)
            cur.execute("INSERT INTO commercial.invoice (organization_id, payment_order_id, invoice_number, subtotal_amount, tax_amount, total_amount, currency_code, invoice_status, issued_at, paid_at) "
                        "VALUES (%s, %s, %s, %s, %s, %s, 'USD', 'paid', %s, %s)", (oid, order_id, f"INV-{oid:07d}-{k + 1}", amount, tax, round(amount + tax, 2), when, when))
            running += amount
            cur.execute("INSERT INTO commercial.wallet_ledger (wallet_id, entry_type, amount, currency_code, balance_after, reference_type, reference_id, notes, created_by_user_account_id, recorded_at) "
                        "VALUES (%s, 'credit', %s, 'USD', %s, 'recharge', %s, 'Wallet recharge', %s, %s) RETURNING id", (wallet_id, amount, round(running, 2), order_id, owner, when))
            if first_credit_ledger is None:
                first_credit_ledger, first_order = cur.fetchone()[0], order_id

        for k in range(downloads):
            when = now - timedelta(days=ctx.rng.uniform(0, 80))
            running -= 10.0
            cur.execute("INSERT INTO commercial.wallet_ledger (wallet_id, entry_type, amount, currency_code, balance_after, reference_type, notes, created_by_user_account_id, recorded_at) "
                        "VALUES (%s, 'debit', 10.00, 'USD', %s, 'profile_download', 'Profile download', %s, %s) RETURNING id", (wallet_id, round(running, 2), rec, when))
            ledger_id = cur.fetchone()[0]
            if cand_ids:
                cur.execute("INSERT INTO commercial.candidate_profile_download_history (organization_id, downloader_user_account_id, candidate_profile_id, credit_deduction_amount, currency_code, wallet_ledger_id, downloaded_at) "
                            "VALUES (%s, %s, %s, 10.00, 'USD', %s, %s)", (oid, rec, ctx.rng.choice(cand_ids), ledger_id, when))

        # one org in ten gets a refunded recharge: a correcting ledger entry that points at the original, never an update
        if first_credit_ledger and ctx.rng.random() < 0.10 and balance >= recharges[0] and len(recharges) > 1:
            running -= recharges[0]
            cur.execute("INSERT INTO commercial.wallet_ledger (wallet_id, entry_type, amount, currency_code, balance_after, reference_type, correction_of_ledger_id, notes, created_by_user_account_id) "
                        "VALUES (%s, 'correction_debit', %s, 'USD', %s, 'correction', %s, 'Refund of first recharge', %s)", (wallet_id, recharges[0], round(running, 2), first_credit_ledger, owner))
            cur.execute("INSERT INTO commercial.payment_refund (payment_order_id, refund_amount, currency_code, gateway_refund_ref, refund_reason, refund_status, processed_at) "
                        "VALUES (%s, %s, 'USD', %s, 'Requested by customer', 'processed', %s)", (first_order, recharges[0], f"rfnd_{oid}", now))
            cur.execute("UPDATE commercial.wallet SET balance = %s WHERE id = %s", (round(running, 2), wallet_id))

        # sessions: owner on one or two devices, always within the licence's device limit
        for d in range(ctx.rng.choice([1, 1, 2])):
            cur.execute("INSERT INTO core.user_session (user_account_id, device_identifier, session_token_hash, started_at, last_activity_at) "
                        "VALUES (%s, %s, encode(sha256(%s::bytea), 'hex'), %s, %s)",
                        (owner, f"device-{d}-{owner}", f"session-{owner}-{d}", now - timedelta(days=2), now - timedelta(hours=ctx.rng.randint(0, 40))))
    conn.commit()
    print(f"[+] Commercial data seeded in {time.time() - t0:.2f}s")


def seed_sourcing(conn, ctx, orgs):
    cur = conn.cursor()
    t0 = time.time()
    role_ids = dict((r[0], r[1]) for r in _rows(cur, "SELECT name, id FROM core.role"))
    jobs = _rows(cur, "SELECT j.id, o.owner FROM recruitment.job_posting j JOIN (SELECT organization_id, user_account_id AS owner FROM recruitment.organization_member WHERE organization_role = 'owner') o "
                      "ON o.organization_id = j.organization_id WHERE j.job_status IN ('published', 'paused', 'closed', 'filled') ORDER BY j.id")
    cands = _rows(cur, "SELECT id FROM profile.candidate_profile WHERE profile_status = 'active' ORDER BY id")
    if not jobs or not cands:
        return
    n_cons = max(3, len(orgs) // 4)
    print(f"[*] Seeding {n_cons:,} consultants, sourcing requests, submissions and outreach campaigns...")
    offset = _next_index(cur)
    cons_rows = bulk(cur, "INSERT INTO core.user_account (email, phone_e164, phone_country_code, account_status, preferred_language) VALUES %s RETURNING id, email",
                     [(f"consultant_{offset + i + 1}@example.com", f"+9195{ctx.rng.randint(10000000, 99999999)}", "IN", "active", "en") for i in range(n_cons)], returning=True)
    _add_roles_and_credentials(cur, cons_rows, "consultant", role_ids)
    consultants = [r[0] for r in cons_rows]

    open_jobs = ctx.rng.sample(jobs, max(1, len(jobs) // 5))
    bulk(cur, "INSERT INTO sourcing.job_consultant_policy (job_posting_id, is_open_to_consultants, max_consultants, bounty_amount, currency_code) VALUES %s ON CONFLICT DO NOTHING",
         [(j, True, 3, ctx.rng.choice([500, 1000, 1500]), "USD") for j, _ in open_jobs])

    req_rows = []
    for jid, owner in open_jobs:
        for c in ctx.rng.sample(consultants, min(ctx.rng.randint(1, 2), len(consultants))):
            status = ctx.pick(["requested", "accepted", "declined", "revoked"], [0.30, 0.50, 0.15, 0.05])
            decided = ctx.days_ago(1, 60) if status in ("accepted", "declined") else None
            req_rows.append((jid, c, status, "Strong bench for this role", owner if decided else None, decided, "Fits budget" if status == "accepted" else None))
    reqs = bulk(cur, "INSERT INTO sourcing.consultant_sourcing_request (job_posting_id, consultant_user_account_id, request_status, proposal_notes, decided_by_user_account_id, decided_at, decision_reason) "
                     "VALUES %s ON CONFLICT DO NOTHING RETURNING id, job_posting_id, consultant_user_account_id, request_status", req_rows, returning=True)
    subs = []
    for rid, jid, cons, status in reqs:
        if status != "accepted":
            continue
        for (cid,) in ctx.rng.sample(cands, min(ctx.rng.randint(1, 4), len(cands))):
            subs.append((rid, jid, cid, cons, ctx.pick(["submitted", "shortlisted", "accepted", "rejected", "hired"], [0.35, 0.25, 0.15, 0.15, 0.10])))
    bulk(cur, "INSERT INTO sourcing.sourcing_submission (consultant_sourcing_request_id, job_posting_id, candidate_profile_id, submitted_by_user_account_id, submission_status) VALUES %s ON CONFLICT DO NOTHING", subs)

    for org in ctx.rng.sample(orgs, max(1, len(orgs) // 3)):
        picked = [c for (c,) in ctx.rng.sample(cands, min(ctx.rng.randint(5, 30), len(cands)))]
        cur.execute("INSERT INTO sourcing.outreach_batch (organization_id, campaign_name, channel, subject, message_body, total_recipients, total_credits_deducted, status, completed_at, created_by_user_account_id) "
                    "VALUES (%s, %s, 'email', 'Opportunities that match your profile', 'We would like to talk about a role.', %s, %s, 'completed', %s, %s) RETURNING id",
                    (org["id"], f"Campaign {org['id']}", len(picked), round(len(picked) * 0.5, 2), ctx.days_ago(1, 60), org["recruiter"]))
        batch_id = cur.fetchone()[0]
        rec = []
        for cid in picked:
            st = ctx.pick(["sent", "delivered", "opened", "responded", "bounced", "blocked"], [0.10, 0.35, 0.25, 0.15, 0.10, 0.05])
            sent = None if st == "blocked" else ctx.days_ago(1, 60)
            rec.append((batch_id, cid, st, sent, sent + timedelta(minutes=1) if sent and st in ("delivered", "opened", "responded") else None,
                        sent + timedelta(hours=ctx.rng.randint(1, 72)) if sent and st == "responded" else None))
        bulk(cur, "INSERT INTO sourcing.outreach_recipient (outreach_batch_id, candidate_profile_id, delivery_status, sent_at, delivered_at, response_recorded_at) VALUES %s ON CONFLICT DO NOTHING", rec)
    conn.commit()
    print(f"[+] Sourcing seeded in {time.time() - t0:.2f}s ({len(reqs):,} requests, {len(subs):,} submissions)")


def seed_messaging_and_support(conn, ctx, orgs):
    cur = conn.cursor()
    t0 = time.time()
    users = one_column(cur, "SELECT u.id FROM core.user_account u JOIN core.user_role ur ON ur.user_account_id = u.id JOIN core.role r ON r.id = ur.role_id AND r.name = 'candidate' ORDER BY u.id")
    if not users:
        return
    n_notif = max(50, len(users) // 2)
    n_tickets = max(10, len(users) // 25)
    print(f"[*] Seeding {n_notif:,} notifications, {n_tickets:,} support tickets and candidate blocks...")
    subjects = ["New job matching your skills", "Your application was viewed", "Complete your profile", "Interview invitation"]
    notif = []
    for _ in range(n_notif):
        status = ctx.pick(["queued", "sent", "delivered", "read", "failed"], [0.03, 0.10, 0.52, 0.28, 0.07])
        created = ctx.days_ago(0, 90)
        sent = None if status == "queued" else created + timedelta(seconds=ctx.rng.randint(1, 30))
        delivered = sent + timedelta(seconds=ctx.rng.randint(1, 120)) if status in ("delivered", "read") else None
        read = delivered + timedelta(minutes=ctx.rng.randint(1, 3000)) if status == "read" else None
        notif.append((ctx.rng.choice(users), ctx.pick(["email", "in_app", "push", "sms"], [0.45, 0.30, 0.20, 0.05]),
                      ctx.rng.choice(subjects), "Open Talentra to see more.", status, sent, delivered, read, created, created))
    bulk(cur, "INSERT INTO messaging.notification_delivery (recipient_user_account_id, channel, subject, body_snippet, delivery_status, sent_at, delivered_at, read_at, created_at, updated_at) VALUES %s", notif)

    tickets = []
    for i in range(n_tickets):
        tickets.append((f"TCK-{i + 1:07d}", ctx.rng.choice(users), ctx.pick(SUPPORT_CATEGORIES, [0.25, 0.2, 0.3, 0.1, 0.15]),
                        ctx.rng.choice(SUPPORT_SUBJECTS), ctx.pick(["low", "medium", "high", "urgent"], [0.35, 0.40, 0.20, 0.05]),
                        ctx.pick(["open", "in_progress", "waiting_on_user", "resolved", "closed"], [0.25, 0.20, 0.10, 0.25, 0.20])))
    bulk(cur, "INSERT INTO messaging.support_ticket (ticket_number, requester_user_account_id, category, subject, priority, ticket_status) VALUES %s ON CONFLICT DO NOTHING", tickets)

    blockers = ctx.rng.sample(users, max(1, len(users) // 50))
    bulk(cur, "INSERT INTO core.user_block (blocker_user_account_id, blocked_organization_id, block_reason) VALUES %s",
         [(b, ctx.rng.choice(orgs)["id"], "Unsolicited recruiter outreach") for b in blockers])
    # some candidates also block an individual recruiter (a separate row: a block names a user or an organisation, never both)
    bulk(cur, "INSERT INTO core.user_block (blocker_user_account_id, blocked_user_account_id, block_reason) VALUES %s ON CONFLICT DO NOTHING",
         [(b, ctx.rng.choice(orgs)["recruiter"], "Repeated unsolicited messages") for b in blockers[: max(1, len(blockers) // 2)]])
    conn.commit()
    print(f"[+] Messaging and support seeded in {time.time() - t0:.2f}s")


INSTITUTIONS = ["State Technical University", "City College of Commerce", "National Institute of Technology",
                "Metropolitan University", "Coastal Polytechnic", "Heritage Business School"]
FIELDS = ["Computer Science", "Information Systems", "Business Administration", "Electronics", "Statistics", "Finance"]
EMPLOYERS = ["Acme Systems", "Orbit Software", "Pinnacle Health", "Globe Logistics", "Brightpath Education", "Northstar Retail", "Helix Labs"]
SEARCH_TERMS = ["postgresql dba", "python backend remote", "data engineer", "react developer", "devops kubernetes", "product manager fintech"]


def _chunks(cur, sql, size):
    """Yield rows of `sql` (ordered, with a %s placeholder for the last id) in chunks."""
    last = 0
    while True:
        cur.execute(sql, (last, size))
        rows = cur.fetchall()
        if not rows:
            return
        yield rows
        last = rows[-1][0]


def seed_profile_depth(conn, ctx):
    """Education, experience, languages, projects, documents, completion score, activity and preferences."""
    cur = conn.cursor()
    t0 = time.time()
    quals = one_column(cur, "SELECT id FROM master.qualification ORDER BY id")
    roles = one_column(cur, "SELECT id FROM master.job_role ORDER BY id")
    emp_types = one_column(cur, "SELECT id FROM master.employment_type ORDER BY id")
    langs = _rows(cur, "SELECT id, code FROM master.language ORDER BY id")
    templates = one_column(cur, "SELECT id FROM profile.resume_template ORDER BY id")
    print("[*] Seeding education, experience, languages, projects, documents and profile completion...")
    today = ctx.as_of.date()
    n = 0
    sql = ("SELECT p.id, p.user_account_id, p.total_experience_years, p.headline IS NOT NULL, p.professional_summary IS NOT NULL "
           "FROM profile.candidate_profile p WHERE p.id > %s ORDER BY p.id LIMIT %s")
    for rows in _chunks(cur, sql, ctx.cfg["batch_size"]):
        edu, work, lang, proj, docs, comp = [], [], [], [], [], []
        for pid, uid, exp, has_head, has_sum in rows:
            exp = float(exp or 0)
            grad_year = today.year - int(exp) - ctx.rng.randint(0, 2)
            edu.append((pid, ctx.rng.choice(quals), ctx.rng.choice(INSTITUTIONS), ctx.rng.choice(FIELDS),
                        today.replace(year=grad_year - 4, month=7, day=1), today.replace(year=grad_year, month=6, day=30),
                        ctx.pick(["First Class", "Distinction", "Second Class"], [0.4, 0.2, 0.4]), "classification"))
            jobs = min(int(exp // 3) + (1 if exp >= 1 else 0), 5)
            cursor_date = today
            for k in range(jobs):
                dur = ctx.rng.randint(14, 40)                               # months
                end = None if k == 0 else cursor_date
                start = (cursor_date - timedelta(days=30 * dur))
                work.append((pid, ctx.rng.choice(roles) if roles else None, ctx.rng.choice(EMPLOYERS), ctx.rng.choice(TITLES),
                             ctx.rng.choice(emp_types), start, end, k == 0))
                cursor_date = start - timedelta(days=ctx.rng.randint(5, 60))
            for lid, code in ctx.rng.sample(langs, ctx.rng.randint(1, 3)):
                lang.append((pid, lid, ctx.pick(["basic", "conversational", "professional", "fluent", "native"], [0.1, 0.2, 0.3, 0.2, 0.2]), True, True, True))
            for _ in range(ctx.pick([0, 1, 2], [0.5, 0.35, 0.15])):
                ongoing = ctx.rng.random() < 0.2
                s = today - timedelta(days=ctx.rng.randint(60, 900))
                proj.append((pid, f"{ctx.rng.choice(TITLES)} case study", "Contributor", ctx.pick(["personal", "academic", "professional", "open_source"], [0.3, 0.2, 0.4, 0.1]),
                             s, None if ongoing else s + timedelta(days=ctx.rng.randint(14, 200)), ongoing))
            has_resume = ctx.rng.random() < 0.7
            if has_resume:
                digest = "%064x" % ctx.rng.getrandbits(256)
                docs.append((pid, "resume", "ready", f"resume_{pid}.pdf", "s3", f"resumes/{pid // 1000}/{pid}.pdf", "application/pdf",
                             ctx.rng.randint(40_000, 900_000), digest, True, ctx.rng.choice(templates) if templates and ctx.rng.random() < 0.4 else None))
            flags = [has_head, has_sum, True, True, jobs > 0, has_resume, bool(proj)]
            comp.append((pid, round(100.0 * sum(flags) / 7, 2), *flags))
        bulk(cur, "INSERT INTO profile.candidate_education (candidate_profile_id, qualification_id, institution_name, field_of_study, start_date, end_date, grade_value, grade_scale) VALUES %s", edu)
        bulk(cur, "INSERT INTO profile.candidate_work_experience (candidate_profile_id, job_role_id, employer_name, job_title, employment_type_id, start_date, end_date, is_current) VALUES %s", work)
        bulk(cur, "INSERT INTO profile.candidate_language (candidate_profile_id, language_id, proficiency_level, can_read, can_write, can_speak) VALUES %s ON CONFLICT DO NOTHING", lang)
        bulk(cur, "INSERT INTO profile.candidate_project (candidate_profile_id, title, candidate_role, project_type, start_date, end_date, is_ongoing) VALUES %s", proj)
        bulk(cur, "INSERT INTO profile.candidate_document (candidate_profile_id, document_type, document_status, original_filename, storage_provider, storage_key, mime_type, file_size_bytes, checksum_sha256, is_primary, resume_template_id) VALUES %s", docs)
        bulk(cur, "INSERT INTO profile.candidate_profile_completion (candidate_profile_id, total_score_percentage, has_headline, has_summary, has_skills, has_education, has_experience, has_resume, has_projects) VALUES %s ON CONFLICT DO NOTHING", comp)
        conn.commit()
        n += len(rows)
    print(f"[+] Profile depth seeded for {n:,} candidates in {time.time() - t0:.2f}s")


def seed_engagement(conn, ctx, orgs):
    """Activity, searches, views, bookmarks, assessments, courses, preferences, consent, community, referrals."""
    cur = conn.cursor()
    t0 = time.time()
    people = _rows(cur, "SELECT p.id, p.user_account_id FROM profile.candidate_profile p ORDER BY p.id")
    if not people:
        return
    print(f"[*] Seeding activity, searches, profile views, assessments, courses, preferences and community for {len(people):,} candidates...")
    as_of = ctx.as_of
    pick_n = lambda frac: ctx.rng.sample(people, max(1, int(len(people) * frac)))

    # candidate activity (append-only) and search history
    acts = []
    for pid, uid in pick_n(0.30):
        for _ in range(ctx.rng.randint(1, 4)):
            acts.append((uid, pid, ctx.pick(["login", "profile_update", "resume_download", "resume_upload", "logout"], [0.4, 0.2, 0.15, 0.1, 0.15]),
                         f"10.{ctx.rng.randint(0, 255)}.{ctx.rng.randint(0, 255)}.{ctx.rng.randint(1, 254)}", ctx.days_ago(0, 120)))
    bulk(cur, "INSERT INTO profile.candidate_activity_log (user_account_id, candidate_profile_id, activity_type, client_ip, occurred_at) VALUES %s", acts)
    bulk(cur, "INSERT INTO profile.candidate_search_history (candidate_profile_id, query_text, result_count, searched_at) VALUES %s",
         [(pid, ctx.rng.choice(SEARCH_TERMS), ctx.rng.randint(0, 400), ctx.days_ago(0, 60)) for pid, _ in pick_n(0.20) for _ in range(ctx.rng.randint(1, 3))])

    # recruiters look at, and bookmark, candidates
    views, marks = [], []
    for org in orgs:
        for pid, _ in ctx.rng.sample(people, min(len(people), ctx.rng.randint(3, 25))):
            views.append((pid, org["recruiter"], org["id"], ctx.pick(["search", "direct_link", "sourcing", "applicant_review"], [0.5, 0.1, 0.2, 0.2]),
                          ctx.pick([0.0, 1.0], [0.6, 0.4]), ctx.days_ago(0, 120)))
        for pid, _ in ctx.rng.sample(people, min(len(people), ctx.rng.randint(0, 6))):
            marks.append((org["id"], org["recruiter"], pid, "Follow up next quarter"))
    bulk(cur, "INSERT INTO profile.profile_view_history (candidate_profile_id, viewer_user_account_id, organization_id, view_source, credit_deducted, viewed_at) VALUES %s", views)
    bulk(cur, "INSERT INTO profile.recruiter_bookmark (organization_id, user_account_id, candidate_profile_id, notes) VALUES %s ON CONFLICT DO NOTHING", marks)

    # assessments and courses
    skills = one_column(cur, "SELECT id FROM master.skill ORDER BY id LIMIT 6")
    assess = bulk(cur, "INSERT INTO profile.candidate_assessment (title, assessment_provider, skill_id, total_questions, duration_minutes, passing_percentage) VALUES %s RETURNING id, passing_percentage",
                  [(f"{t} proficiency test", "Talentra Assess", s, 40, 45, 60.0) for t, s in zip(["SQL", "Python", "Docker", "React", "Java", "Linux"], skills)], returning=True)
    scores = []
    for pid, _ in pick_n(0.25):
        aid, passing = ctx.rng.choice(assess)
        mx = 40.0; got = round(ctx.rng.uniform(10, 40), 1)
        scores.append((pid, aid, got, mx, round(ctx.rng.uniform(5, 99), 1), got / mx * 100 >= float(passing), ctx.days_ago(1, 200)))
    bulk(cur, "INSERT INTO profile.candidate_assessment_score (candidate_profile_id, candidate_assessment_id, score_obtained, max_score, percentile, is_passed, attempted_at) VALUES %s ON CONFLICT DO NOTHING", scores)
    courses = [r[0] for r in bulk(cur, "INSERT INTO profile.course (code, title, provider_name, duration_hours, language_code) VALUES %s ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title RETURNING id",
                                  [(f"course-{i}", t, "Talentra Academy", d, "en") for i, (t, d) in enumerate(
                                      [("SQL foundations", 12.5), ("Python for data", 20.0), ("Docker essentials", 8.0), ("System design", 16.0),
                                       ("Interview skills", 4.0), ("Cloud basics", 10.0), ("Agile delivery", 6.0), ("Data modelling", 14.0)], 1)], returning=True)]
    enrol = []
    for pid, _ in pick_n(0.15):
        status = ctx.pick(["enrolled", "in_progress", "completed", "dropped"], [0.25, 0.30, 0.35, 0.10])
        enrolled = ctx.days_ago(30, 300)
        done = enrolled + timedelta(days=ctx.rng.randint(5, 40)) if status == "completed" else None
        enrol.append((pid, ctx.rng.choice(courses), status, enrolled, done, round(ctx.rng.uniform(55, 100), 1) if status == "completed" else None))
    bulk(cur, "INSERT INTO profile.course_enrolment (candidate_profile_id, course_id, enrolment_status, enrolled_at, completed_at, score_percent) VALUES %s ON CONFLICT DO NOTHING", enrol)

    # preferences, consent, alerts (set-based where the data already exists)
    cur.execute("INSERT INTO messaging.user_privacy_preference (user_account_id, profile_visibility, allow_recruiter_direct_message, show_salary_expectations, show_current_employer) "
                "SELECT user_account_id, visibility, visibility <> 'private', FALSE, visibility = 'public' FROM profile.candidate_profile ON CONFLICT DO NOTHING;")
    prefs = []
    for pid, uid in pick_n(0.40):
        for cat, ch in (("applications", "email"), ("job_alerts", "email"), ("job_alerts", "push"), ("marketing", "email")):
            prefs.append((uid, cat, ch, cat != "marketing" or ctx.rng.random() < 0.3))
    bulk(cur, "INSERT INTO messaging.user_notification_preference (user_account_id, notification_category, channel, is_enabled) VALUES %s ON CONFLICT DO NOTHING", prefs)
    cities = one_column(cur, "SELECT id FROM master.city ORDER BY id")
    bulk(cur, "INSERT INTO messaging.job_alert_preference (user_account_id, alert_name, keywords, city_id, minimum_salary, currency_code, frequency, is_active) VALUES %s",
         [(uid, "My saved search", ctx.rng.choice(SEARCH_TERMS), ctx.rng.choice(cities), ctx.rng.choice([60000, 90000, 120000]), "USD",
           ctx.pick(["instant", "daily", "weekly"], [0.2, 0.5, 0.3]), True) for _, uid in pick_n(0.20)])
    consents = []
    for _, uid in people:
        granted = ctx.days_ago(30, 700)
        consents.append((uid, "terms_of_service", "2026-01", True, granted)); consents.append((uid, "privacy_policy", "2026-01", True, granted))
        if ctx.rng.random() < 0.5:
            consents.append((uid, "marketing_communications", "2026-01", True, granted))
    bulk(cur, "INSERT INTO core.consent_record (user_account_id, consent_type, consent_version, is_granted, granted_at) VALUES %s", consents)
    bulk(cur, "INSERT INTO core.user_device (user_account_id, device_identifier, device_name, device_type, operating_system, is_trusted, first_seen_at, last_seen_at) VALUES %s ON CONFLICT DO NOTHING",
         [(o["owner"], f"device-{d}-{o['owner']}", "Work laptop", "laptop", "macOS", True, as_of - timedelta(days=60), as_of - timedelta(hours=ctx.rng.randint(1, 48)))
          for o in orgs for d in range(1)])

    # community, FAQs, templates, referrals
    cur.execute("SELECT COALESCE(MAX(id), 0) FROM messaging.community_post"); first_post = cur.fetchone()[0]
    posts = bulk(cur, "INSERT INTO messaging.community_post (author_user_account_id, title, content, topic, likes_count, is_pinned, content_language_code) VALUES %s RETURNING id",
                 [(uid, f"How I prepared for a {ctx.rng.choice(TITLES)} interview", "Sharing what worked for me over the last three months.",
                   ctx.rng.choice(["career", "interviews", "skills", "gigs"]), 0, False, "en") for _, uid in pick_n(0.02)], returning=True)
    reacts = [(p[0], uid, ctx.pick(["like", "celebrate", "support", "insightful"], [0.6, 0.15, 0.15, 0.1]))
              for p in posts for _, uid in ctx.rng.sample(people, min(len(people), ctx.rng.randint(0, 12)))]
    bulk(cur, "INSERT INTO messaging.post_reaction (community_post_id, user_account_id, reaction_type) VALUES %s ON CONFLICT DO NOTHING", reacts)
    bulk(cur, "INSERT INTO messaging.faq (category, question, answer, sort_order, is_published) VALUES %s",
         [("account", "How do I reset my password?", "Use the reset link on the sign-in page.", 1, True),
          ("account", "How do I delete my account?", "Request erasure from Privacy settings; it is processed within 30 days.", 2, True),
          ("billing", "How do I recharge my wallet?", "Open Billing, choose an amount and pay by card.", 1, True),
          ("jobs", "Why can't I see an employer's job?", "Unpublished jobs are visible only to the employer's own team.", 1, True),
          ("gigs", "Who pays for a gig?", "The requester pays through the platform; fulfilment is handled outside it.", 1, True)])
    bulk(cur, "INSERT INTO messaging.notification_template (template_code, channel, default_language_code, subject_template, body_template, is_active) VALUES %s ON CONFLICT DO NOTHING",
         [("application_received", "email", "en", "We received your application", "Thanks for applying to {{job_title}}.", True),
          ("interview_invite", "email", "en", "Interview invitation", "{{employer}} would like to interview you.", True),
          ("job_alert", "push", "en", "New jobs for you", "{{count}} new jobs match your saved search.", True)])
    refs = []
    for i, (pid, uid) in enumerate(pick_n(0.03)):
        status = ctx.pick(["invited", "registered", "qualified_hire", "reward_paid"], [0.4, 0.3, 0.2, 0.1])
        refs.append((uid, f"friend{i}_{uid}@example.org", f"REF-{uid}-{i}", status, 25.0 if status == "reward_paid" else None,
                     "USD" if status == "reward_paid" else None, as_of if status in ("qualified_hire", "reward_paid") else None))
    bulk(cur, "INSERT INTO messaging.referral_event (referrer_user_account_id, referred_email, referral_code, status, reward_amount, currency_code, qualified_at) VALUES %s ON CONFLICT DO NOTHING", refs)
    conn.commit()
    print(f"[+] Engagement data seeded in {time.time() - t0:.2f}s")


def seed_structure(conn, ctx, orgs):
    """Questionnaires and answers, positions, organisation hierarchy, recruiter mapping, identifiers, audit activity."""
    cur = conn.cursor()
    t0 = time.time()
    print("[*] Seeding questionnaires, positions, organisation structure, identifiers and audited actions...")

    # questionnaires on a third of the public jobs, answered by about 60% of their applicants
    jobs = _rows(cur, "SELECT id, created_by_user_account_id FROM recruitment.job_posting WHERE job_status IN ('published','paused','closed','filled') ORDER BY id")
    chosen = ctx.rng.sample(jobs, max(1, len(jobs) // 3)) if jobs else []
    qrows = bulk(cur, "INSERT INTO recruitment.job_questionnaire (job_posting_id, title, instructions, is_mandatory, created_by_user_account_id) VALUES %s RETURNING id",
                 [(j, "Screening questions", "Answer all questions.", True, by) for j, by in chosen], returning=True)
    questions = []
    for (qid,) in qrows:
        questions += [(qid, "Why do you want this role?", "text", None, True, 1),
                      (qid, "Years of relevant experience?", "numeric", None, True, 2),
                      (qid, "Can you relocate?", "boolean", None, False, 3),
                      (qid, "Preferred working hours?", "single_choice", '["day","night","flexible"]', False, 4)]
    bulk(cur, "INSERT INTO recruitment.job_questionnaire_question (job_questionnaire_id, question_text, question_type, options_json, is_required, sort_order) VALUES %s", questions)
    cur.execute("""
        INSERT INTO recruitment.application_question_response
            (candidate_application_id, job_questionnaire_question_id, response_text, selected_options_json, numeric_response, boolean_response)
        SELECT a.id, q.id,
               CASE WHEN q.question_type = 'text' THEN 'I enjoy building reliable systems.' END,
               CASE WHEN q.question_type = 'single_choice' THEN '["flexible"]'::jsonb END,
               CASE WHEN q.question_type = 'numeric' THEN round((1 + mod(abs(hashint8(a.id))::numeric, 12)), 1) END,
               CASE WHEN q.question_type = 'boolean' THEN mod(abs(hashint8(a.id + q.id))::numeric, 2) = 0 END
          FROM recruitment.candidate_application a
          JOIN recruitment.job_questionnaire jq ON jq.job_posting_id = a.job_posting_id
          JOIN recruitment.job_questionnaire_question q ON q.job_questionnaire_id = jq.id
         WHERE mod(abs(hashint8(a.id + %s))::numeric, 10) < 6
        ON CONFLICT DO NOTHING;""", (ctx.seed,))

    # positions: one per vacancy; a joined applicant fills the first
    cur.execute("""
        INSERT INTO recruitment.job_position (job_posting_id, position_reference_code, position_status, filled_by_candidate_profile_id, filled_at)
        SELECT j.id, 'POS-' || j.id || '-' || s.i,
               CASE WHEN s.i = 1 AND w.candidate_profile_id IS NOT NULL THEN 'filled'
                    WHEN j.job_status = 'cancelled' THEN 'cancelled' ELSE 'open' END,
               CASE WHEN s.i = 1 THEN w.candidate_profile_id END,
               CASE WHEN s.i = 1 AND w.candidate_profile_id IS NOT NULL THEN w.joined_at END
          FROM recruitment.job_posting j
          CROSS JOIN LATERAL generate_series(1, j.vacancy_count) AS s(i)
          LEFT JOIN LATERAL (SELECT a.candidate_profile_id, a.last_status_changed_at AS joined_at FROM recruitment.candidate_application a
                              WHERE a.job_posting_id = j.id AND a.application_status = 'joined' ORDER BY a.id LIMIT 1) w ON TRUE
        ON CONFLICT DO NOTHING;""")

    # organisation hierarchy, recruiter mapping and registration identifiers
    org_ids = [o["id"] for o in orgs]
    hier = [(p, c, ctx.pick(["subsidiary", "branch", "client", "vendor"], [0.4, 0.3, 0.2, 0.1]), True)
            for p, c in zip(org_ids[::10], org_ids[5::10]) if p != c]
    bulk(cur, "INSERT INTO recruitment.organization_hierarchy (parent_organization_id, child_organization_id, relationship_type, is_active) VALUES %s ON CONFLICT DO NOTHING", hier)
    maps = []
    for o in orgs[::5]:
        client = ctx.rng.choice(org_ids)
        if client != o["id"]:
            maps.append((o["recruiter"], o["id"], client, (ctx.as_of - timedelta(days=ctx.rng.randint(30, 300))).date(), None, True))
    bulk(cur, "INSERT INTO recruitment.recruiter_client_mapping (recruiter_user_account_id, agency_organization_id, client_organization_id, effective_from, effective_to, is_active) VALUES %s", maps)

    countries = {r[0]: r[1] for r in _rows(cur, "SELECT iso_alpha2, id FROM master.country")}
    org_country = {r[0]: r[1] for r in _rows(cur, "SELECT id, country_id FROM recruitment.organization")}
    by_id = {v: k for k, v in countries.items()}
    idents = []
    root = identifier_crypto.dev_root_key()      # seed data only: a fixed, public key; real data uses TALENTRA_IDENTIFIER_ROOT_KEY
    for o in orgs:
        cid = org_country.get(o["id"])
        iso = by_id.get(cid, "XX")
        if iso == "IN":
            body = f"29{ctx.rng.choice(['AABCU', 'AAPFU', 'BCDEF', 'ACMPK'])}{ctx.rng.randint(1000, 9999)}F1Z"
            typ, val = "gstin", body + identifier_crypto._gstin_check_char(body)
        elif iso == "US":
            typ, val = "ein", f"{ctx.rng.randint(10, 99)}-{ctx.rng.randint(1000000, 9999999)}"
        else:
            typ, val = "company_number", f"{iso}{ctx.rng.randint(100000, 999999)}"
        status = ctx.pick(["verified", "pending", "unverified", "rejected"], [0.6, 0.15, 0.2, 0.05])
        if cid is None:
            continue
        ct, bidx, ver = identifier_crypto.encrypt(o["id"], cid, typ, val, root)
        idents.append((o["id"], cid, typ, psycopg2.Binary(ct), psycopg2.Binary(bidx), ver, status, ctx.as_of if status == "verified" else None, o["owner"] if status == "verified" else None))
    bulk(cur, "INSERT INTO recruitment.organization_identifier (organization_id, country_id, identifier_type, identifier_ciphertext, identifier_bidx, identifier_key_version, verification_status, verified_at, verified_by_user_account_id) VALUES %s ON CONFLICT DO NOTHING",
         idents)

    # integration boundaries (docket section 6): verification outcomes, share events, review figures, legacy ids and a few outbox events
    cand_users = one_column(cur, "SELECT u.id FROM core.user_account u JOIN core.user_role ur ON ur.user_account_id = u.id JOIN core.role r ON r.id = ur.role_id AND r.name = 'candidate' ORDER BY u.id LIMIT 20000")
    ver = []
    for uid in cand_users[: max(5, len(cand_users) // 4)]:
        st = ctx.pick(["verified", "pending", "rejected", "expired"], [0.70, 0.15, 0.10, 0.05])
        when = ctx.days_ago(1, 300)
        token = ("tok_" + hashlib.sha256(f"idv-{uid}".encode()).hexdigest()[:24]) if st == "verified" else None
        ver.append((uid, "idv_demo", f"seed-{uid}", st, token, when, when + timedelta(minutes=5) if st == "verified" else None, when + timedelta(days=365) if st == "verified" else None))
    bulk(cur, "INSERT INTO core.identity_verification (user_account_id, provider_code, request_id, verification_status, provider_token_ref, requested_at, verified_at, expires_at) VALUES %s ON CONFLICT DO NOTHING", ver)
    job_ids = one_column(cur, "SELECT id FROM recruitment.job_posting ORDER BY id LIMIT 20000")
    if job_ids and cand_users:
        shares = [(ctx.rng.choice(cand_users), ctx.rng.choice(job_ids), ctx.pick(["whatsapp", "linkedin", "x", "facebook", "email", "copy_link"], [0.4, 0.25, 0.05, 0.1, 0.1, 0.1]), ctx.days_ago(0, 120))
                  for _ in range(max(20, len(cand_users) // 5))]
        bulk(cur, "INSERT INTO messaging.share_event (user_account_id, job_posting_id, channel, shared_at) VALUES %s", shares)
        legacy = [(jid, f"LEG-J-{jid:07d}", ctx.days_ago(0, 30)) for jid in job_ids[: max(10, len(job_ids) // 20)]]
        bulk(cur, "INSERT INTO messaging.external_reference (boundary_code, entity_name, entity_id, external_id, last_synced_at) SELECT 'legacy_sync', 'recruitment.job_posting', v.jid, v.ext, v.ts FROM (VALUES %s) AS v(jid, ext, ts) ON CONFLICT DO NOTHING", legacy,
             )
    reviews = []
    for o in orgs:
        if ctx.rng.random() < 0.6:
            cur_code = ctx.pick(["USD", "INR", "EUR"], [0.4, 0.5, 0.1]); has_sal = ctx.rng.random() < 0.7
            reviews.append((o["id"], ctx.pick(["ReviewHub", "WorkVoice"], [0.7, 0.3]), round(ctx.rng.uniform(2.5, 4.8), 2), ctx.rng.randint(3, 900),
                            round(ctx.rng.uniform(20000, 150000), 2) if has_sal else None, cur_code if has_sal else None, ctx.days_ago(0, 60)))
    bulk(cur, "INSERT INTO recruitment.company_review_summary (organization_id, source, rating_average, review_count, salary_median, currency_code, refreshed_at) VALUES %s ON CONFLICT DO NOTHING", reviews)
    for k, (code, direction, etype) in enumerate([("legacy_sync", "inbound", "job.upsert"), ("company_reviews", "inbound", "figures.refresh"), ("messaging_provider", "outbound", "notification.send"),
                                                  ("messaging_provider", "inbound", "notification.delivered"), ("identity_verification", "outbound", "verification.request"),
                                                  ("company_verification", "outbound", "company.lookup"), ("gig_fulfilment", "outbound", "assignment.handoff"), ("geolocation", "outbound", "geocode.request")]):
        cur.execute("SELECT messaging.enqueue_integration_event(%s, %s, %s, %s, %s::jsonb)", (code, direction, etype, f"seed-{k}", json.dumps({"seed": k})))

    # audited actions, produced by the real functions rather than inserted: refused logins and revoked sessions
    users = one_column(cur, "SELECT u.id FROM core.user_account u JOIN core.user_role ur ON ur.user_account_id = u.id JOIN core.role r ON r.id = ur.role_id AND r.name = 'candidate' ORDER BY u.id LIMIT 40")
    refused = revoked = 0
    for uid in users:
        tokens = [hashlib.sha256(f"seed-{uid}-{d}".encode()).hexdigest() for d in range(3)]
        got = []
        for d in range(3):
            cur.execute("SELECT core.create_session_with_device_limit(%s, %s, %s, %s, 'mobile', '10.0.0.1');", (uid, f"seed-device-{uid}-{d}", tokens[d], f"Phone {d}"))
            got.append(cur.fetchone()[0])
        refused += got.count(None)
        if got[0] is not None and ctx.rng.random() < 0.5:
            cur.execute("SELECT core.revoke_user_session(%s, %s, 'Logged out from another device');", (got[0], uid)); revoked += 1
    conn.commit()
    print(f"[+] Structure seeded in {time.time() - t0:.2f}s ({refused} logins refused and audited, {revoked} sessions revoked)")


def load_analytics(conn):
    print("[*] Loading the star schema from the operational tables (analytics.refresh_reporting_marts)...")
    t0 = time.time()
    with conn.cursor() as cur:
        cur.execute("CALL analytics.refresh_reporting_marts();")
    conn.commit()
    print(f"[+] Analytics loaded in {time.time() - t0:.2f}s")


# Loading synthetic accounts is not a sequence of real role, credential or consent changes, so these audit triggers are
# switched off for the duration of the load and switched back on afterwards. Real actions are still produced where the
# seed calls the real functions (refused logins, revoked sessions).
AUDIT_TRIGGERS = [
    ("core.user_credential", "trg_user_credential_audit"), ("core.user_role", "trg_user_role_audit"),
    ("core.consent_record", "trg_consent_record_audit"), ("core.user_block", "trg_user_block_audit"),
    ("recruitment.organization_member", "trg_organization_member_audit"), ("commercial.payment_order", "trg_payment_order_audit"),
    ("commercial.payment_refund", "trg_payment_refund_audit"), ("commercial.subscription_licence", "trg_subscription_licence_audit"),
    ("commercial.licence_seat_allocation", "trg_licence_seat_audit"), ("commercial.subscription", "trg_subscription_audit"),
]


def set_audit_triggers(conn, enabled):
    with conn.cursor() as cur:
        for table, trigger in AUDIT_TRIGGERS:
            cur.execute(f"ALTER TABLE {table} {'ENABLE' if enabled else 'DISABLE'} TRIGGER {trigger};")
    conn.commit()


def already_seeded(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT EXISTS (SELECT 1 FROM profile.candidate_profile);")
        return cur.fetchone()[0]


def seed_recruiter_portal(conn, ctx):
    """What the recruiter portal needs on top of the core data (migrations 040 to 042): departments, extra cities, perks, qualification
    requirements and assigned recruiters on jobs. Chosen with hashes of the row id and the seed, so the same seed gives the same data."""
    print("[*] Seeding recruiter-portal data (departments, locations, perks, qualifications, assigned recruiters)...")
    seed = int(ctx.seed)
    with conn.cursor() as cur:
        cur.execute("SELECT array_agg(id ORDER BY id) FROM master.department"); depts = cur.fetchone()[0]
        cur.execute("SELECT array_agg(id ORDER BY id) FROM master.job_perk"); perks = cur.fetchone()[0]
        cur.execute("SELECT array_agg(id ORDER BY id) FROM master.city"); cities = cur.fetchone()[0]
        cur.execute("SELECT array_agg(id ORDER BY id) FROM master.qualification WHERE name <> 'Other'"); quals = cur.fetchone()[0]
        h = lambda col, k: f"mod(abs(hashint8({col} # ({seed} * {k} + 7))::numeric), 1000000)"
        cur.execute(f"""UPDATE recruitment.job_posting j
                           SET department_id = (%(d)s::bigint[])[1 + {h('j.id', 3)}::int %% %(nd)s],
                               show_salary = (j.salary_min IS NOT NULL AND {h('j.id', 5)} < 600000),
                               has_variable_pay = ({h('j.id', 11)} < 200000)""", {"d": depts, "nd": len(depts)})
        cur.execute(f"""INSERT INTO recruitment.job_posting_location (job_posting_id, city_id)
                        SELECT j.id, (%(c)s::bigint[])[1 + {h('j.id', 13)}::int %% %(nc)s] FROM recruitment.job_posting j WHERE {h('j.id', 17)} < 300000
                        UNION
                        SELECT j.id, (%(c)s::bigint[])[1 + {h('j.id', 19)}::int %% %(nc)s] FROM recruitment.job_posting j WHERE {h('j.id', 23)} < 150000
                        ON CONFLICT DO NOTHING""", {"c": cities, "nc": len(cities)})
        cur.execute(f"""INSERT INTO recruitment.job_posting_perk (job_posting_id, job_perk_id)
                        SELECT j.id, (%(p)s::bigint[])[1 + {h('j.id * 10 + k', 29)}::int %% %(np)s]
                          FROM recruitment.job_posting j CROSS JOIN generate_series(1, 3) k WHERE {h('j.id', 31)} < 700000
                        ON CONFLICT DO NOTHING""", {"p": perks, "np": len(perks)})
        cur.execute(f"""INSERT INTO recruitment.job_qualification_requirement (job_posting_id, qualification_id, field_of_study, is_mandatory)
                        SELECT j.id, (%(q)s::bigint[])[1 + {h('j.id', 37)}::int %% %(nq)s],
                               CASE WHEN {h('j.id', 41)} < 500000 THEN (ARRAY['Computer Science', 'Business Administration', 'Electronics', 'Commerce', 'Mechanical Engineering'])[1 + {h('j.id', 43)}::int %% 5] END,
                               {h('j.id', 47)} < 750000
                          FROM recruitment.job_posting j WHERE {h('j.id', 53)} < 800000
                        ON CONFLICT DO NOTHING""", {"q": quals, "nq": len(quals)})
        cur.execute(f"""INSERT INTO recruitment.job_recruiter_assignment (job_posting_id, recruiter_user_account_id, assigned_by_user_account_id)
                        SELECT j.id, m.user_account_id, j.created_by_user_account_id
                          FROM recruitment.job_posting j
                          CROSS JOIN LATERAL (SELECT om.user_account_id FROM recruitment.organization_member om
                                               WHERE om.organization_id = j.organization_id AND om.membership_status = 'active'
                                                 AND om.organization_role IN ('recruiter', 'hiring_manager', 'owner', 'admin')
                                               ORDER BY mod(abs(hashint8(om.user_account_id # (j.id + {seed}))::numeric), 100000) LIMIT 2) m
                        ON CONFLICT DO NOTHING""")
        cur.execute(f"""UPDATE profile.candidate_work_experience w SET department_id = (%(d)s::bigint[])[1 + {h('w.id', 59)}::int %% %(nd)s]
                         WHERE {h('w.id', 61)} < 600000""", {"d": depts, "nd": len(depts)})
        # candidates: notice period and pay, optional self-declared gender, last activity, how the course was studied
        cur.execute(f"""INSERT INTO profile.candidate_job_preference (candidate_profile_id, notice_period_days, current_annual_ctc, expected_annual_ctc, ctc_currency_code, is_ctc_visible_to_recruiters)
                        SELECT c.id, (ARRAY[0, 15, 30, 45, 60, 90])[1 + {h('c.id', 67)}::int % 6],
                               CASE WHEN {h('c.id', 71)} < 800000 THEN base END,
                               CASE WHEN {h('c.id', 71)} < 800000 THEN round(base * (1.1 + {h('c.id', 73)} / 3000000.0), 2) END,
                               CASE WHEN {h('c.id', 71)} < 800000 THEN cur END,
                               {h('c.id', 79)} < 350000
                          FROM (SELECT cp.id,
                                       CASE WHEN {h('cp.id', 83)} < 850000 THEN 'INR' ELSE 'USD' END AS cur,
                                       CASE WHEN {h('cp.id', 83)} < 850000 THEN round(300000 + {h('cp.id', 89)} * 3.5, 2) ELSE round(30000 + {h('cp.id', 89)} * 0.12, 2) END AS base
                                  FROM profile.candidate_profile cp WHERE {h('cp.id', 97)} < 750000) c
                        ON CONFLICT DO NOTHING""")
        cur.execute(f"""INSERT INTO profile.candidate_diversity_profile (candidate_profile_id, gender)
                        SELECT cp.id, CASE WHEN {h('cp.id', 101)} < 380000 THEN 'female' WHEN {h('cp.id', 101)} < 930000 THEN 'male' WHEN {h('cp.id', 101)} < 950000 THEN 'non_binary' ELSE 'prefer_not_to_say' END
                          FROM profile.candidate_profile cp WHERE {h('cp.id', 103)} < 350000
                        ON CONFLICT DO NOTHING""")
        cur.execute(f"""UPDATE profile.candidate_profile cp SET last_active_at = %(as_of)s::timestamptz - ({h('cp.id', 107)} / 1000000.0 * 240) * INTERVAL '1 day'
                         WHERE cp.last_active_at IS NULL""", {"as_of": ctx.as_of})
        cur.execute(f"""UPDATE profile.candidate_education e SET study_mode = CASE WHEN {h('e.id', 109)} < 750000 THEN 'full_time' WHEN {h('e.id', 109)} < 900000 THEN 'part_time' ELSE 'distance' END
                         WHERE {h('e.id', 113)} < 800000""")
        # applications: recruiters source some candidates (a first stage before the candidate applies) and most applications have a recruiter
        cur.execute("SELECT count(*) FROM recruitment.candidate_application"); n_apps = cur.fetchone()[0]
        cur.execute("SELECT array_agg(id ORDER BY id) FROM (SELECT id FROM profile.candidate_profile WHERE profile_status = 'active' AND visibility <> 'private' ORDER BY id LIMIT 200000) x"); cands = cur.fetchone()[0]
        cur.execute("SELECT array_agg(id ORDER BY id) FROM (SELECT j.id FROM recruitment.job_posting j WHERE j.job_status = 'published' AND EXISTS (SELECT 1 FROM recruitment.job_recruiter_assignment r WHERE r.job_posting_id = j.id) ORDER BY j.id LIMIT 100000) x"); jobs = cur.fetchone()[0]
        if cands and jobs:
            cur.execute(f"""INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, application_source, applied_at,
                                                                           assigned_recruiter_user_account_id, created_by_user_account_id, updated_by_user_account_id)
                            SELECT x.c, x.j, 'sourced', 'recruiter_sourced', %(as_of)s::timestamptz - ({h('x.g', 127)} / 1000000.0 * 60) * INTERVAL '1 day', r.rid, r.rid, r.rid
                              FROM (SELECT g, (%(c)s::bigint[])[1 + {h('g', 131)}::int %% %(nc)s] AS c, (%(j)s::bigint[])[1 + {h('g', 137)}::int %% %(nj)s] AS j
                                      FROM generate_series(1, %(n)s) g) x
                              CROSS JOIN LATERAL (SELECT recruiter_user_account_id AS rid FROM recruitment.job_recruiter_assignment a WHERE a.job_posting_id = x.j ORDER BY a.id LIMIT 1) r
                            ON CONFLICT DO NOTHING""", {"as_of": ctx.as_of, "c": cands, "nc": len(cands), "j": jobs, "nj": len(jobs), "n": max(20, int(n_apps * 0.06))})
            cur.execute(f"""UPDATE recruitment.candidate_application SET application_status = 'shortlisted', updated_by_user_account_id = assigned_recruiter_user_account_id
                             WHERE application_status = 'sourced' AND {h('id', 139)} < 350000""")
        cur.execute("ALTER TABLE recruitment.candidate_application DISABLE TRIGGER trg_candidate_application_recruiter")      # the assignment table was already validated
        cur.execute(f"""UPDATE recruitment.candidate_application a SET assigned_recruiter_user_account_id = r.rid
                          FROM (SELECT a2.id, (SELECT recruiter_user_account_id FROM recruitment.job_recruiter_assignment x WHERE x.job_posting_id = a2.job_posting_id
                                                ORDER BY mod(abs(hashint8(x.id # a2.id)::numeric), 1000) LIMIT 1) AS rid
                                  FROM recruitment.candidate_application a2 WHERE a2.assigned_recruiter_user_account_id IS NULL AND {h('a2.id', 149)} < 700000) r
                         WHERE a.id = r.id AND r.rid IS NOT NULL""")
        cur.execute("ALTER TABLE recruitment.candidate_application ENABLE TRIGGER trg_candidate_application_recruiter")
        # a few saved and recent recruiter searches
        cur.execute(f"""INSERT INTO profile.recruiter_search (organization_id, user_account_id, name, criteria_json, result_count, is_alert_enabled, last_run_at)
                        SELECT r.organization_id, r.recruiter_user_account_id, CASE WHEN g %% 3 = 0 THEN 'Search ' || g END,
                               jsonb_build_object('keywords', (ARRAY['Java', 'Python developer', 'UX designer', 'DevOps, Kubernetes', 'Accountant'])[1 + g %% 5], 'min_experience', 2, 'max_experience', 5),
                               (g * 7) %% 300, (g %% 6 = 0), %(as_of)s::timestamptz - (g %% 40) * INTERVAL '1 day'
                          FROM generate_series(1, 60) g
                          CROSS JOIN LATERAL (SELECT j.organization_id, a.recruiter_user_account_id FROM recruitment.job_recruiter_assignment a JOIN recruitment.job_posting j ON j.id = a.job_posting_id
                                               ORDER BY a.id OFFSET g * 3 LIMIT 1) r
                        ON CONFLICT DO NOTHING""", {"as_of": ctx.as_of})
    conn.commit()


def main():
    parser = argparse.ArgumentParser(description="Talentra synthetic data generator")
    parser.add_argument("--scale", choices=sorted(SCALE_CONFIGS), default="dev", help="dev | medium | laptop (see module docstring)")
    parser.add_argument("--seed", type=int, default=42, help="random seed; the same seed gives the same shape (default 42)")
    parser.add_argument("--append", action="store_true", help="add to a database that already holds candidates (default: refuse)")
    args = parser.parse_args()
    config = SCALE_CONFIGS[args.scale]
    ctx = Ctx(args.seed, config)

    print("=" * 64)
    print(f" Talentra synthetic data (scale: {args.scale}, seed: {args.seed})")
    print(f" Candidates: {config['candidates']:,} | Jobs: {config['jobs']:,} | Applications: {config['applications']:,}")
    print("=" * 64)

    conn = get_connection()
    try:
        if already_seeded(conn) and not args.append:
            print("[!] This database already holds candidate data. Seeding it again would add a second copy of everything.\n"
                  "    Re-create the database and re-run the migrations, or pass --append if a second copy is what you want.",
                  file=sys.stderr)
            sys.exit(2)
        t_start = time.time()
        set_audit_triggers(conn, False)
        with conn.cursor() as _c:
            _c.execute("SET talentra.skip_search_refresh = 'on'")       # search documents are rebuilt in bulk below
        conn.commit()
        seed_master_reference_geo(conn)
        seed_candidates(conn, ctx)
        orgs = seed_employers(conn, ctx)
        live_jobs = seed_jobs(conn, ctx, orgs)
        seed_applications(conn, ctx, live_jobs)
        seed_gig_marketplace(conn, ctx, orgs)
        seed_commercial(conn, ctx, orgs)
        seed_sourcing(conn, ctx, orgs)
        seed_messaging_and_support(conn, ctx, orgs)
        seed_profile_depth(conn, ctx)
        seed_engagement(conn, ctx, orgs)
        seed_recruiter_portal(conn, ctx)
        with conn.cursor() as _c:
            _c.execute("SET talentra.skip_search_refresh = 'off'")
            _c.execute("SELECT profile.rebuild_candidate_search_documents()")
        conn.commit()
        set_audit_triggers(conn, True)      # the audited actions that follow are real ones
        seed_structure(conn, ctx, orgs)
        load_analytics(conn)

        print("[*] Running ANALYZE...")
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("ANALYZE;")
        print(f"\n[+] Seeding completed in {time.time() - t_start:.2f} seconds.")
    finally:
        try:
            conn.rollback()
            set_audit_triggers(conn, True)
        finally:
            conn.close()


if __name__ == "__main__":
    main()
