# NAS engagement: context and plan (reminder file)

Last updated: 30 Oct 2026. Paste or attach this file at the start of a new chat.

## 1. Engagement

- **Client:** National Autistic Society (NAS). Contacts: Alexander (Head of Data, AI and Development), Ben (Transformation Manager), Hannah (engaged me via recruiter).
- **Me:** Lindian, independent Snowflake consultant. No prior Dynamics experience.
- **Duration:** to 11 Nov 2026 (draft email said 12 Nov; verify against the contract).
- **Contract scope (assessment only):**
  1. Establish the current state of the Snowflake, MDM and ADF implementation.
  2. Identify the work completed and still required for the Dynamics migration.
  3. Confirm the technical boundary between NAS integration work and Dynamics-side activities.
  4. Assess complexity, dependencies, risks and delivery sequence.
  5. Produce an indicative estimate in person-days and elapsed time.
  6. Identify tasks that can run in parallel.
  7. Consider whether AI can speed things up.
- **The contract does not mention building the migration.** Do not take on build work without written agreement.
- **Goal:** deliver an excellent, evidence-based assessment plus detailed specifications, to make a credible case for being awarded the migration work afterwards (a separate proposal). Specifications describe the remaining work and acceptance criteria. They are not an agreement to build it.

## 2. Background

- Flow: Raisers Edge (legacy CRM) -> ADF -> Snowflake -> MDM/golden records -> HubSpot (marketing) and Dynamics 365 (core CRM). Snowflake stays as the integration layer after Raisers Edge is retired.
- HubSpot migration and the MDM were done by an incumbent partner on fixed deliverables. The partner has quoted a large additional sum for the final Dynamics stage; NAS wants an independent view.
- Mapping is done: about "2,000 tables" mapped into about "36 objects" (meaning to be clarified). Dynamics go-live is planned for Q1 next year.
- Dynamics partner (Emma Hunt per the transcript) supplies a landing zone/API. NAS pushes data to it.

## 3. What the code shows (workspace `c:\NAS CODE`)

- Databases: `AUDIT_DB`, `INTEGRATION_DB`, `MDM_DB`, `RAISERS_EDGE`.
- Dynamics layer (`INTEGRATION_DB\DYNAMICS`): `DT_D365_CONTACT_PAYLOAD`, `DT_D365_ACCOUNT_PAYLOAD` (dynamic tables, 1-hour lag), `VW_D365_REQUESTS` (builds POST/PATCH requests, uses `D365_WRITEBACK_STATE`, 2,000 rows per entity per run), `VW_D365_ACCOUNT`.
- `MDM_DB.GOLD.VW_GOLDEN_RECORD_IDS` holds per-platform IDs from `XREF` (D365 contact/account IDs by `STANDARDISED_ID` prefix).
- Only **Contact and Account** are implemented, against about 36 objects in scope. This is the central gap.
- Workspace `SP_XREF_CAPTURE*` procedures have empty bodies (`AS ''`). Check the deployed versions with `GET_DDL`; it may be an export artefact.
- `GOLDEN_RECORDS` is a person/organisation model, so gifts, events and other entities probably need new structures. Confirm against the mapping document.
- Existing code is not evidence of deployment or completeness. Mark each item as working/evidenced, present but unverified, incomplete, dependent on others, or out of scope.

## 4. Decisions and facts established

