"""Hand-written column definitions: the columns whose meaning is not in their name.

Rule for every entry on a nullable column: say what NULL means. build_definitions_migration.py refuses an entry that does not.
Keys are 'schema.table.column'.
"""
D = {}

def t(table, **cols):
    for c, text in cols.items():
        D[f"{table}.{c}"] = text

# ---- analytics (star schema) -------------------------------------------------------------------------------------------
t("analytics.dim_candidate",
  candidate_key="Surrogate key of this version of the candidate (Type 2): a candidate whose city or experience changes gets a new key.",
  candidate_profile_id="Id of the candidate in profile.candidate_profile, shared by every version of the candidate.",
  current_city_name="City of the candidate's current location in this version. NULL when no current location is recorded.",
  primary_skill_name="Name of the candidate's primary skill in this version. NULL when the candidate has listed no skill.",
  valid_from="Start of the period in which this version was current.",
  valid_to="End of the period in which this version was current. NULL for the current version.")
t("analytics.dim_date",
  date_key="Calendar day as the integer YYYYMMDD (for example 20261028); the key facts join to.",
  day_of_month="Day of the month, 1 to 31.", day_name="English name of the weekday, padded by the database to nine characters.",
  day_of_week="ISO weekday, 1 (Monday) to 7 (Sunday).", month_number="Month of the year, 1 to 12.",
  month_name="English name of the month, padded by the database.", quarter_number="Calendar quarter, 1 to 4.", year_number="Calendar year.")
t("analytics.dim_job_posting",
  job_posting_key="Surrogate key of the job in the star schema.", job_posting_id="Id of the job in recruitment.job_posting.",
  job_title="Title of the job as last loaded (Type 1: the latest value wins).", job_role_name="Name of the job's role. NULL when the job has no role.",
  industry_name="Name of the job's industry. NULL when the job has none.", employment_type_code="Employment type code (for example full_time). NULL when the job has none.",
  work_type_code="Work arrangement code (on_site, remote, hybrid). NULL when the job has none.",
  salary_min="Lowest salary offered, in currency_code. NULL when the job discloses no salary.", salary_max="Highest salary offered, in currency_code. NULL when the job discloses no salary.")
t("analytics.dim_organization",
  organization_key="Surrogate key of this version of the organisation (Type 2).", organization_id="Id of the organisation in recruitment.organization, shared by every version.",
  organization_name="Name in this version.", organization_type="Type in this version (for example employer, agency).",
  country_code="ISO 3166 alpha-3 code of the organisation's country. NULL when no country is recorded.",
  industry_name="The industry in which the organisation posts most jobs. NULL when it has posted none with an industry.",
  valid_from="Start of the period in which this version was current.", valid_to="End of the period in which this version was current. NULL for the current version.")
t("analytics.fact_application_event",
  candidate_application_id="Application the event belongs to (recruitment.candidate_application).",
  previous_status="Status the application left. NULL for the first event, when it was created.", new_status="Status the application entered.",
  event_timestamp="When the status change happened (UTC).")
t("analytics.fact_gig_performance",
  gig_assignment_id="Finished assignment this row summarises (gig.gig_assignment).", agreed_amount="Price agreed for the assignment, in currency_code.",
  actual_reconciled_earnings="Earnings the fulfilment system reported, in currency_code. 0 when none have been reconciled.",
  client_rating="Requester's overall rating, 1 to 5. NULL when the assignment was not rated.", assignment_status="Final status of the assignment: completed or terminated.")
t("analytics.fact_wallet_transaction",
  wallet_id="Wallet the entry belongs to (commercial.wallet).", entry_type="credit, debit, correction_credit or correction_debit.",
  amount="Amount of the entry, always positive, in currency_code; entry_type gives the direction.", reference_type="What the entry paid for or came from (recharge, profile_download, ...).",
  recorded_timestamp="When the entry was written to the ledger (UTC).")
# ---- audit -------------------------------------------------------------------------------------------------------------
t("audit.action_catalogue", sensitive_class="Which of the 14 sensitive action classes this action evidences (docs/phase-1-discover/05-audit-event-matrix.md).",
  description="What the action means, in one line.")
