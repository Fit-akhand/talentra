#!/usr/bin/env python3
"""
Talentra Synthetic Data Generator (Milestone 19: B60–B64)
Engine: PostgreSQL 17
Generates realistic, constraint-compliant synthetic data across all 10 schemas.
Supports configurable scales: dev, medium, laptop (1M candidates, 100K jobs, 5M applications).
Adheres strictly to the 10 Rule Groups: E.164 phones, RFC emails, UTC timestamptz,
financial balance reconciliations, and non-overlapping temporal constraints.
"""

import argparse
import io
import math
import os
import random
import sys
import time
from datetime import datetime, timedelta, timezone
import psycopg2
from psycopg2.extras import execute_values

DB_HOST = os.getenv("POSTGRES_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
DB_NAME = os.getenv("POSTGRES_DB", "talentra")
DB_USER = os.getenv("POSTGRES_USER", "talentra_admin")
DB_PASS = os.getenv("POSTGRES_PASSWORD", "354vctrho9t769874t8B*^&$%&**tf2eej2rh")

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

SCALE_CONFIGS = {
    "dev": {
        "candidates": 500,
        "organizations": 20,
        "jobs": 100,
        "applications": 2000,
        "gig_workers": 100,
        "gig_requests": 50,
        "batch_size": 500
    },
    "medium": {
        "candidates": 10000,
        "organizations": 200,
        "jobs": 1000,
        "applications": 50000,
        "gig_workers": 2000,
        "gig_requests": 500,
        "batch_size": 2000
    },
    "laptop": {
        "candidates": 1000000,
        "organizations": 10000,
        "jobs": 100000,
        "applications": 5000000,
        "gig_workers": 100000,
        "gig_requests": 50000,
        "batch_size": 10000
    }
}

def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )

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

def seed_translations(conn):
    print("[*] Seeding UI multilingual translations...")
    cur = conn.cursor()
    translations = [
        ('btn.apply_job', 'en', 'Apply Now', True),
        ('btn.apply_job', 'es', 'Postularse Ahora', True),
        ('btn.apply_job', 'de', 'Jetzt bewerben', True),
        ('btn.apply_job', 'hi', 'अभी आवेदन करें', True),
        ('btn.apply_job', 'fr', 'Postuler maintenant', True),
        ('nav.job_search', 'en', 'Find Jobs', True),
        ('nav.job_search', 'es', 'Buscar Empleos', True),
        ('nav.job_search', 'de', 'Jobs finden', True),
        ('nav.job_search', 'hi', 'नौकरियां खोजें', True),
        ('label.welcome_back', 'en', 'Welcome Back', True),
        ('label.welcome_back', 'es', 'Bienvenido de nuevo', True),
        ('label.welcome_back', 'hi', 'वापसी पर स्वागत है', True),
        ('status.applied', 'en', 'Application Submitted', True),
        ('status.shortlisted', 'en', 'Shortlisted', True),
        ('status.interviewed', 'en', 'Interview Scheduled', True),
        ('status.offered', 'en', 'Offer Extended', True),
        ('status.joined', 'en', 'Successfully Hired', True)
    ]
    execute_values(
        cur,
        "INSERT INTO messaging.ui_translation (string_key, language_code, translated_text, is_verified) VALUES %s ON CONFLICT (string_key, language_code) DO NOTHING;",
        translations
    )
    conn.commit()
    cur.close()

