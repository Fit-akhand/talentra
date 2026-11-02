#!/usr/bin/env python3
"""Generate docs/phase-4-platform/22-integration-boundaries.md (playbook step 22) from the live database.

For each of the docket's nine boundaries (section 6): data ownership, stored versus referenced data, failure behaviour, the retry policy,
the idempotency and audit rules, and the database objects that hold what the boundary promises to store. Every object named is looked up in
the catalog; the generator fails if one does not exist. The legacy-sync section lists every field of the synchronised tables with its
direction, conflict rule and owner.
"""
import os, sys
import psycopg2

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "docs", "phase-4-platform", "22-integration-boundaries.md")
# boundary code -> the objects (table, view, function or schema.table.column) that hold what it stores
OBJECTS = {
    "payment_gateway": ["commercial.payment_order", "commercial.payment_order.gateway_order_id", "commercial.payment_order.idempotency_key", "commercial.payment_refund", "commercial.invoice", "commercial.wallet_ledger"],
    "identity_verification": ["core.identity_verification", "core.identity_verification.provider_token_ref"],
    "company_verification": ["recruitment.organization_identifier", "recruitment.organization_identifier.verification_status", "recruitment.organization_identifier.identifier_ciphertext"],
    "gig_fulfilment": ["gig.gig_assignment.external_handoff_ref", "gig.gig_assignment.external_status", "gig.gig_external_earnings"],
    "legacy_sync": ["messaging.external_reference", "messaging.legacy_field_mapping", "messaging.sync_conflict", "messaging.resolve_sync_conflict"],
    "messaging_provider": ["messaging.notification_delivery", "messaging.notification_template", "messaging.user_notification_preference"],
    "social_sharing": ["messaging.share_event"],
    "geolocation": ["recruitment.organization_location.latitude", "recruitment.organization_location.longitude", "recruitment.organization_location.place_reference"],
    "company_reviews": ["recruitment.company_review_summary", "recruitment.company_review_summary_labelled"],
}
COMMON = ["messaging.integration_boundary", "messaging.integration_event", "messaging.enqueue_integration_event", "messaging.claim_integration_events",
          "messaging.complete_integration_event", "messaging.fail_integration_event", "messaging.requeue_dead_letter", "audit.ops_integration_health"]