t("audit.audit_event", entity_schema="Schema of the table the action concerned.", entity_name="Table the action concerned.",
  entity_id="Primary key of the row the action concerned. NULL for actions with no row, such as a failed login.",
  client_ip="Address the request came from. NULL for actions not made through a request. Personal data.",
  user_agent="Client software string. NULL when not available. Personal data.")
t("audit.column_classification", schema_name="Schema of the classified column.", table_name="Table of the classified column.", column_name="The classified column.")
t("audit.entity_lifecycle_policy", schema_name="Schema of the table this policy describes.", table_name="Table this policy describes.",
  retention_basis="Why the retention period is what it is. NULL when no retention limit is set.")
t("audit.maintenance_run", job_name="Which scheduled job ran: refresh_marts, purge_expired_data, erase_inactive_accounts or backup_restore_check.")
t("audit.system_error_log", error_code="Short stable code for the kind of error, for example INTEGRATION_DEAD_LETTER.", error_message="What went wrong, in words.",
  stack_trace="Stack trace when the error came from application code. NULL for errors raised inside the database.")
# ---- commercial --------------------------------------------------------------------------------------------------------
t("commercial.candidate_profile_download_history", credit_deduction_amount="Credit charged for this download, in currency_code. 0 when the download was free (for example within a plan quota).")
t("commercial.invoice", invoice_number="Human-readable invoice number, unique, issued in sequence per organisation.", subtotal_amount="Amount before tax, in currency_code.",
  tax_amount="Tax charged, in currency_code. 0 when the sale is untaxed.", total_amount="Subtotal plus tax, in currency_code. A CHECK enforces the sum.")
t("commercial.payment_order", gateway_provider="Payment gateway that handled the order (for example razorpay, stripe).",
  gateway_order_id="The gateway's reference for the order. A reference only: no card or bank data is stored. Sensitive.", order_amount="Amount to be charged, in currency_code.")
t("commercial.payment_refund", refund_amount="Amount returned to the payer, in currency_code.", gateway_refund_ref="The gateway's reference for the refund. Sensitive.",
  refund_reason="Why the refund was made, in words. NULL when none was given.", refund_status="Status of the refund at the gateway (for example processed, pending, failed).")
t("commercial.subscription", period_start="Start of the paid period (inclusive).", period_end="End of the paid period (exclusive). Active periods of one licence may not overlap.",
  auto_renew="True when the subscription renews itself at period_end unless cancelled.", cancellation_reason="Why it was cancelled. NULL unless the subscription was cancelled.")
t("commercial.subscription_licence", licence_key="The licence's unique key, shown to the customer. Sensitive in the sense of a credential; kept out of the audit log.",
  licence_name="Product name on the licence.", max_users="Seats: the most users who may hold a seat at once. A positive integer.",
  max_devices_per_user="The most devices one user may be logged in on at once. A positive integer; the login function enforces it.",
  valid_from="Start of the licence (inclusive).", valid_to="End of the licence (inclusive of the instant; not before valid_from).")
t("commercial.subscription_plan", plan_code="Stable code of the plan, unique.", name="Plan name shown to customers.", price_amount="Price per billing interval, in currency_code.",
  job_postings_quota="Job postings included per period.", profile_downloads_quota="Profile downloads included per period.", outreach_credits_quota="Outreach messages included per period.")
t("commercial.wallet", balance="Current credit, in currency_code, never negative. Must equal balance_after of the latest ledger entry; the reconciliation KPI (KPI-007) checks it.")
t("commercial.wallet_ledger", amount="Amount of this entry, always positive, in currency_code; entry_type gives the direction.",
  balance_after="Wallet balance immediately after this entry, never negative.", reference_id="Id of the thing the entry paid for (for example the payment order). NULL when there is none, such as a correction.",
  notes="Free-text note. NULL when none.")
# ---- core --------------------------------------------------------------------------------------------------------------
t("core.consent_record", consent_version="Version of the terms or policy the user responded to.", client_ip="Address the consent was given from. NULL when not captured. Personal data.",
  user_agent="Client software the consent was given from. NULL when not captured. Personal data.")
