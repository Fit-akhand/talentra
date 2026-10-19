# Talentra External Integration Boundaries Dossier
**System Engine**: PostgreSQL 17  
**Architecture**: Bounded Integration Contexts  
**Boundary Count**: 9 Standard Enterprise Boundaries  

---

## 1. Integration Boundary Architecture Overview

Talentra interacts with 9 external third-party services and legacy enterprise boundaries. Rather than allowing foreign schemas or untyped JSON payloads to pollute internal relational models, every integration is governed by a **Strict Bounded Context**:
1. **Inbound Payloads**: Validated, sanitized, and transformed into strongly-typed domain records with check constraints.
2. **Outbound Operations**: Governed by idempotency tokens and recorded in audit logs.
3. **Resilience Principle**: The database never relies on external system uptime for core transactional commits. If an external provider is unreachable, operations queue gracefully or fail isolatedly without corrupting core state.

```
                              +-------------------------------------------+
                              |         TALENTRA POSTGRESQL 17            |
                              |              DATA ENGINE                  |
                              +-------------------------------------------+
                                    |              |              |
                +-------------------+              |              +-------------------+
                |                                  |                                  |
                v                                  v                                  v
     +---------------------+            +---------------------+            +---------------------+
     | 1. Resume Parsing   |            | 3. Payment Gateway  |            | 6. Messaging Queue  |
     | - Stored: Skills/Exp|            | - Stored: Order ID  |            | - Stored: Receipt   |
     | - Ref: Storage URI  |            | - Ref: Provider Ref |            | - Ref: Message Body |
     +---------------------+            +---------------------+            +---------------------+
                |                                  |                                  |
                v                                  v                                  v
     +---------------------+            +---------------------+            +---------------------+
     | 2. Assessments      |            | 4. Background Check |            | 8. Geolocation      |
     | - Stored: Score/Pct |            | - Stored: Pass/Fail |            | - Stored: Lat/Long  |
     | - Ref: Exam Session |            | - Ref: Report URL   |            | - Ref: Map Tiles    |
     +---------------------+            +---------------------+            +---------------------+
```

---

## 2. Integration Boundary Specifications