def seed_users_and_candidates(conn, num_candidates, batch_size):
    print(f"[*] Seeding {num_candidates:,} candidate accounts, profiles, skills, and locations...")
    cur = conn.cursor()
    
    # Fetch reference IDs
    cur.execute("SELECT id FROM master.city;")
    city_ids = [r[0] for r in cur.fetchall()] or [1]
    
    cur.execute("SELECT id, normalized_name FROM master.skill;")
    skill_rows = cur.fetchall()
    skill_ids = [r[0] for r in skill_rows] or [1]
    key_skills = [r[0] for r in skill_rows if r[1] in ('postgresql', 'python', 'docker', 'react', 'java')] or skill_ids[:3]

    cur.execute("SELECT id FROM master.qualification;")
    qual_ids = [r[0] for r in cur.fetchall()] or [1]

    created = 0
    t0 = time.time()

    while created < num_candidates:
        current_batch = min(batch_size, num_candidates - created)
        
        # 1. Bulk insert user accounts
        user_buffer = io.StringIO()
        for i in range(current_batch):
            idx = created + i + 1
            email = f"candidate_{idx}_{random.randint(10000, 99999)}@example.com".lower()
            phone = f"+9198{random.randint(10000000, 99999999)}"
            pwd_hash = "$argon2id$v=19$m=65536,t=3,p=4$synthetic_hash_value"
            user_buffer.write(f"{email}\t{phone}\tIN\tactive\ten\t{pwd_hash}\n")
        
        user_buffer.seek(0)
        cur.copy_expert(
            "COPY core.user_account (email, phone_e164, phone_country_code, account_status, preferred_language, password_hash) FROM STDIN",
            user_buffer
        )
        
        # Retrieve generated user IDs for this batch
        cur.execute("SELECT id FROM core.user_account ORDER BY id DESC LIMIT %s;", (current_batch,))
        batch_user_ids = sorted([r[0] for r in cur.fetchall()])

        # 2. Bulk insert candidate profiles
        profile_buffer = io.StringIO()
        for uid in batch_user_ids:
            fn = random.choice(FIRST_NAMES)
            ln = random.choice(LAST_NAMES)
            headline = f"{random.choice(TITLES)} with {random.randint(2, 15)} yrs experience"
            exp = round(random.uniform(1.0, 18.0), 1)
            visibility = random.choice(["recruiters", "recruiters", "public", "private"])
            profile_buffer.write(f"{uid}\t{headline}\tExperienced professional {fn} {ln}\t{exp}\tactive\t{visibility}\n")
        
        profile_buffer.seek(0)
        cur.copy_expert(
            "COPY profile.candidate_profile (user_account_id, headline, professional_summary, total_experience_years, profile_status, visibility) FROM STDIN",
            profile_buffer
        )

        cur.execute("SELECT id FROM profile.candidate_profile ORDER BY id DESC LIMIT %s;", (current_batch,))
        batch_cand_ids = sorted([r[0] for r in cur.fetchall()])

        # 3. Bulk insert candidate locations (current city)
        loc_buffer = io.StringIO()
        for cid in batch_cand_ids:
            city_id = random.choice(city_ids)
            loc_buffer.write(f"{cid}\t{city_id}\tcurrent\n")
        
        loc_buffer.seek(0)
        cur.copy_expert(
            "COPY profile.candidate_location (candidate_profile_id, city_id, location_type) FROM STDIN",
            loc_buffer
        )

        # 4. Bulk insert candidate skills
        skill_buffer = io.StringIO()
        for cid in batch_cand_ids:
            c_skills = set(random.sample(skill_ids, min(3, len(skill_ids))))
            if random.random() < 0.7:
                c_skills.add(random.choice(key_skills))
            
            is_prim = True
            for sid in c_skills:
                prof = random.choice(["intermediate", "expert", "advanced", "beginner"])
                exp_yrs = round(random.uniform(1.0, 10.0), 1)
                prim_str = 't' if is_prim else 'f'
                skill_buffer.write(f"{cid}\t{sid}\t{prof}\t{exp_yrs}\t{prim_str}\n")
                is_prim = False

        skill_buffer.seek(0)
        cur.copy_expert(
            "COPY profile.candidate_skill (candidate_profile_id, skill_id, proficiency_level, experience_years, is_primary) FROM STDIN",
            skill_buffer
        )

        created += current_batch
        if created % 25000 == 0 or created == num_candidates:
            elapsed = time.time() - t0
            rate = created / elapsed if elapsed > 0 else 0
            print(f"    -> {created:,}/{num_candidates:,} candidates created ({rate:,.0f} rows/sec)")

    conn.commit()
    cur.close()
    print(f"[+] Candidate profiles and skills seeded successfully in {time.time() - t0:.2f}s")