t("core.permission", name="Short name shown to administrators.", module="Area of the platform the permission belongs to.", description="What the permission allows. NULL when the name says it all.")
t("core.role", name="Role name, for example candidate, recruiter, admin.", description="What the role is for. NULL when the name says it all.")
t("core.user_account", phone_country_code="ISO 3166 alpha-2 country of the phone number. NULL exactly when phone_e164 is NULL (a CHECK keeps the pair together).",
  preferred_language="Language code for the interface (for example en, hi); falls back to en when untranslated.")
t("core.user_block", block_reason="Why the block was made, in the blocker's words. NULL when none was given.")
t("core.user_credential", credential_identifier="What the user types to authenticate: the email for a password, a key id for an API key. Personal data; kept out of the audit log.",
  algorithm="Hashing algorithm of secret_hash, for example argon2id. A CHECK on the hash itself enforces an approved format.")
t("core.user_device", device_identifier="Identifier the client generated for the device. Personal data.", device_name="Name the user gave the device. NULL when not given.",
  operating_system="Operating system reported by the client. NULL when not reported.")
t("core.user_session", device_identifier="Device the session runs on; counted against the licence's device limit while the session is open.")
# ---- gig ---------------------------------------------------------------------------------------------------------------
t("gig.gig_application", bid_amount="Price the worker offers, in currency_code.", pitch="The worker's proposal text. NULL when the worker applied without one.")
t("gig.gig_assignment", agreed_amount="Price agreed for the assignment, in currency_code.", external_handoff_ref="Reference to this assignment in the fulfilment system, which runs the work.",
  external_status="Status the fulfilment system last reported, as a string; reconciled into assignment_status.")
t("gig.gig_external_earnings", estimated_earnings="Earnings the fulfilment system estimated, in currency_code.", total_earnings="Earnings it reported as final, in currency_code. 0 until the work is finished.",
  projected_earnings="Earnings it projects by the end of the assignment, in currency_code.")
t("gig.gig_rating", rating_score="Overall rating from 1.00 to 5.00.", quality_score="Quality of work, 1.00 to 5.00. NULL when the requester gave only an overall score.",
  communication_score="Communication, 1.00 to 5.00. NULL when not scored.", review_text="Written review. NULL when the requester wrote none.")
t("gig.gig_request", title="Short title of the project.", description="What the project is.", deliverables="What the worker must hand over.", budget_amount="Budget in currency_code; pricing_type says whether it is a total, an hourly rate or a daily rate.")
t("gig.gig_worker_availability", available_from="First day the worker is available (inclusive).", available_to="Last day the worker is available (inclusive); not before available_from.")
t("gig.gig_worker_preference", reason="Why the organisation favourited or blacklisted the worker. NULL when no reason was given.")
t("gig.gig_worker_profile", headline="One-line professional headline.", bio="Longer self-description. NULL when the worker wrote none.",
  hourly_rate="Rate per hour in currency_code. NULL when the worker quotes no hourly rate.", daily_rate="Rate per day in currency_code. NULL when the worker quotes no daily rate.",
  total_completed_gigs="Count of assignments completed through the platform; maintained from finished assignments.", average_rating="Mean of the ratings received, 1.00 to 5.00. NULL until the first rating.")
t("gig.gig_worker_service", custom_title="The worker's own name for this service. NULL to use the skill's name.", rate_override="Rate for this service in currency_code, replacing the profile rate. NULL to use the profile rate.")
# ---- master ------------------------------------------------------------------------------------------------------------
for tbl, what in (("master.city", "City"), ("master.employment_type", "Employment type"), ("master.industry", "Industry"), ("master.job_role", "Job role"),
                  ("master.qualification", "Qualification"), ("master.skill", "Skill"), ("master.state", "State or province"), ("master.work_type", "Work arrangement"),
                  ("master.country", "Country"), ("master.language", "Language")):
    D[f"{tbl}.name"] = f"{what} name in English; the display name in other languages is a translation key in messaging.ui_translation."
t("master.country", iso_alpha2="ISO 3166-1 alpha-2 code (two capital letters).", iso_alpha3="ISO 3166-1 alpha-3 code (three capital letters).",
  phone_calling_code="International dialling code with a plus sign, for example +91. NULL when none is recorded.")