- **Environments:** DEV/TEST/PROD exist. TEST and PROD are **separate Snowflake accounts**, so access, roles and comparisons are per account. Compare environments by extracted DDL, and compare against a repo once one exists.
- **Azure DevOps:** no access yet. Until then, Snowflake is the source of truth (record this as a finding). Ask whether the repo is the source of truth and how code is deployed between accounts.
- **Role:** currently ACCOUNTADMIN. Want to drop it and use a least-privilege role. Plan: `NAS_DEV_READONLY` (default, read-only incl. definitions) and optionally `NAS_DEV_ENGINEER` (DEV only). Ask the admin to remove the ACCOUNTADMIN grant, not just change the default. Procedure/function source may need separate handling.
- **PROD access:** request read-only, metadata-only (definitions, row counts, run history; no donor data). Reason: contract requires the current state, and PROD shows what is actually live and any drift from TEST. If refused, ask NAS for exports and note lower certainty in the report.
- **Local code and Copilot:** ask NAS openly for permission to keep code locally and use GitHub Copilot (the contract's "consider whether AI can speed things up" supports this). Follow their data-handling rules.
- **Estimate so far:** mapping review 3-8, ADF test 3-5, ten test/UAT loads 5-10, cutover 2-4, missing entity mappings 2-5. Total is **15-32** person-days (earlier note said 31). HubSpot refresh 1-3 days is separate. Clarify whether "close missing mappings" means identify/size or implement. This estimate covers only part of the full migration.

## 5. Roadmap to 11 Nov (8 working days)

| Day | Date | Focus | Output |
|---|---|---|---|
| 1 | Fri 30 Oct | Confirm scope, access, contacts, environments; read SOW, architecture, mapping; catalogue code | Evidence list, access tracker |
| 2 | Mon 2 Nov | Trace Contact/Account flow end to end; ADF pipelines and run history | Current-state findings |
| 3 | Tue 3 Nov | Reconcile mapping vs code; define "2,000 tables"/"36 objects"; coverage matrix | Coverage matrix, gap list |
| 4 | Wed 4 Nov | Boundaries with Dynamics and incumbent partners; writeback, ID capture, retries | RACI, dependency register |
| 5 | Thu 5 Nov | Complexity and risks; environments, deployment, access | Risk register |
| 6 | Fri 6 Nov | Write specifications | Spec pack draft 1 |
| 7 | Mon 9 Nov | Estimate (person-days, elapsed), sequence, parallel plan | Estimate and plan |
| 8 | Tue 10 Nov | Review with Alexander and finalise | Final report and spec pack |
| Buffer | Wed 11 Nov | Walkthrough and handover | Presentation |

**Deliverables:** assessment report; estimate and plan; specification pack.

**Spec pack work packages:** environments/deployment/access; mapping closure; MDM extensions per entity; Snowflake payload/request layer; ADF orchestration, auth, errors, monitoring; ID capture and writeback state; reconciliation and data quality; test strategy, UAT and ten test loads; cutover and rollback; hypercare and handover. Each spec has objective, scope/exclusions, inputs/outputs, design (mappings, create vs update, retries), acceptance criteria and tests, dependencies/risks, and an estimate with assumptions.

**Good practice:** evidence over assertion; separate verified from assumed; independent honest estimate; versioned code and repeatable DEV -> TEST/UAT -> PROD promotion; idempotent, retry-safe loads; record-level logging and reconciliation; no secrets or personal data in notes.

## 6. Day 1 checklist and status

1. Email Alexander to confirm scope in writing (draft written; fix the date, remove "(if applicable)", add subject). **Not confirmed as sent.**
2. Create the access tracker (Item | Owner | Date requested | Status | Notes): SOW, architecture diagram, mapping document, Snowflake DEV/TEST (read-only), Snowflake PROD (read-only metadata), ADF each environment, Azure DevOps, Dynamics partner contact and API details, Dynamics test environment, written scope confirmation, permission for local code and Copilot.
3. Send the access-request email (second email, after scope confirmation).
4. Read the SOW, architecture and mapping documents; note entities in scope, promised vs built, open questions.
5. Catalogue the code: record which account `c:\NAS CODE` came from; inventory per object (Database | Schema | Object | Type | Purpose | Source | Status | Notes); flag Dynamics items and empty procedures.
6. Verify in Snowflake read-only (`SHOW`, `INFORMATION_SCHEMA`, `GET_DDL`). No CREATE/DROP; avoid personal data.
7. Write the Day 1 evidence list.
8. Send an end-of-day update to Alexander.

## 7. Open questions

- Correct end date (11 or 12 Nov)?
- Which Snowflake account is DEV, TEST, PROD? Is there a UAT?
- Does the Azure DevOps repo exist, and is it the source of truth?
- Meaning of "2,000 tables" and "36 objects"?
- Is the workspace export from DEV, TEST or PROD?
- Is local storage of code and Copilot use approved?
- Does the "close missing mappings" estimate line mean identify or implement?

## 8. Deliberately dropped

- Earlier requests for a full end-to-end migration roadmap were withdrawn. The contract is assessment only.
