# Integration Boundaries (Step 22)

**Phase:** 4 Platform | **Step:** 22 Integration and Source Mapping
**Generated** by `scripts/lifecycle/gen_integration_doc.py` from `messaging.integration_boundary`, `messaging.legacy_field_mapping` and the catalog. Do not hand-edit. The previous hand-written version described nine different boundaries and tables that do not exist; it is replaced.

The docket (section 6) names nine external boundaries. The schema must reference their data but does not own their processes. For each, the docket requires: who is the source of truth, what is stored versus referenced, and what happens when the other system is down. The rows below are the live contents of `messaging.integration_boundary`, so the database and this document cannot disagree.

**Out of scope by the docket:** integrating with live external services. Nothing here calls one. What the database provides is the storage each boundary promises, and the outbox that makes an exchange safe to retry.

## How every exchange behaves

All nine share one mechanism (`messaging.integration_event`, WF-15): an exchange is enqueued with an idempotency key, claimed by a worker, and completed or failed. A failure schedules the next attempt with exponential backoff from the boundary's base interval; after the boundary's maximum attempts it becomes a dead letter, an `INTEGRATION_DEAD_LETTER` row is written to `audit.system_error_log` (severity *warning* for optional boundaries, *error* otherwise), and `audit.ops_integration_health` shows it. A replayed idempotency key is a no-op. Dead letters are replayed by an operator with `messaging.requeue_dead_letter`.

| Boundary | Optional | Attempts | First backoff |
|:--|:--|--:|--:|
| Payment gateway (`payment_gateway`) | no | 3 | 30 s |
| Identity verification service (`identity_verification`) | no | 3 | 60 s |
| Company registration and tax verification (`company_verification`) | no | 3 | 60 s |
| Gig fulfilment system (`gig_fulfilment`) | no | 3 | 120 s |
| Legacy job and candidate systems (`legacy_sync`) | no | 3 | 300 s |
| Messaging and notification providers (`messaging_provider`) | no | 3 | 30 s |
| Social sharing (`social_sharing`) | yes | 1 | 30 s |
| Mapping and geolocation service (`geolocation`) | yes | 3 | 300 s |
| Company review and salary data (`company_reviews`) | yes | 3 | 3600 s |

## The nine boundaries

### Payment gateway (`payment_gateway`)

| Question | Answer |
|:--|:--|
| Source of truth | Gateway for money movement; Talentra for orders, invoices and the wallet ledger |
| Stored in Talentra | Transaction reference, status, amount, currency, invoice and wallet ledger entries |
| Only referenced | Card and bank data (never stored); the gateway's own customer records |
| When the other system is down | An order stays created or authorized; the wallet is credited only on a confirmed capture. After 3 failed attempts the event is dead-lettered and the order is left for a person to settle. |
| Idempotency | idempotency_key on the payment order (unique per organisation) and on every gateway event |
| Audit | payment_order and payment_refund changes are audit events (classes 14); the wallet ledger is the financial trail |
| Database objects | `commercial.payment_order`, `commercial.payment_order.gateway_order_id`, `commercial.payment_order.idempotency_key`, `commercial.payment_refund`, `commercial.invoice`, `commercial.wallet_ledger` |

### Identity verification service (`identity_verification`)

| Question | Answer |
|:--|:--|
| Source of truth | The verification service for the check; Talentra for the outcome |
| Stored in Talentra | Verification outcome and an opaque token |
| Only referenced | The raw identity number (never stored in clear text) |
| When the other system is down | The account stays unverified; features that need verification stay locked. Retried 3 times, then dead-lettered. |
| Idempotency | The verification request id supplied by the service |
| Audit | Outcome changes are account status changes (class 7) |
| Database objects | `core.identity_verification`, `core.identity_verification.provider_token_ref` |

### Company registration and tax verification (`company_verification`)