t("master.job_role", description="What the role does. NULL when the name is enough.")
t("master.language", native_name="The language's name in itself, for example Deutsch. NULL for languages whose native name has not been entered.")
t("master.skill", description="What the skill covers. NULL when the name is enough.")
t("master.state", subdivision_code="ISO 3166-2 subdivision code. NULL when the state has none.")
t("master.status_machine_exemption", entity_code="schema.table of the entity whose status column is exempt.", column_name="The exempt status column.", reason="Why no transition rules apply.")
t("master.status_transition", entity_code="schema.table of the entity the rule governs.", from_status="Status the row leaves.", to_status="Status the row may enter.")
# ---- messaging ---------------------------------------------------------------------------------------------------------
t("messaging.community_post", title="Post title.", content="Post body, in the language named by content_language_code.", topic="Topic the post is filed under (for example career, interviews).")
t("messaging.faq", category="Group the question is listed under.", question="The question as shown.", answer="The answer as shown.")
t("messaging.integration_boundary", name="Boundary name from docket section 6.", source_of_truth="Which system is authoritative for the data.", stored_data="What Talentra keeps.",
  referenced_data="What Talentra only points to and never copies.", failure_behaviour="What happens when the other side is down.", idempotency_rule="How a repeated message is recognised.",
  audit_rule="How the exchange is recorded.", max_attempts="How many times an exchange is tried before it becomes a dead letter.", base_backoff_seconds="Seconds before the second attempt; doubles for each further attempt.")
t("messaging.integration_event", event_type="Kind of exchange, for example payment.captured.", idempotency_key="Key that makes a replay of the same exchange a no-op, unique per boundary and direction.",
  entity_name="Table of the local row the exchange concerns. NULL when it concerns none.", entity_id="Id of that row. NULL when it concerns none.", attempts="Attempts made so far; at most the boundary's max_attempts.")
t("messaging.job_alert_preference", alert_name="Name the user gave the saved search.", keywords="Search words. NULL for a filter-only alert.", minimum_salary="Lowest salary the user wants, in currency_code. NULL for no minimum.")
t("messaging.notification_delivery", subject="Subject line. NULL for channels with none (SMS, push).", body_snippet="First part of the message, kept for audit only. NULL when not retained. Personal data.",
  external_provider_message_id="The provider's id for the message. NULL until the provider accepts it.")
t("messaging.notification_template", template_code="Stable code the application uses to pick the template.", default_language_code="Language the template is written in; other languages are translations.",
  subject_template="Subject with {{placeholders}}. NULL for channels with no subject.", body_template="Body with {{placeholders}}.")
t("messaging.referral_event", referred_email="Address the invitation went to. Personal data.", referral_code="Code in the invitation, unique.", reward_amount="Reward owed to the referrer, in currency_code. NULL until a reward is earned.")
t("messaging.support_ticket", ticket_number="Human-readable ticket number, unique.", category="Kind of problem (account, billing, technical, privacy, other).", subject="One-line summary written by the requester. Personal data.")
t("messaging.ui_translation", string_key="Key the interface asks for, for example btn.apply_job. Keys are never shown to users.", translated_text="The text in language_code.")
# ---- profile -----------------------------------------------------------------------------------------------------------
t("profile.candidate_assessment", title="Name of the test.", assessment_provider="Company that runs the test.", total_questions="Number of questions.", duration_minutes="Time allowed, in minutes.")
t("profile.candidate_assessment_score", score_obtained="Points the candidate scored, 0 to max_score.", max_score="Points available.")
t("profile.candidate_education", institution_name="School, college or university.", field_of_study="Subject studied. NULL when not stated.", grade_value="Grade achieved as written (for example 8.4 or First Class). NULL when not stated.",
  grade_scale="What grade_value is out of (for example 10 CGPA). NULL when not stated.", description="Extra detail the candidate added. NULL when none.")
t("profile.candidate_profile", headline="One-line headline shown in search results. NULL until the candidate writes one.")
t("profile.candidate_project", title="Project name.", candidate_role="The candidate's role in the project.", description="What the project was. NULL when not described.", outcome="What it achieved. NULL when not stated.")
t("profile.candidate_work_experience", employer_name="Employer as the candidate wrote it; not linked to an organisation.", job_title="Title held.", description="Responsibilities and achievements. NULL when not described.")
t("profile.course", title="Course title.")
t("profile.profile_view_history", credit_deducted="Credit charged for the view, in the organisation's wallet currency. 0 when viewing was free.")
t("profile.recruiter_bookmark", notes="The recruiter's private note about the candidate. NULL when none.")
t("profile.resume_template", name="Template name shown in the resume builder.")
# ---- recruitment -------------------------------------------------------------------------------------------------------
t("recruitment.application_question_response", response_text="Answer to a text question. NULL for other question types.", numeric_response="Answer to a numeric question. NULL for other question types.",
  boolean_response="Answer to a yes/no question. NULL for other types, and for a yes/no question not yet answered.")