def main():
    cx = psycopg2.connect(host=os.getenv("PGHOST", "127.0.0.1"), port=os.getenv("PGPORT", "5432"), user=os.getenv("PGUSER", "talentra_admin"),
                          dbname=os.getenv("PGDATABASE", "talentra"), password=os.getenv("PGPASSWORD"))
    cur = cx.cursor()
    cur.execute("""SELECT n.nspname || '.' || c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind IN ('r','p','v','m')
                   UNION SELECT n.nspname || '.' || p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   UNION SELECT table_schema || '.' || table_name || '.' || column_name FROM information_schema.columns""")
    exist = {r[0] for r in cur.fetchall()}
    missing = sorted({o for objs in list(OBJECTS.values()) + [COMMON] for o in objs if o not in exist})
    cur.execute("""SELECT code, name, source_of_truth, stored_data, referenced_data, failure_behaviour, idempotency_rule, audit_rule, is_optional, max_attempts, base_backoff_seconds
                     FROM messaging.integration_boundary ORDER BY id""")
    bounds = cur.fetchall()
    unmapped = [b[0] for b in bounds if b[0] not in OBJECTS]
    cur.execute("""SELECT talentra_table, talentra_column, legacy_entity, legacy_field, direction, conflict_rule, owner_role, note
                     FROM messaging.legacy_field_mapping ORDER BY talentra_table, direction = 'not_synced', talentra_column""")
    maps = cur.fetchall()
    cur.execute("SELECT direction, count(*) FROM messaging.legacy_field_mapping GROUP BY 1"); dcount = dict(cur.fetchall())
    cur.execute("SELECT conflict_rule, count(*) FROM messaging.legacy_field_mapping WHERE conflict_rule IS NOT NULL GROUP BY 1 ORDER BY 2 DESC"); rcount = cur.fetchall()

    L = ["# Integration Boundaries (Step 22)\n",
         "**Phase:** 4 Platform | **Step:** 22 Integration and Source Mapping",
         "**Generated** by `scripts/lifecycle/gen_integration_doc.py` from `messaging.integration_boundary`, `messaging.legacy_field_mapping` and the catalog. Do not hand-edit. The previous hand-written version described nine different boundaries and tables that do not exist; it is replaced.\n",
         "The docket (section 6) names nine external boundaries. The schema must reference their data but does not own their processes. For each, the docket requires: who is the source of truth, what is stored versus referenced, and what happens when the other system is down. The rows below are the live contents of `messaging.integration_boundary`, so the database and this document cannot disagree.\n",
         "**Out of scope by the docket:** integrating with live external services. Nothing here calls one. What the database provides is the storage each boundary promises, and the outbox that makes an exchange safe to retry.\n",
         "## How every exchange behaves\n",
         "All nine share one mechanism (`messaging.integration_event`, WF-15): an exchange is enqueued with an idempotency key, claimed by a worker, and completed or failed. A failure schedules the next attempt with exponential backoff from the boundary's base interval; after the boundary's maximum attempts it becomes a dead letter, an `INTEGRATION_DEAD_LETTER` row is written to `audit.system_error_log` (severity *warning* for optional boundaries, *error* otherwise), and `audit.ops_integration_health` shows it. A replayed idempotency key is a no-op. Dead letters are replayed by an operator with `messaging.requeue_dead_letter`.\n",
         "| Boundary | Optional | Attempts | First backoff |", "|:--|:--|--:|--:|"]
    for code, name, sot, stored, ref, fail, idem, aud, opt, att, back in bounds:
        L.append(f"| {name} (`{code}`) | {'yes' if opt else 'no'} | {att} | {back} s |")
    L += ["", "## The nine boundaries\n"]
    for code, name, sot, stored, ref, fail, idem, aud, opt, att, back in bounds:
        L += [f"### {name} (`{code}`)\n", "| Question | Answer |", "|:--|:--|",
              f"| Source of truth | {sot} |", f"| Stored in Talentra | {stored} |", f"| Only referenced | {ref} |",
              f"| When the other system is down | {fail} |", f"| Idempotency | {idem} |", f"| Audit | {aud} |",
              f"| Database objects | {', '.join(f'`{o}`' for o in OBJECTS.get(code, []))} |", ""]
    L += ["## Legacy sync: direction and conflict rule for every field\n",
          "The docket requires the sync direction for each field and the rule for conflicts. The legacy systems' schemas were not available, so **the legacy field names are assumptions** (DEC-32); the Talentra columns, directions, rules and owners are real and are held in `messaging.legacy_field_mapping`. `messaging.resolve_sync_conflict` applies a rule to one field and `messaging.sync_conflict` logs the result with hashes, not values.\n",
          f"**{sum(v for k, v in dcount.items() if k != 'not_synced')} fields are synchronised** ({', '.join(f'{k} {v}' for k, v in sorted(dcount.items()) if k != 'not_synced')}); **{dcount.get('not_synced', 0)} columns of the same tables are recorded as not synchronised**, each with the reason. Rules in use: " + ", ".join(f"{k} ({v})" for k, v in rcount) + ".\n",
          "| Rule | Meaning |", "|:--|:--|",
          "| `legacy_wins` | Facts about the past (original publication time, how an application arrived) and identities; never overwritten |",
          "| `talentra_wins` | Reserved; not used by any field today |",
          "| `latest_update_wins` | Whichever side changed the field last; a tie goes to a person |",
          "| `cutover_dependent` | The legacy value until cut-over, the Talentra value after |",
          "| `manual_review` | A person decides, every time |", "",
          "| Talentra field | Legacy field | Direction | Rule | Owner | Note |", "|:--|:--|:--|:--|:--|:--|"]
    for t, c, le, lf, d, r, o, n in maps:
        L.append(f"| `{t}.{c}` | {f'{le}.{lf}' if lf else '-'} | {d} | {r or '-'} | {o} | {n} |")
    L += ["", "## Not designed here\n",
          "- **Ingestion and migration (step 25)** are out of scope in the docket; the mapping above is what a migration would be written against.",
          "- **The cut-over date** is a parameter of `messaging.resolve_sync_conflict`, not a stored value; the person running the migration supplies it.",
          "- **Live calls** to any of the nine systems."]
    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(f"{len(bounds)} boundaries, {len(maps)} mapped columns; objects missing: {missing}; boundaries without objects: {unmapped}")
    if missing or unmapped: sys.exit(1)


if __name__ == "__main__":
    main()