| Question | Answer |
|:--|:--|
| Source of truth | The registry for the record; Talentra for the verification status |
| Stored in Talentra | Verification status and the identifiers used for lookup (encrypted, see recruitment.organization_identifier) |
| Only referenced | The registry's full company record |
| When the other system is down | The organisation stays pending; job posting that needs verification waits. Retried 3 times, then dead-lettered. |
| Idempotency | organization_identifier id plus the registry lookup date |
| Audit | Status changes are organisation status changes (class 7) |
| Database objects | `recruitment.organization_identifier`, `recruitment.organization_identifier.verification_status`, `recruitment.organization_identifier.identifier_ciphertext` |

### Gig fulfilment system (`gig_fulfilment`)

| Question | Answer |
|:--|:--|
| Source of truth | The fulfilment system for execution and earnings; Talentra for the handoff reference and reconciled status |
| Stored in Talentra | Handoff reference, assignment status, reconciled earnings (gig_external_earnings) |
| Only referenced | The work product and the fulfilment system's internal state |
| When the other system is down | The assignment keeps its last reconciled status and reconciliation is retried; earnings are never guessed. Dead-lettered after 3 attempts. |
| Idempotency | external_handoff_ref on the assignment, and the sync hash on earnings |
| Audit | Reconciliations are rows in gig_external_earnings with a sync hash; failures are in the dead-letter queue |
| Database objects | `gig.gig_assignment.external_handoff_ref`, `gig.gig_assignment.external_status`, `gig.gig_external_earnings` |

### Legacy job and candidate systems (`legacy_sync`)

| Question | Answer |
|:--|:--|
| Source of truth | The legacy system until cut-over, then Talentra. Candidate profile and job text: Talentra wins on conflict after cut-over; legacy wins before it. Status: the later timestamp wins. |
| Stored in Talentra | Mapped ids, last sync time, conflict log |
| Only referenced | Legacy-only fields not in the Talentra model |
| When the other system is down | Records that fail validation go to the dead-letter queue with the reason; the batch continues. Nothing is dropped silently. |
| Idempotency | The legacy system's record id plus its version or modified-at stamp |
| Audit | Every conflict and every rejected record is an integration_event |
| Database objects | `messaging.external_reference`, `messaging.legacy_field_mapping`, `messaging.sync_conflict`, `messaging.resolve_sync_conflict` |

### Messaging and notification providers (`messaging_provider`)

| Question | Answer |
|:--|:--|
| Source of truth | The provider for delivery; Talentra for preferences and the delivery record |
| Stored in Talentra | Delivery status, preferences, a short body snippet for audit |
| Only referenced | The full message body beyond what audit needs |
| When the other system is down | The delivery is marked failed and retried with backoff; after 3 attempts it is dead-lettered and the user sees the in-app notification instead. |
| Idempotency | The provider message id (external_provider_message_id) on the delivery |
| Audit | notification_delivery rows are the record; dead letters are in integration_event |
| Database objects | `messaging.notification_delivery`, `messaging.notification_template`, `messaging.user_notification_preference` |

### Social sharing (`social_sharing`)

| Question | Answer |
|:--|:--|
| Source of truth | The social platform for the post; Talentra for the fact that a share happened |
| Stored in Talentra | The share event |
| Only referenced | The external post content |
| When the other system is down | Not retried: a failed share is shown to the user and dropped. A lost share event costs nothing. |
| Idempotency | job posting id + platform + user, per day |
| Audit | Share events are integration_event rows |
| Database objects | `messaging.share_event` |

### Mapping and geolocation service (`geolocation`)

| Question | Answer |
|:--|:--|
| Source of truth | The service for coordinates; Talentra for the stored place reference |
| Stored in Talentra | Coordinates and place references |
| Only referenced | Map tiles and street data |
| When the other system is down | Optional: if the service is down the location is stored as text without coordinates and geocoded later. Never blocks a posting. |
| Idempotency | The place text plus country, hashed |
| Audit | Lookups are integration_event rows only when they fail |
| Database objects | `recruitment.organization_location.latitude`, `recruitment.organization_location.longitude`, `recruitment.organization_location.place_reference` |