t("recruitment.application_status_history", change_reason="Why the stage changed, in the recruiter's words. NULL when none was given.")
t("recruitment.candidate_application", cover_letter="Text the candidate sent with the application. NULL when none. Personal data.")
t("recruitment.job_position", position_reference_code="The employer's code for this vacancy slot, unique within the job.")
t("recruitment.job_posting", title="Job title.", description="Full description, in the language named by description_language_code.", responsibilities="Duties. NULL when covered by the description.",
  qualifications="Required background. NULL when covered by the description.", workplace_location_text="Free-text place, used when no city is chosen. NULL when city_id says it.",
  application_deadline="Last moment applications are accepted. NULL for no deadline.")
t("recruitment.job_questionnaire", title="Name of the screening questionnaire.", instructions="Text shown above the questions. NULL when none.")
t("recruitment.job_questionnaire_question", question_text="The question as shown to the applicant.")
t("recruitment.organization", name="Legal or trading name.", description="About the organisation. NULL when none.", contact_email="Public contact address. NULL when none. Personal data in the case of sole traders.")
t("recruitment.organization_identifier", identifier_value="The registration or tax number, as the registry prints it. STORED IN CLEAR TEXT: Sensitive and an open risk (docs/phase-2-model/12-tax-id-security-design.md).")
t("recruitment.organization_location", location_name="Name of the site, for example Corporate HQ.", address_line1="First line of the address.", address_line2="Second line. NULL when there is none.",
  postal_code="Postal or ZIP code as written locally.", latitude="Degrees north, six decimals. NULL when not geocoded.", longitude="Degrees east, six decimals. NULL when not geocoded.")
t("recruitment.recruiter_client_mapping", effective_from="First day the recruiter acts for the client.", effective_to="Last day the recruiter acts for the client. NULL while the mapping is open-ended.")
# ---- sourcing ----------------------------------------------------------------------------------------------------------
t("sourcing.consultant_sourcing_request", proposal_notes="The consultant's pitch for taking the job. NULL when none.", decision_reason="Why the employer accepted or declined. NULL until decided, and when no reason was given.")
t("sourcing.job_consultant_policy", max_consultants="The most consultants who may work the job at once. NULL for no limit.", bounty_amount="Fee paid to the consultant for a hire, in currency_code. NULL when unpaid.",
  terms_and_conditions="Commercial terms for consultants. NULL when the standard terms apply.")
t("sourcing.outreach_batch", campaign_name="Internal name of the campaign.", subject="Subject line for channels that have one. NULL for SMS and in-app.", message_body="The message sent.",
  total_recipients="Number of recipients in the batch.", total_credits_deducted="Credit charged for the whole batch, in the organisation's wallet currency.")
t("sourcing.sourcing_submission", consultant_notes="The consultant's note about the candidate. NULL when none.", client_feedback="The employer's feedback to the consultant. NULL until given.")
# ---- the partitioned copy of candidate_application: same columns, same meaning ------------------------------------------
for c in ("candidate_profile_id", "job_posting_id", "application_status", "cover_letter", "application_source", "created_by_user_account_id", "updated_by_user_account_id"):
    D[f"recruitment.candidate_application_partitioned.{c}"] = None   # filled from candidate_application by the builder
D["recruitment.candidate_application_partitioned.candidate_document_id"] = "Document (profile.candidate_document) the candidate attached as their resume. NULL when the application was made with the profile alone."

