# Talentra: Entity Lifecycles and State Machines (Step 08)

**Phase:** 2 Model | **Step:** 08 Entity Lifecycle and State Machines
**Generated** by `scripts/lifecycle/gen_model_catalogues.py`. States are read from CHECK constraints and transitions from `master.status_transition`; do not hand-edit.

A status column is **governed** when `master.status_transition` lists its legal moves and a trigger rejects every other update (migration 022). Everything not listed is illegal, so the illegal transitions are the complement and need no separate list. A status with no outgoing move is **final**.

**25 governed state machines, 5 recorded exemptions, 0 status columns undecided** (of 30 status-like columns).

## Governed state machines

### `commercial.invoice.invoice_status`

States: `draft`, `issued`, `paid`, `void`, `uncollectible`. Initial: `draft`. Final: `paid`, `void`, `uncollectible`. Legal moves: 5. Illegal moves (rejected): 15.

| From | Allowed next states |
|:--|:--|
| `draft` | `issued`, `void` |
| `issued` | `paid`, `uncollectible`, `void` |
| `paid` | *final* |
| `void` | *final* |
| `uncollectible` | *final* |

### `commercial.payment_order.order_status`

States: `created`, `authorized`, `captured`, `failed`, `cancelled`, `refunded`. Initial: `created`. Final: `failed`, `cancelled`, `refunded`. Legal moves: 7. Illegal moves (rejected): 23.

| From | Allowed next states |
|:--|:--|
| `created` | `authorized`, `cancelled`, `failed` |
| `authorized` | `cancelled`, `captured`, `failed` |
| `captured` | `refunded` |
| `failed` | *final* |
| `cancelled` | *final* |
| `refunded` | *final* |

### `commercial.subscription.subscription_status`

States: `active`, `cancelled`, `expired`. Initial: `active`. Final: `cancelled`, `expired`. Legal moves: 2. Illegal moves (rejected): 4.

| From | Allowed next states |
|:--|:--|
| `active` | `cancelled`, `expired` |
| `cancelled` | *final* |
| `expired` | *final* |

### `commercial.subscription_licence.licence_status`

States: `active`, `expired`, `suspended`, `cancelled`. Initial: none. Final: `expired`, `cancelled`. Legal moves: 6. Illegal moves (rejected): 6.

| From | Allowed next states |
|:--|:--|
| `active` | `cancelled`, `expired`, `suspended` |
| `expired` | *final* |
| `suspended` | `active`, `cancelled`, `expired` |
| `cancelled` | *final* |

### `core.identity_verification.verification_status`

States: `pending`, `verified`, `rejected`, `expired`. Initial: none. Final: none. Legal moves: 6. Illegal moves (rejected): 6.

| From | Allowed next states |
|:--|:--|
| `pending` | `expired`, `rejected`, `verified` |
| `verified` | `expired` |
| `rejected` | `pending` |
| `expired` | `pending` |

### `core.user_account.account_status`

States: `pending`, `active`, `suspended`, `deactivated`. Initial: `pending`. Final: `deactivated`. Legal moves: 6. Illegal moves (rejected): 6.

| From | Allowed next states |
|:--|:--|
| `pending` | `active`, `deactivated` |
| `active` | `deactivated`, `suspended` |
| `suspended` | `active`, `deactivated` |
| `deactivated` | *final* |

### `gig.gig_application.application_status`

States: `submitted`, `accepted`, `rejected`, `withdrawn`. Initial: `submitted`. Final: `accepted`, `rejected`, `withdrawn`. Legal moves: 3. Illegal moves (rejected): 9.

| From | Allowed next states |
|:--|:--|
| `submitted` | `accepted`, `rejected`, `withdrawn` |
| `accepted` | *final* |
| `rejected` | *final* |
| `withdrawn` | *final* |

### `gig.gig_assignment.assignment_status`

States: `active`, `completed`, `terminated`. Initial: `active`. Final: `completed`, `terminated`. Legal moves: 2. Illegal moves (rejected): 4.

| From | Allowed next states |
|:--|:--|
| `active` | `completed`, `terminated` |
| `completed` | *final* |
| `terminated` | *final* |

### `gig.gig_request.request_status`

States: `open`, `awarded`, `in_progress`, `completed`, `cancelled`. Initial: `open`. Final: `completed`, `cancelled`. Legal moves: 6. Illegal moves (rejected): 14.

| From | Allowed next states |
|:--|:--|
| `open` | `awarded`, `cancelled` |
| `awarded` | `cancelled`, `in_progress` |
| `in_progress` | `cancelled`, `completed` |
| `completed` | *final* |
| `cancelled` | *final* |