| # | Boundary Name | External Partner / Type | Data Ownership | Stored in PostgreSQL | Referenced Only (Not Stored) | Failure & Resilience Strategy | Idempotency Key | Audit & Security Trace |
| :-: | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **Resume Parsing** | Sovren / Textkernel / LLM Extractor | Talentra owns extracted profile data; Provider owns ML model weights | Parsed skills (`candidate_skill`), parsed experience (`candidate_work_experience`), normalized education, document storage URI | Raw OCR bounding boxes, proprietary ML confidence vector weights | Asynchronous worker queue; retry 3x with exponential backoff; manual CV edit fallback | `cv_file_hash` (`sha256`) | Document ingestion logged in `audit.audit_event`; document record in `profile.candidate_document` |
| **2** | **Assessment Providers** | HackerRank / Codility / TestGorilla | Provider owns test questions and proctoring recordings; Talentra owns candidate outcome | Assessment score, percentile rank, completion timestamp, verification status (`candidate_assessment`) | Raw keystroke logs, webcam proctoring video feeds, question source code | Asynchronous webhook ingestion; fallback to polling API every 15 min; status marked `'pending_evaluation'` | `external_test_session_id` | Assessment completion audited; webhook HMAC-SHA256 signature verified |
| **3** | **Payment Gateways** | Stripe / Razorpay / Adyen | Dual ownership: Provider owns cardholder PCI vault; Talentra owns order & invoice ledgers | Payment order ID, transaction amount, ISO currency, payment status, invoice reference (`payment_order`, `invoice`, `wallet_ledger`) | Raw credit card numbers, CVV, bank account numbers, 3DS biometric tokens | Webhook idempotency ledger; circuit breaker on checkout; DLQ for failed webhook delivery | `gateway_transaction_id` + `idempotency_key` (UUIDv4) | Every credit/debit recorded in strictly append-only `commercial.wallet_ledger`; PCI-DSS zero-storage compliance |
| **4** | **Background Verification** | Checkr / Sterling / Onfido | Provider owns investigation dossier; Talentra owns verification outcome flag | Verification status (`verified`, `failed`, `pending`), verification date, certified provider name, report hash | Full court records, criminal registry documents, credit bureau dossiers | Asynchronous long-running webhook (24h–72h); polling fallback every 6h; manual compliance review | `bg_check_case_id` | Verification status transitions audited; sensitive dossier view access logged |
| **5** | **Legacy HRIS / ATS** | Workday / SAP SuccessFactors / Greenhouse | Client enterprise owns employee master; Talentra owns sourcing & candidate pipeline | Unified candidate ID, enterprise org ID, legacy sync timestamp, mapped status | Deprecated legacy custom fields, decommissioned on-prem database internal keys | Field-level conflict resolution; Talentra authoritative on applications, HRIS authoritative on joining; dual-write queue | `legacy_source_system` + `legacy_record_id` | Bidirectional sync history and conflict logs persisted in `audit.audit_event` |
| **6** | **Messaging Providers** | Twilio (SMS/WhatsApp) / SendGrid (Email) / FCM (Push) | Provider owns carrier routing; Talentra owns delivery ledger and communication templates | Channel, recipient ID, delivery status (`queued`, `sent`, `delivered`, `failed`, `read`), sent_at (`notification_delivery`) | Ephemeral raw message body text (pruned after 90 days), carrier SMS routing logs | Asynchronous BullMQ / Celery worker; exponential backoff (1s, 5s, 30s); fallback from WhatsApp to SMS to email | `provider_message_id` + `notification_id` | All outbound deliveries logged; unsubscribe and opt-out preferences enforced in `user_notification_preference` |
| **7** | **Social Sharing** | LinkedIn / Twitter / WhatsApp Share | Social platforms own feed engagement; Talentra owns outbound share attribution | Job posting ID, share token, click attribution count, social platform code | Social network user graph, external social feed comments | Client-side direct redirect; asynchronous pixel tracking; zero dependency on social API availability | `share_token_id` (UUIDv4) | Share event tracked in analytics mart; no candidate PII transmitted |
| **8** | **Geolocation Service** | Google Maps API / OpenStreetMap / Mapbox | Provider owns cartographic vector tiles; Talentra owns city/state master boundaries | Standardized city ID, country ISO, latitude, longitude coordinate pairs | Vector map tiles, street polyline geometries, traffic overlay data | Cache geocoding lookups in Redis/DB; fallback to city centroid coordinates from `master.city` | `location_hash` (`md5(normalized_address)`) | Geocoding API usage metrics tracked; location changes logged in `profile.candidate_location` |
| **9** | **Salary & Review Aggregators** | Levels.fyi / Glassdoor / Payscale API | Provider owns aggregated benchmark dataset; Talentra owns job salary bounds | Percentile salary tiers (p25, p50, p75), normalized role name, refresh timestamp | Individual anonymous employee review texts, proprietary salary regression weights | Daily background synchronization worker; serve cached percentile benchmarks on API timeout | `source_benchmark_id` | Ingestion metadata and salary currency conversions audited in reporting mart |

---

## 3. Detailed Boundary Specifications

### 3.1 Boundary 1: Resume Parsing Service
* **Interface Protocol**: Asynchronous REST webhook over TLS 1.3 with HMAC-SHA256 signature verification.
* **Storage Invariant**: Raw resume files (PDF/DOCX) are stored in an S3-compatible Object Storage bucket with SSE-KMS encryption. PostgreSQL stores only the object storage key (`storage_key`), file size, MIME type, and cryptographic SHA-256 hash.
* **Failure Handling**: If the parser crashes or times out (30s threshold), the document status is updated to `'parse_failed'` in `profile.candidate_document`. A message is posted to a Dead-Letter Queue (DLQ) for asynchronous retry. The candidate can immediately fill in their experience manually via the web interface.

### 3.2 Boundary 2: Assessment Providers
* **Interface Protocol**: Outbound candidate invite via REST API; inbound test completion via signed webhook.
* **Data Flow**:
  1. Recruiter assigns an assessment: Talentra generates an `invitation_token` and calls Provider API.
  2. Candidate completes test on Provider platform.
  3. Provider calls Talentra webhook with `external_test_session_id`, `score`, and `percentile`.
  4. Talentra verifies webhook HMAC signature, records the score in `profile.candidate_assessment`, and triggers a pipeline stage transition if the candidate passes the cut-off threshold.