def seed_organizations_and_jobs(conn, num_orgs, num_jobs, batch_size):
    print(f"[*] Seeding {num_orgs:,} organizations and {num_jobs:,} job postings...")
    cur = conn.cursor()

    cur.execute("SELECT id FROM core.user_account LIMIT 1;")
    creator_id = cur.fetchone()[0]

    cur.execute("SELECT id FROM master.employment_type;")
    emp_ids = [r[0] for r in cur.fetchall()] or [1]

    cur.execute("SELECT id FROM master.work_type;")
    work_ids = [r[0] for r in cur.fetchall()] or [1]

    cur.execute("SELECT id FROM master.city;")
    city_ids = [r[0] for r in cur.fetchall()] or [1]

    cur.execute("SELECT id FROM master.skill;")
    skill_ids = [r[0] for r in cur.fetchall()] or [1]

    # Insert Organizations
    t0 = time.time()
    org_buffer = io.StringIO()
    for i in range(num_orgs):
        idx = i + 1
        name = f"Enterprise Tech Group {idx}"
        slug = f"enterprise-tech-group-{idx}-{random.randint(1000, 9999)}"
        org_buffer.write(f"{name}\t{slug}\temployer\tactive\t{creator_id}\n")
    
    org_buffer.seek(0)
    cur.copy_expert(
        "COPY recruitment.organization (name, slug, organization_type, organization_status, created_by_user_account_id) FROM STDIN",
        org_buffer
    )
    conn.commit()

    cur.execute("SELECT id FROM recruitment.organization ORDER BY id DESC LIMIT %s;", (num_orgs,))
    org_ids = [r[0] for r in cur.fetchall()]

    # Insert Organization Locations
    org_loc_buffer = io.StringIO()
    for oid in org_ids:
        cid = random.choice(city_ids)
        org_loc_buffer.write(f"{oid}\t{cid}\tCorporate HQ\tInnovation Way Suite 100\t94105\tt\n")
    org_loc_buffer.seek(0)
    cur.copy_expert(
        "COPY recruitment.organization_location (organization_id, city_id, location_name, address_line1, postal_code, is_headquarters) FROM STDIN",
        org_loc_buffer
    )
    conn.commit()

    # Insert Jobs
    created_jobs = 0
    now_str = datetime.now(timezone.utc).isoformat()
    while created_jobs < num_jobs:
        current_batch = min(batch_size, num_jobs - created_jobs)
        job_buffer = io.StringIO()
        for i in range(current_batch):
            oid = random.choice(org_ids)
            title = random.choice(TITLES)
            desc = f"Key opportunity for {title} leading high-scale distributed systems."
            eid = random.choice(emp_ids)
            wid = random.choice(work_ids)
            cid = random.choice(city_ids)
            s_min = random.choice([80000, 100000, 120000, 150000])
            s_max = s_min + random.choice([20000, 40000, 60000])
            job_buffer.write(
                f"{oid}\t{creator_id}\t{eid}\t{wid}\t{cid}\t{title}\t{desc}\tpublished\tUSD\t{s_min}\t{s_max}\tyear\t{now_str}\n"
            )

        job_buffer.seek(0)
        cur.copy_expert(
            "COPY recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, city_id, title, description, job_status, currency_code, salary_min, salary_max, salary_period, published_at) FROM STDIN",
            job_buffer
        )

        # Retrieve inserted job IDs to add required skills
        cur.execute("SELECT id FROM recruitment.job_posting ORDER BY id DESC LIMIT %s;", (current_batch,))
        batch_job_ids = [r[0] for r in cur.fetchall()]

        skill_req_buffer = io.StringIO()
        for jid in batch_job_ids:
            for sid in random.sample(skill_ids, min(3, len(skill_ids))):
                skill_req_buffer.write(f"{jid}\t{sid}\tt\tintermediate\t2.0\n")
        
        skill_req_buffer.seek(0)
        cur.copy_expert(
            "COPY recruitment.job_skill_requirement (job_posting_id, skill_id, is_required, minimum_proficiency_level, minimum_experience_years) FROM STDIN",
            skill_req_buffer
        )

        created_jobs += current_batch

    conn.commit()
    cur.close()
    print(f"[+] Organizations & Jobs seeded successfully in {time.time() - t0:.2f}s")