### Company review and salary data (`company_reviews`)

| Question | Answer |
|:--|:--|
| Source of truth | The data provider |
| Stored in Talentra | Aggregated figures with source and refresh date |
| Only referenced | Individual reviews and the provider's raw dataset |
| When the other system is down | The previous figures stay visible with their refresh date; a stale figure is labelled, not hidden. Retried daily. |
| Idempotency | source + role + period |
| Audit | Refreshes are integration_event rows |
| Database objects | `recruitment.company_review_summary`, `recruitment.company_review_summary_labelled` |

## Legacy sync: direction and conflict rule for every field

The docket requires the sync direction for each field and the rule for conflicts. The legacy systems' schemas were not available, so **the legacy field names are assumptions** (DEC-32); the Talentra columns, directions, rules and owners are real and are held in `messaging.legacy_field_mapping`. `messaging.resolve_sync_conflict` applies a rule to one field and `messaging.sync_conflict` logs the result with hashes, not values.

**31 fields are synchronised** (bidirectional 3, inbound 28); **29 columns of the same tables are recorded as not synchronised**, each with the reason. Rules in use: cutover_dependent (16), legacy_wins (7), latest_update_wins (7), manual_review (1).

| Rule | Meaning |
|:--|:--|
| `legacy_wins` | Facts about the past (original publication time, how an application arrived) and identities; never overwritten |
| `talentra_wins` | Reserved; not used by any field today |
| `latest_update_wins` | Whichever side changed the field last; a tie goes to a person |
| `cutover_dependent` | The legacy value until cut-over, the Talentra value after |
| `manual_review` | A person decides, every time |