### 3.3 Boundary 3: Payment Gateway & Wallet Ledger
* **Zero PCI-DSS Footprint**: Talentra servers never see or store raw Primary Account Numbers (PAN), CVVs, or cardholder banking credentials.
* **Idempotency Strategy**: Every payment intent generates an application-side UUIDv4 idempotency key passed in the header:
  ```http
  Idempotency-Key: 9ddb55c2-a252-4ee3-88e7-ff27f18a343f
  ```
* **Ledger Atomicity**: When a Stripe `payment_intent.succeeded` webhook is received:
  1. The transaction checks if `gateway_transaction_id` has already been recorded in `commercial.payment_order`. If yes, it returns `HTTP 200 OK` immediately (idempotent duplicate suppression).
  2. It updates `commercial.payment_order.order_status = 'completed'`.
  3. It creates an append-only entry in `commercial.wallet_ledger` with `entry_type = 'credit'`, `reference_type = 'recharge'`.
  4. It increments `commercial.wallet.balance` by the exact credited amount.
  5. The entire workflow is executed inside a single PostgreSQL transaction block (`ISOLATION LEVEL READ COMMITTED`).

### 3.4 Boundary 4: Background Verification
* **Compliance Invariant**: Full background dossier reports containing criminal records or credit histories are stored exclusively in the certified provider's vault.
* **Talentra Storage**: Talentra stores only a Boolean certification flag (`is_verified = TRUE`), the certified provider's identifier (`Checkr`), and a temporary expiring URL (TTL = 15 minutes) fetched on-demand by authorized enterprise compliance officers.

### 3.5 Boundary 5: Legacy Enterprise Systems
* **Conflict Resolution Strategy**:
  * If a conflict occurs during synchronization (e.g., job title updated in both Talentra and Workday), Talentra applies a **Deterministic Source-of-Truth Rule**:
    * Sourcing & Application Pipeline: **Talentra is Source of Truth**.
    * Employee Joining & Payroll: **Enterprise HRIS is Source of Truth**.
  * All synchronization anomalies are logged in `audit.system_error_log` with the conflicting JSON payloads preserved for manual review.

### 3.6 Boundary 6: High-Volume Messaging Providers
* **Delivery Status Lifecycle**:
  ```mermaid
  stateDiagram-v2
      [*] --> Queued: Notification Created
      Queued --> Sent: Provider Dispatched
      Sent --> Delivered: Delivery Receipt Received
      Sent --> Failed: Bounced / Invalid Number
      Delivered --> Read: Recipient Opened App
      Failed --> Retried: Exponential Backoff (3x)
      Retried --> DLQ: Max Retries Exceeded
  ```
* **Rate Limiting & Cost Control**: If a candidate receives $>5$ alerts within a 1-hour window, outbound dispatches are coalesced into a single digest summary, preventing messaging spam and API cost overrun.

### 3.7 Boundary 7: Social Sharing & Attribution
* **Anonymized Attribution**: When a job seeker clicks "Share on LinkedIn", Talentra generates a short share link containing a cryptographic `share_token`:
  ```
  https://talentra.io/jobs/1042?st=a7b8c9d0e1f2
  ```
* **Privacy Assurance**: The share event records zero candidate PII. Only aggregated click counters and candidate application source attributes (`application_source = 'social_linkedin'`) are captured.

### 3.8 Boundary 8: Geolocation Service
* **Caching & Spatial Resilience**:
  * Addresses are normalized and queried against Google Maps API / Mapbox.
  * Standardized city and coordinate pairs are cached permanently in `master.city`.
  * If the external geolocation provider encounters an outage, Talentra falls back to spatial bounding box queries calculated from `master.city` centroid coordinates, ensuring continuous operation of job radius searches.

### 3.9 Boundary 9: Review & Salary Data Aggregator
* **Ingestion Cadence**: Background workers pull anonymized salary percentile distributions once every 24 hours.
* **Resilience Invariant**: Job posting creations and candidate applications are completely decoupled from external salary API response times. If the salary aggregator is unreachable, the system displays the employer's declared salary range (`salary_min`, `salary_max`) without percentile benchmark overlays.