def seed_applications(conn, num_apps, batch_size):
    print(f"[*] Seeding {num_apps:,} candidate applications across operational & partitioned tables...")
    cur = conn.cursor()

    cur.execute("SELECT id FROM profile.candidate_profile;")
    cand_ids = [r[0] for r in cur.fetchall()]

    cur.execute("SELECT id FROM recruitment.job_posting;")
    job_ids = [r[0] for r in cur.fetchall()]

    cur.execute("SELECT id FROM core.user_account LIMIT 1;")
    user_id = cur.fetchone()[0]

    statuses = ["applied", "shortlisted", "interviewed", "offered", "joined", "rejected"]
    status_weights = [0.55, 0.20, 0.12, 0.05, 0.03, 0.05]

    created = 0
    t0 = time.time()
    seen_pairs = set()

    # Generate applications
    cur.execute("""
        CREATE TEMP TABLE IF NOT EXISTS tmp_candidate_app (
            candidate_profile_id BIGINT,
            job_posting_id BIGINT,
            application_status VARCHAR(20),
            application_source VARCHAR(30),
            created_by_user_account_id BIGINT,
            updated_by_user_account_id BIGINT
        ) ON COMMIT DELETE ROWS;
    """)

    while created < num_apps:
        current_batch = min(batch_size, num_apps - created)
        app_buffer = io.StringIO()
        batch_rows = 0

        for _ in range(current_batch * 2):
            if batch_rows >= current_batch:
                break
            cid = random.choice(cand_ids)
            jid = random.choice(job_ids)
            pair = (cid, jid)
            if pair in seen_pairs:
                continue
            seen_pairs.add(pair)
            status = random.choices(statuses, weights=status_weights, k=1)[0]
            app_buffer.write(f"{cid}\t{jid}\t{status}\tdirect\t{user_id}\t{user_id}\n")
            batch_rows += 1

        app_buffer.seek(0)
        cur.copy_expert(
            "COPY tmp_candidate_app (candidate_profile_id, job_posting_id, application_status, application_source, created_by_user_account_id, updated_by_user_account_id) FROM STDIN",
            app_buffer
        )
        cur.execute("""
            INSERT INTO recruitment.candidate_application (
                candidate_profile_id, job_posting_id, application_status, application_source,
                created_by_user_account_id, updated_by_user_account_id
            )
            SELECT candidate_profile_id, job_posting_id, application_status, application_source,
                   created_by_user_account_id, updated_by_user_account_id
            FROM tmp_candidate_app
            ON CONFLICT (candidate_profile_id, job_posting_id) DO NOTHING;
        """)
        cur.execute("TRUNCATE TABLE tmp_candidate_app;")
        created += batch_rows

        if len(seen_pairs) > 200000:
            seen_pairs.clear()

        if created % 50000 == 0 or created >= num_apps:
            elapsed = time.time() - t0
            rate = created / elapsed if elapsed > 0 else 0
            print(f"    -> {created:,}/{num_apps:,} applications created ({rate:,.0f} rows/sec)")

    conn.commit()

    # Also seed range partitioned table recruitment.candidate_application_partitioned
    print("[*] Seeding partitioned applications table (recruitment.candidate_application_partitioned)...")
    cur.execute("SELECT COUNT(*) FROM recruitment.candidate_application_partitioned;")
    if cur.fetchone()[0] == 0:
        cur.execute("""
            INSERT INTO recruitment.candidate_application_partitioned (
                candidate_profile_id, job_posting_id, application_status, application_source,
                applied_at, created_by_user_account_id, updated_by_user_account_id
            )
            SELECT
                candidate_profile_id, job_posting_id, application_status, application_source,
                applied_at, created_by_user_account_id, updated_by_user_account_id
            FROM recruitment.candidate_application
            LIMIT 50000;
        """)
        conn.commit()

    cur.close()
    print(f"[+] Applications seeded successfully in {time.time() - t0:.2f}s")