### `gig.gig_worker_profile.verification_status`

States: `unverified`, `verified`, `suspended`. Initial: `unverified`. Final: none. Legal moves: 4. Illegal moves (rejected): 2.

| From | Allowed next states |
|:--|:--|
| `unverified` | `suspended`, `verified` |
| `verified` | `suspended` |
| `suspended` | `verified` |

### `messaging.integration_event.event_status`

States: `pending`, `in_progress`, `succeeded`, `failed`, `dead_letter`. Initial: none. Final: `succeeded`. Legal moves: 7. Illegal moves (rejected): 13.

| From | Allowed next states |
|:--|:--|
| `pending` | `in_progress` |
| `in_progress` | `dead_letter`, `failed`, `succeeded` |
| `succeeded` | *final* |
| `failed` | `dead_letter`, `in_progress` |
| `dead_letter` | `pending` |

### `messaging.referral_event.status`

States: `invited`, `registered`, `qualified_hire`, `reward_paid`. Initial: `invited`. Final: `reward_paid`. Legal moves: 3. Illegal moves (rejected): 9.

| From | Allowed next states |
|:--|:--|
| `invited` | `registered` |
| `registered` | `qualified_hire` |
| `qualified_hire` | `reward_paid` |
| `reward_paid` | *final* |

### `messaging.support_ticket.ticket_status`

States: `open`, `in_progress`, `waiting_on_user`, `resolved`, `closed`. Initial: `open`. Final: `closed`. Legal moves: 10. Illegal moves (rejected): 10.

| From | Allowed next states |
|:--|:--|
| `open` | `closed`, `in_progress` |
| `in_progress` | `closed`, `resolved`, `waiting_on_user` |
| `waiting_on_user` | `closed`, `in_progress`, `resolved` |
| `resolved` | `closed`, `in_progress` |
| `closed` | *final* |

### `profile.candidate_document.document_status`

States: `uploaded`, `scanning`, `ready`, `rejected`, `archived`. Initial: `uploaded`. Final: `archived`. Legal moves: 8. Illegal moves (rejected): 12.

| From | Allowed next states |
|:--|:--|
| `uploaded` | `archived`, `rejected`, `scanning` |
| `scanning` | `archived`, `ready`, `rejected` |
| `ready` | `archived` |
| `rejected` | `archived` |
| `archived` | *final* |

### `profile.candidate_profile.profile_status`

States: `draft`, `active`, `paused`. Initial: `draft`. Final: none. Legal moves: 3. Illegal moves (rejected): 3.

| From | Allowed next states |
|:--|:--|
| `draft` | `active` |
| `active` | `paused` |
| `paused` | `active` |

### `profile.course_enrolment.enrolment_status`

States: `enrolled`, `in_progress`, `completed`, `dropped`. Initial: none. Final: `completed`. Legal moves: 6. Illegal moves (rejected): 6.

| From | Allowed next states |
|:--|:--|
| `enrolled` | `completed`, `dropped`, `in_progress` |
| `in_progress` | `completed`, `dropped` |
| `completed` | *final* |
| `dropped` | `enrolled` |

### `recruitment.candidate_application.application_status`

States: `sourced`, `applied`, `shortlisted`, `interviewed`, `offered`, `joined`, `rejected`, `withdrawn`. Initial: `sourced`. Final: `joined`, `rejected`, `withdrawn`. Legal moves: 16. Illegal moves (rejected): 40.

| From | Allowed next states |
|:--|:--|
| `sourced` | `applied`, `rejected`, `shortlisted`, `withdrawn` |
| `applied` | `rejected`, `shortlisted`, `withdrawn` |
| `shortlisted` | `interviewed`, `rejected`, `withdrawn` |
| `interviewed` | `offered`, `rejected`, `withdrawn` |
| `offered` | `joined`, `rejected`, `withdrawn` |
| `joined` | *final* |
| `rejected` | *final* |
| `withdrawn` | *final* |

### `recruitment.job_position.position_status`

States: `open`, `offered`, `filled`, `cancelled`. Initial: none. Final: `filled`, `cancelled`. Legal moves: 6. Illegal moves (rejected): 6.

| From | Allowed next states |
|:--|:--|
| `open` | `cancelled`, `filled`, `offered` |
| `offered` | `cancelled`, `filled`, `open` |
| `filled` | *final* |
| `cancelled` | *final* |

### `recruitment.job_posting.job_status`

States: `draft`, `published`, `paused`, `closed`, `filled`, `cancelled`. Initial: `draft`. Final: `filled`, `cancelled`. Legal moves: 10. Illegal moves (rejected): 20.