| Talentra field | Legacy field | Direction | Rule | Owner | Note |
|:--|:--|:--|:--|:--|:--|
| `core.user_account.email` | candidate.email | inbound | manual_review | Security | The email identifies the person; two different emails for one legacy record are a possible different person and need a human |
| `core.user_account.phone_e164` | candidate.mobile | inbound | latest_update_wins | Data | Contact data: the more recent change is the better one; legacy format is normalised to E.164 on the way in |
| `profile.candidate_profile.headline` | candidate.title | inbound | cutover_dependent | Product | Profile text: legacy before cut-over, Talentra after |
| `profile.candidate_profile.professional_summary` | candidate.about | inbound | cutover_dependent | Product | Profile text: legacy before cut-over, Talentra after |
| `profile.candidate_profile.profile_status` | candidate.status | bidirectional | latest_update_wins | Product | Either side can deactivate or reactivate; the later change wins |
| `profile.candidate_profile.summary_language_code` | candidate.about_lang | inbound | cutover_dependent | Data | Follows the text it describes |
| `profile.candidate_profile.total_experience_years` | candidate.experience_years | inbound | latest_update_wins | Data | A measurement that only goes up; the later value is right |
| `profile.candidate_profile.created_at` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `profile.candidate_profile.created_by_user_account_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `profile.candidate_profile.deleted_at` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `profile.candidate_profile.deleted_by_user_account_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `profile.candidate_profile.id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `profile.candidate_profile.updated_at` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `profile.candidate_profile.updated_by_user_account_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `profile.candidate_profile.user_account_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `profile.candidate_profile.visibility` | - | not_synced | - | Data | A Talentra privacy choice; the legacy systems have no equivalent |
| `recruitment.candidate_application.application_source` | application.channel | inbound | legacy_wins | Data | How the application arrived is a fact |
| `recruitment.candidate_application.application_status` | application.stage | bidirectional | latest_update_wins | Product | Both systems move candidates through stages until cut-over; the later move wins and the state machine still applies |
| `recruitment.candidate_application.applied_at` | application.created | inbound | legacy_wins | Data | History: the original application time is a fact |
| `recruitment.candidate_application.candidate_profile_id` | application.candidate_ref | inbound | legacy_wins | Data | Identity of the application; resolved through messaging.external_reference |
| `recruitment.candidate_application.cover_letter` | application.cover_note | inbound | legacy_wins | Data | What the candidate wrote at the time does not change |
| `recruitment.candidate_application.job_posting_id` | application.job_ref | inbound | legacy_wins | Data | Identity of the application; resolved through messaging.external_reference |
| `recruitment.candidate_application.candidate_document_id` | - | not_synced | - | Data | Documents are migrated separately into object storage and linked afterwards |
| `recruitment.candidate_application.created_at` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.candidate_application.created_by_user_account_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.candidate_application.id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.candidate_application.last_status_changed_at` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.candidate_application.updated_at` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.candidate_application.updated_by_user_account_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.application_deadline` | job.closes_on | inbound | latest_update_wins | Product | A date either side may extend |
| `recruitment.job_posting.currency_code` | job.salary_currency | inbound | cutover_dependent | Finance | As salary_min |
| `recruitment.job_posting.description` | job.description | inbound | cutover_dependent | Product | Job text: legacy before cut-over, Talentra after |
| `recruitment.job_posting.description_language_code` | job.description_lang | inbound | cutover_dependent | Data | Follows the text it describes |
| `recruitment.job_posting.job_status` | job.state | bidirectional | latest_update_wins | Product | Either side can close a job; the later change wins and the state machine still applies |
| `recruitment.job_posting.maximum_experience_years` | job.max_experience | inbound | cutover_dependent | Product | Requirement text in numeric form |
| `recruitment.job_posting.minimum_experience_years` | job.min_experience | inbound | cutover_dependent | Product | Requirement text in numeric form |
| `recruitment.job_posting.organization_id` | job.employer_ref | inbound | legacy_wins | Data | Ownership of an imported job never moves; resolved through messaging.external_reference |
| `recruitment.job_posting.published_at` | job.posted_on | inbound | legacy_wins | Data | History: the original publication time is a fact |
| `recruitment.job_posting.qualifications` | job.requirements | inbound | cutover_dependent | Product | Job text: legacy before cut-over, Talentra after |
| `recruitment.job_posting.responsibilities` | job.responsibilities | inbound | cutover_dependent | Product | Job text: legacy before cut-over, Talentra after |
| `recruitment.job_posting.salary_max` | job.salary_to | inbound | cutover_dependent | Finance | As salary_min |
| `recruitment.job_posting.salary_min` | job.salary_from | inbound | cutover_dependent | Finance | Compensation moves together with currency and period (a CHECK keeps the trio consistent) |
| `recruitment.job_posting.salary_period` | job.salary_unit | inbound | cutover_dependent | Finance | As salary_min |
| `recruitment.job_posting.title` | job.title | inbound | cutover_dependent | Product | Job text: legacy before cut-over, Talentra after |
| `recruitment.job_posting.vacancy_count` | job.openings | inbound | latest_update_wins | Product | A count either side may change as roles are filled |
| `recruitment.job_posting.workplace_location_text` | job.location_text | inbound | cutover_dependent | Data | Free text place; geocoding happens in Talentra |
| `recruitment.job_posting.city_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.closed_at` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.created_at` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.created_by_user_account_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.deleted_at` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.deleted_by_user_account_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.employment_type_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.industry_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.job_role_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.updated_at` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.updated_by_user_account_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.job_posting.work_type_id` | - | not_synced | - | Data | Maintained by Talentra: key, audit, lifecycle or derived column |
| `recruitment.organization.name` | employer.company_name | inbound | cutover_dependent | Product | Legacy owns the name until cut-over; Talentra after |

## Not designed here

- **Ingestion and migration (step 25)** are out of scope in the docket; the mapping above is what a migration would be written against.
- **The cut-over date** is a parameter of `messaging.resolve_sync_conflict`, not a stored value; the person running the migration supplies it.
- **Live calls** to any of the nine systems.