def seed_gig_marketplace(conn, num_workers, num_requests):
    print(f"[*] Seeding {num_workers:,} gig worker profiles, services, availability, and projects...")
    cur = conn.cursor()

    cur.execute("""
        SELECT u.id FROM core.user_account u
        LEFT JOIN gig.gig_worker_profile gwp ON u.id = gwp.user_account_id
        WHERE gwp.id IS NULL
        ORDER BY u.id ASC LIMIT %s;
    """, (num_workers,))
    user_ids = [r[0] for r in cur.fetchall()]

    cur.execute("SELECT id FROM recruitment.organization LIMIT 10;")
    org_ids = [r[0] for r in cur.fetchall()] or [1]

    cur.execute("SELECT id FROM master.skill WHERE normalized_name IN ('python', 'postgresql', 'docker', 'react');")
    key_skills = [r[0] for r in cur.fetchall()]
    if not key_skills:
        cur.execute("SELECT id FROM master.skill LIMIT 4;")
        key_skills = [r[0] for r in cur.fetchall()]

    # Gig Worker Profiles
    if user_ids:
        worker_buffer = io.StringIO()
        for uid in user_ids:
            headline = f"Contractor: {random.choice(TITLES)}"
            hr = round(random.uniform(40.0, 150.0), 2)
            dr = hr * 8
            rating = round(random.uniform(4.0, 5.0), 2)
            worker_buffer.write(f"{uid}\t{headline}\t{hr}\t{dr}\tUSD\tt\t{rating}\tverified\n")
        
        worker_buffer.seek(0)
        cur.copy_expert(
            "COPY gig.gig_worker_profile (user_account_id, headline, hourly_rate, daily_rate, currency_code, is_available, average_rating, verification_status) FROM STDIN",
            worker_buffer
        )
        conn.commit()

    cur.execute("SELECT id FROM gig.gig_worker_profile ORDER BY id DESC LIMIT %s;", (num_workers,))
    worker_ids = [r[0] for r in cur.fetchall()]

    # Gig Services (Skills)
    srv_buffer = io.StringIO()
    for wid in worker_ids:
        for sid in key_skills[:2]:
            rate = round(random.uniform(50.0, 120.0), 2)
            srv_buffer.write(f"{wid}\t{sid}\tSenior Consulting Specialist\t{rate}\n")
    srv_buffer.seek(0)
    cur.copy_expert(
        "COPY gig.gig_worker_service (gig_worker_profile_id, skill_id, custom_title, rate_override) FROM STDIN",
        srv_buffer
    )
    conn.commit()

    # Gig Worker Availability (covering project window 2026-11-01 to 2026-11-30)
    avail_buffer = io.StringIO()
    for wid in worker_ids:
        avail_buffer.write(f"{wid}\t2026-10-01\t2026-12-31\t8.0\n")
    avail_buffer.seek(0)
    cur.copy_expert(
        "COPY gig.gig_worker_availability (gig_worker_profile_id, available_from, available_to, daily_available_hours) FROM STDIN",
        avail_buffer
    )
    conn.commit()

    # Gig Requests
    req_buffer = io.StringIO()
    for i in range(num_requests):
        oid = random.choice(org_ids)
        title = f"Gig Project: {random.choice(TITLES)} Module Deliverable"
        budget = round(random.uniform(1000.0, 10000.0), 2)
        req_buffer.write(f"{oid}\t{user_ids[0]}\t{title}\tHigh-impact deliverables\tCode and docs\tfixed\t{budget}\tUSD\t2026-11-01\t2026-11-30\topen\n")

    req_buffer.seek(0)
    cur.copy_expert(
        "COPY gig.gig_request (organization_id, created_by_user_account_id, title, description, deliverables, pricing_type, budget_amount, currency_code, start_date, end_date, request_status) FROM STDIN",
        req_buffer
    )
    conn.commit()

    # Gig Applications & Assignments
    cur.execute("SELECT id FROM gig.gig_request ORDER BY id DESC LIMIT %s;", (min(num_requests, 100),))
    req_ids = [r[0] for r in cur.fetchall()]
    assigned_workers = worker_ids[:len(req_ids)]

    now_ts = datetime.now(timezone.utc).isoformat()
    app_buffer = io.StringIO()
    for req_id, wid in zip(req_ids, assigned_workers):
        amt = round(random.uniform(2000.0, 5000.0), 2)
        app_buffer.write(f"{req_id}\t{wid}\t{amt}\tUSD\t10\tAccepted project proposal\taccepted\t{now_ts}\n")
    
    app_buffer.seek(0)
    cur.copy_expert(
        "COPY gig.gig_application (gig_request_id, gig_worker_profile_id, bid_amount, currency_code, proposed_duration_days, pitch, application_status, decided_at) FROM STDIN",
        app_buffer
    )
    conn.commit()

    cur.execute("SELECT id, gig_request_id, gig_worker_profile_id, bid_amount FROM gig.gig_application ORDER BY id DESC LIMIT %s;", (len(assigned_workers),))
    app_rows = cur.fetchall()

    assign_buffer = io.StringIO()
    for row in app_rows:
        app_id, req_id, wid, amt = row
        handoff_ref = f"handoff_ref_{app_id}_{random.randint(1000, 9999)}"
        assign_buffer.write(f"{req_id}\t{app_id}\t{wid}\t2026-11-16\t2026-11-25\t{amt}\tUSD\tactive\t{handoff_ref}\n")
    
    assign_buffer.seek(0)
    cur.copy_expert(
        "COPY gig.gig_assignment (gig_request_id, gig_application_id, gig_worker_profile_id, assigned_start_date, assigned_end_date, agreed_amount, currency_code, assignment_status, external_handoff_ref) FROM STDIN",
        assign_buffer
    )
    conn.commit()

    cur.execute("SELECT id FROM gig.gig_assignment ORDER BY id DESC LIMIT %s;", (len(assigned_workers),))
    assign_ids = [r[0] for r in cur.fetchall()]

    earn_buffer = io.StringIO()
    rating_buffer = io.StringIO()
    for aid in assign_ids:
        total_e = round(random.uniform(1500.0, 4500.0), 2)
        earn_buffer.write(f"{aid}\t{total_e}\t{total_e}\t{total_e}\tUSD\tsync_hash_{aid}\n")
        score = round(random.uniform(4.0, 5.0), 2)
        rating_buffer.write(f"{aid}\t{user_ids[0]}\t{score}\tOutstanding engineering output and speed.\n")

    earn_buffer.seek(0)
    cur.copy_expert(
        "COPY gig.gig_external_earnings (gig_assignment_id, estimated_earnings, total_earnings, projected_earnings, currency_code, external_sync_hash) FROM STDIN",
        earn_buffer
    )

    rating_buffer.seek(0)
    cur.copy_expert(
        "COPY gig.gig_rating (gig_assignment_id, rater_user_account_id, rating_score, review_text) FROM STDIN",
        rating_buffer
    )
    conn.commit()
    cur.close()
    print("[+] Gig marketplace data seeded successfully")