| From | Allowed next states |
|:--|:--|
| `draft` | `cancelled`, `published` |
| `published` | `cancelled`, `closed`, `filled`, `paused` |
| `paused` | `cancelled`, `closed`, `published` |
| `closed` | `published` |
| `filled` | *final* |
| `cancelled` | *final* |

### `recruitment.organization.organization_status`

States: `pending`, `active`, `suspended`, `closed`. Initial: `pending`. Final: `closed`. Legal moves: 6. Illegal moves (rejected): 6.

| From | Allowed next states |
|:--|:--|
| `pending` | `active`, `closed` |
| `active` | `closed`, `suspended` |
| `suspended` | `active`, `closed` |
| `closed` | *final* |

### `recruitment.organization_identifier.verification_status`

States: `unverified`, `pending`, `verified`, `rejected`. Initial: `unverified`. Final: none. Legal moves: 7. Illegal moves (rejected): 5.

| From | Allowed next states |
|:--|:--|
| `unverified` | `pending`, `rejected`, `verified` |
| `pending` | `rejected`, `verified` |
| `verified` | `pending` |
| `rejected` | `pending` |

### `recruitment.organization_member.membership_status`

States: `invited`, `active`, `suspended`, `removed`. Initial: `invited`. Final: `removed`. Legal moves: 6. Illegal moves (rejected): 6.

| From | Allowed next states |
|:--|:--|
| `invited` | `active`, `removed` |
| `active` | `removed`, `suspended` |
| `suspended` | `active`, `removed` |
| `removed` | *final* |

### `sourcing.consultant_sourcing_request.request_status`

States: `requested`, `accepted`, `declined`, `revoked`. Initial: `requested`. Final: `declined`, `revoked`. Legal moves: 4. Illegal moves (rejected): 8.

| From | Allowed next states |
|:--|:--|
| `requested` | `accepted`, `declined`, `revoked` |
| `accepted` | `revoked` |
| `declined` | *final* |
| `revoked` | *final* |

### `sourcing.outreach_batch.status`

States: `draft`, `queued`, `processing`, `completed`, `cancelled`. Initial: `draft`. Final: `completed`, `cancelled`. Legal moves: 6. Illegal moves (rejected): 14.

| From | Allowed next states |
|:--|:--|
| `draft` | `cancelled`, `queued` |
| `queued` | `cancelled`, `processing` |
| `processing` | `cancelled`, `completed` |
| `completed` | *final* |
| `cancelled` | *final* |

### `sourcing.sourcing_submission.submission_status`

States: `submitted`, `shortlisted`, `accepted`, `rejected`, `hired`. Initial: `submitted`. Final: `rejected`, `hired`. Legal moves: 6. Illegal moves (rejected): 14.

| From | Allowed next states |
|:--|:--|
| `submitted` | `rejected`, `shortlisted` |
| `shortlisted` | `accepted`, `rejected` |
| `accepted` | `hired`, `rejected` |
| `rejected` | *final* |
| `hired` | *final* |

## Status columns without transition rules

A status that no trigger governs must be a recorded decision, not an oversight: it is either set by an external service whose callbacks arrive out of order (`external_driver`) or it is the outcome column of an append-only history row (`append_only_history`). The reasons are rows in `master.status_machine_exemption`; `tests/test_state_machines.sql` fails if a status column is neither governed nor exempt.

| Table | Column | Kind | Reason |
|:--|:--|:--|:--|
| `audit.maintenance_run` | `run_status` | append_only_history | One row is written when a job finishes; the status is its outcome, not a state that changes. |
| `messaging.notification_delivery` | `delivery_status` | external_driver | Written from provider callbacks that arrive out of order (a "delivered" can precede "sent"). Rejecting a legitimate late callback would lose the truth; ordering is resolved by the provider timestamp in the application. |
| `recruitment.application_status_history` | `new_status` | append_only_history | A history row records a move that the application table has already validated; the history itself is append-only. |
| `recruitment.application_status_history` | `previous_status` | append_only_history | As new_status: it records the state left, and the history cannot be updated. |
| `sourcing.outreach_recipient` | `delivery_status` | external_driver | Same as notification delivery: set from provider callbacks and recipient replies, which are not ordered. |

## Gaps

1. Every status column is governed (25) or a recorded exemption (5); none is undecided.
2. Enumerations are CHECK lists, not lookup tables. Docket Rule Group 3 asks for lookup tables with per-language display names. The deviation is recorded in `11-rule-compliance.md`.