# ---- nullable columns whose generic text said nothing: say why each is optional --------------------------------------------
D["core.user_account.phone_e164"] = "Phone number in E.164 format with country code, for example +919812345678. NULL until the user adds one; sign-up needs only an email."
D["profile.candidate_skill.proficiency_level"] = "Self-assessed level: beginner, intermediate, advanced or expert. NULL when the candidate listed the skill without rating it."
D["profile.candidate_skill.experience_years"] = "Years of experience with the skill, decimals allowed. NULL when the candidate did not say."
D["profile.candidate_education.start_date"] = "Date the course started. NULL when the candidate gave only the year of completion."
D["profile.candidate_education.end_date"] = "Date the course ended. NULL while the candidate is still studying, or when not stated."
D["profile.candidate_work_experience.end_date"] = "Last day in the job. NULL while the candidate still works there (is_current is true)."
D["recruitment.organization.website_url"] = "Absolute URL of the organisation's website. NULL when it has none or has not given it."
D["recruitment.organization.contact_phone_e164"] = "Contact phone in E.164 format. NULL when the organisation gave only an email."
D["recruitment.job_posting.currency_code"] = "ISO 4217 currency of salary_min and salary_max. NULL exactly when the job discloses no salary (a CHECK keeps salary, currency and period together)."
D["recruitment.job_posting.salary_period"] = "Period the salary covers: hour, day, week, month or year. NULL exactly when the job discloses no salary."
D["recruitment.job_posting.minimum_experience_years"] = "Least experience, in years, the employer asks for. NULL when no minimum is stated."
D["recruitment.job_posting.maximum_experience_years"] = "Most experience, in years, the employer will consider. NULL when there is no ceiling."
D["recruitment.job_skill_requirement.minimum_proficiency_level"] = "Lowest acceptable level for the skill: beginner, intermediate, advanced or expert. NULL when any level will do."
D["recruitment.job_skill_requirement.minimum_experience_years"] = "Least years of experience with the skill. NULL when the job sets none."
D["recruitment.application_status_history.previous_status"] = "Stage the application left. NULL on the first history row, written when the application is created."
D["master.language.native_name"] = "The language's name in itself, for example Deutsch. NULL for languages whose native name has not been entered."
D["profile.candidate_project.start_date"] = "Date the project started. NULL when the candidate gave no dates."
D["profile.candidate_project.end_date"] = "Date the project ended. NULL while it is ongoing, or when no dates were given."
D["profile.candidate_project.project_url"] = "Absolute URL of the project (repository, demo, publication). NULL when none is public."
D["profile.candidate_assessment_score.percentile"] = "Rank among all takers, 0 to 100. NULL until the provider reports it."
D["recruitment.job_questionnaire_question.options_json"] = "JSON array of the choices for a multiple-choice question. NULL for free-text, numeric and yes/no questions."
D["recruitment.application_question_response.selected_options_json"] = "JSON array of the choices the applicant ticked. NULL for questions that are not multiple choice."
D["audit.audit_event.old_values_json"] = "Row as it was before the change, secrets removed. NULL for events that create or only observe (a login, an insert)."
D["audit.audit_event.new_values_json"] = "Row as it is after the change, secrets removed. NULL for events that delete or only observe."
D["audit.system_error_log.context_json"] = "Structured detail of the error (ids, parameters), no personal data. NULL when the message says everything."
D["gig.gig_application.proposed_duration_days"] = "Days the worker expects the work to take. NULL when the worker gave no estimate."
D["gig.gig_external_earnings.external_sync_hash"] = "Hash of the payload last received from the fulfilment system, used to skip unchanged updates. NULL until the first sync."
D["sourcing.job_consultant_policy.currency_code"] = "ISO 4217 currency of bounty_amount. NULL when no bounty currency is given; it should be set whenever bounty_amount is."
D["analytics.dim_candidate.total_experience_years"] = "Total years of work experience in this version of the candidate. NULL when the candidate recorded none."
D["analytics.dim_candidate.profile_completeness_percentage"] = "Profile completeness, 0 to 100, in this version. NULL when it has not been computed."
D["analytics.dim_job_posting.currency_code"] = "ISO 4217 currency of salary_min and salary_max. NULL when the job discloses no salary."
D["analytics.fact_application_event.status_cycle_time_hours"] = "Hours the application spent in previous_status. NULL for the first event, which has no previous status."
D["profile.candidate_document.original_filename"] = "File name as uploaded, 1 to 255 characters, never '.' or '..' and without a slash or backslash. Personal data."