def seed_commercial_and_sessions(conn):
    print("[*] Seeding commercial licences, wallets, reconciled ledgers, and sessions...")
    cur = conn.cursor()

    cur.execute("SELECT id FROM core.user_account LIMIT 5;")
    users = [r[0] for r in cur.fetchall()]
    u1 = users[0]

    cur.execute("SELECT id FROM recruitment.organization LIMIT 5;")
    orgs = [r[0] for r in cur.fetchall()]
    o1 = orgs[0]

    # Licences
    cur.execute("""
        INSERT INTO commercial.subscription_licence (
            organization_id, licence_key, licence_name, max_users, max_devices_per_user,
            valid_from, valid_to, licence_status
        ) VALUES (
            %s, 'LIC-CORP-TEST-KEY-001', 'Enterprise Talent Suite', 50, 3,
            CURRENT_TIMESTAMP - INTERVAL '30 days', CURRENT_TIMESTAMP + INTERVAL '335 days', 'active'
        ) ON CONFLICT (licence_key) DO NOTHING
        RETURNING id;
    """, (o1,))
    lic_row = cur.fetchone()
    if lic_row:
        lic_id = lic_row[0]
    else:
        cur.execute("SELECT id FROM commercial.subscription_licence WHERE licence_key = 'LIC-CORP-TEST-KEY-001';")
        lic_id = cur.fetchone()[0]

    cur.execute("""
        INSERT INTO commercial.licence_seat_allocation (subscription_licence_id, user_account_id, allocated_by_user_account_id)
        VALUES (%s, %s, %s)
        ON CONFLICT DO NOTHING;
    """, (lic_id, u1, u1))

    # User active sessions for device limit verification
    cur.execute("""
        INSERT INTO core.user_session (user_account_id, device_identifier, session_token_hash)
        VALUES
            (%s, 'dev_macbook_pro', 'sess_hash_alpha_dev_1'),
            (%s, 'dev_iphone_15', 'sess_hash_beta_dev_2')
        ON CONFLICT (session_token_hash) DO NOTHING;
    """, (u1, u1))

    # Wallets & Append-Only Ledger
    cur.execute("""
        INSERT INTO commercial.wallet (organization_id, balance, currency_code)
        VALUES (%s, 1500.00, 'USD')
        ON CONFLICT (organization_id, currency_code) DO UPDATE SET balance = 1500.00
        RETURNING id;
    """, (o1,))
    wallet_id = cur.fetchone()[0]

    cur.execute("SELECT COUNT(*) FROM commercial.wallet_ledger WHERE wallet_id = %s;", (wallet_id,))
    if cur.fetchone()[0] == 0:
        cur.execute("""
            INSERT INTO commercial.wallet_ledger (
                wallet_id, entry_type, amount, currency_code, balance_after,
                reference_type, notes, created_by_user_account_id
            )
            VALUES
                (%s, 'credit', 2000.00, 'USD', 2000.00, 'recharge', 'Initial corporate credit deposit', %s),
                (%s, 'debit', 500.00, 'USD', 1500.00, 'profile_download', 'Bulk candidate profile download package', %s);
        """, (wallet_id, u1, wallet_id, u1))

    # Candidate profile download audit history
    cur.execute("SELECT id FROM profile.candidate_profile LIMIT 5;")
    cands = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT id FROM commercial.wallet_ledger WHERE wallet_id = %s LIMIT 1;", (wallet_id,))
    wl_id = cur.fetchone()[0]

    for cid in cands:
        cur.execute("""
            INSERT INTO commercial.candidate_profile_download_history (
                organization_id, downloader_user_account_id, candidate_profile_id,
                credit_deduction_amount, currency_code, wallet_ledger_id
            ) VALUES (%s, %s, %s, 10.00, 'USD', %s)
            ON CONFLICT DO NOTHING;
        """, (o1, u1, cid, wl_id))

    conn.commit()
    cur.close()
    print("[+] Commercial & Sessions data seeded successfully")

def seed_sourcing_blocks_and_messaging(conn):
    print("[*] Seeding user blocks, notifications, and analytics events...")
    cur = conn.cursor()

    cur.execute("SELECT id FROM core.user_account LIMIT 10;")
    users = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT id FROM recruitment.organization LIMIT 5;")
    orgs = [r[0] for r in cur.fetchall()]

    # User Blocks (separate rows to satisfy XOR constraint)
    cur.execute("""
        INSERT INTO core.user_block (blocker_user_account_id, blocked_user_account_id, block_reason)
        VALUES (%s, %s, 'Unsolicited recruiter message')
        ON CONFLICT DO NOTHING;
    """, (users[2], users[1]))

    cur.execute("""
        INSERT INTO core.user_block (blocker_user_account_id, blocked_organization_id, block_reason)
        VALUES (%s, %s, 'Unsolicited corporate outreach')
        ON CONFLICT DO NOTHING;
    """, (users[2], orgs[0]))

    # Notifications
    notif_buffer = io.StringIO()
    for i in range(50):
        notif_buffer.write(f"{users[0]}\temail\tNew Job Alert: Cloud Architect\tOpportunity matching your skills is live.\tsent\t2026-10-17 10:00:00+00\n")
    notif_buffer.seek(0)
    cur.copy_expert(
        "COPY messaging.notification_delivery (recipient_user_account_id, channel, subject, body_snippet, delivery_status, sent_at) FROM STDIN",
        notif_buffer
    )

    # Analytics Dimensions
    cur.execute("""
        INSERT INTO analytics.dim_organization (organization_id, organization_name, organization_type, country_code, industry_name, valid_from)
        SELECT id, name, organization_type, 'USA', 'Technology & Software', CURRENT_TIMESTAMP
        FROM recruitment.organization
        ON CONFLICT DO NOTHING;
    """)

    cur.execute("""
        INSERT INTO analytics.dim_candidate (candidate_profile_id, current_city_name, total_experience_years, profile_completeness_percentage, valid_from)
        SELECT id, 'San Francisco', total_experience_years, 85.00, CURRENT_TIMESTAMP
        FROM profile.candidate_profile
        LIMIT 500
        ON CONFLICT DO NOTHING;
    """)

    cur.execute("""
        INSERT INTO analytics.dim_job_posting (job_posting_id, organization_key, job_title, industry_name, work_type_code)
        SELECT jp.id, dorg.organization_key, jp.title, 'Technology & Software', wt.code
        FROM recruitment.job_posting jp
        JOIN master.work_type wt ON jp.work_type_id = wt.id
        JOIN analytics.dim_organization dorg ON jp.organization_id = dorg.organization_id
        ON CONFLICT (job_posting_id) DO NOTHING;
    """)

    cur.execute("""
        INSERT INTO analytics.fact_application_event (
            date_key, job_posting_key, candidate_application_id,
            candidate_key, organization_key, previous_status, new_status, status_cycle_time_hours
        )
        SELECT
            (EXTRACT(YEAR FROM ca.applied_at)::INT * 10000 + EXTRACT(MONTH FROM ca.applied_at)::INT * 100 + EXTRACT(DAY FROM ca.applied_at)::INT),
            djp.job_posting_key,
            ca.id,
            dc.candidate_key,
            djp.organization_key,
            'applied',
            ca.application_status,
            48.5
        FROM recruitment.candidate_application ca
        JOIN analytics.dim_job_posting djp ON ca.job_posting_id = djp.job_posting_id
        JOIN analytics.dim_candidate dc ON ca.candidate_profile_id = dc.candidate_profile_id
        LIMIT 1000
        ON CONFLICT DO NOTHING;
    """)

    # Refresh materialized KPI views
    cur.execute("REFRESH MATERIALIZED VIEW analytics.mv_hiring_funnel_summary;")
    cur.execute("REFRESH MATERIALIZED VIEW analytics.mv_gig_fulfilment_summary;")

    conn.commit()
    cur.close()
    print("[+] Sourcing, notifications, and analytics facts seeded successfully")

def main():
    parser = argparse.ArgumentParser(description="Talentra Synthetic Data Generator")
    parser.add_argument(
        "--scale",
        choices=["dev", "medium", "laptop"],
        default="dev",
        help="Scale preset (dev: ~2K apps, medium: ~50K apps, laptop: 1M candidates / 5M apps)"
    )
    args = parser.parse_args()
    config = SCALE_CONFIGS[args.scale]

    print(f"================================================================")
    print(f" Talentra Synthetic Data Generator (Scale: {args.scale.upper()})")
    print(f" Candidates: {config['candidates']:,} | Jobs: {config['jobs']:,} | Applications: {config['applications']:,}")
    print(f"================================================================")

    t_start = time.time()
    conn = get_connection()

    try:
        seed_master_reference_geo(conn)
        seed_translations(conn)
        seed_users_and_candidates(conn, config["candidates"], config["batch_size"])
        seed_organizations_and_jobs(conn, config["organizations"], config["jobs"], config["batch_size"])
        seed_applications(conn, config["applications"], config["batch_size"])
        seed_gig_marketplace(conn, config["gig_workers"], config["gig_requests"])
        seed_commercial_and_sessions(conn)
        seed_sourcing_blocks_and_messaging(conn)
        
        # Analyze tables to update PostgreSQL optimizer statistics
        print("[*] Running ANALYZE on operational & dimensional tables...")
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("ANALYZE core.user_account;")
            cur.execute("ANALYZE profile.candidate_profile;")
            cur.execute("ANALYZE profile.candidate_skill;")
            cur.execute("ANALYZE profile.candidate_location;")
            cur.execute("ANALYZE recruitment.organization;")
            cur.execute("ANALYZE recruitment.job_posting;")
            cur.execute("ANALYZE recruitment.candidate_application;")
            cur.execute("ANALYZE recruitment.candidate_application_partitioned;")
            cur.execute("ANALYZE gig.gig_worker_profile;")
            cur.execute("ANALYZE gig.gig_request;")
            cur.execute("ANALYZE gig.gig_assignment;")
            cur.execute("ANALYZE commercial.wallet;")
            cur.execute("ANALYZE commercial.wallet_ledger;")
            cur.execute("ANALYZE messaging.notification_delivery;")
            cur.execute("ANALYZE analytics.fact_application_event;")
        
        total_time = time.time() - t_start
        print(f"\n[+] Seeding completed successfully in {total_time:.2f} seconds.")
    finally:
        conn.close()

if __name__ == "__main__":
    main()
