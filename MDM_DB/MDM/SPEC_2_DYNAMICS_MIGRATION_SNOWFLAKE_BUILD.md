# Specification 2: Snowflake Build for the Dynamics Migration and Sync (up to the ADF hand-off)

Status: DRAFT for discussion. Companion to [RAISERS_EDGE_REMOVAL_SPEC.md](./RAISERS_EDGE_REMOVAL_SPEC.md) (Spec 1).
Scope note: the contract is assessment-only. This describes the work and how to meet the requirements; it is not a commitment to build.

Evidence labels: **[Code]** seen in the SQL exports, **[Talk]** stated in `Nas_Talks.txt`, **[Map]** seen in the mapping workbook `NAS DM Source to Target Mappings Current WIP 1.xlsx`, **[Assumed]** my inference, **[Verify live]** needs Snowflake access.

---

## 1. Purpose and boundary

**Spec 1** covers taking Raisers Edge (RE) out of the daily MDM chain.
**Spec 2 (this document)** covers everything Snowflake must do so that the Dynamics 365 data is correct and ready to be delivered: from the RE raw data through standardisation, MDM, mapping and payload building, **up to the point where ADF picks the payloads up**.

| In scope | Out of scope |
|----------|--------------|
| RAW layer for RE and Dynamics | ADF pipelines, triggers, linked services, monitoring |
| Standardise, match, golden record (existing task chain, see the processing diagram) | The Dynamics landing zone / API itself (Dynamics partner) |
| Mapping RE → Dynamics fields, reference/lookup data | HubSpot refresh |
| Payload views / dynamic tables, load gates, write-back state tables | Dynamics-side configuration and plug-ins |
| Data quality, reconciliation, Snowflake security and deployment | |

**Hand-off contract with ADF (the "up until ADF" line):** Snowflake exposes, per Dynamics entity, a ready-to-send set of rows (request type POST/PATCH, key, JSON body, hold reason, batch size) and accepts a result row back (success / failure / returned Dynamics ID). ADF only moves that data. [Code] `VW_D365_REQUESTS` already works this way (POST/PATCH requests, 2,000-row cap per entity per dispatch, `AUDIT_DB.MONITORING.D365_WRITEBACK_STATE`, pipeline `D365_WRITEBACK`).

## 2. Two flows, not one

The mapping workbook shows the data splits into two different jobs. They need different designs. [Map][Talk]

| | Flow A: Supporters (people, organisations) | Flow B: Transactional and reference data |
|---|---|---|
| Entities | Contact, Organisation (Account), Address, Consent, Relationship, Title, Connection | Transaction, Transaction Line, Payment Schedule, Direct Debit, Event, Event Participant, Membership, Tax Declaration, Restriction, Donor Commitment, Appeal, Package, Campaign, Designation |
| Needs MDM (matching and golden record)? | **Yes** | **No**; must carry the golden/Dynamics supporter ID as its foreign key |
| Run pattern | Daily, ongoing, after go-live | One-off migration (trial loads, fixes, final delta), then static |
| Existing code | MDM chain; `SP_ETL_DYNAMICS`; `DT_D365_ACCOUNT/CONTACT_PAYLOAD`; `VW_D365_ACCOUNT/CONTACT` | DEV only: `VW_D365_MSNFP_EVENT/APPEAL/PACKAGE/DESIGNATION`, `VW_D365_CAMPAIGN`, REF views and `VW_D365_REF_LOAD_GATE` [Code] |
| Main risk | Identity (see Spec 1, section 5.2) | Missing source mappings and rules |

Flow B depends on Flow A: a gift cannot be loaded until its supporter exists in Dynamics. That dependency drives the load order (section 6).

## 3. Starting position

### 3.1 What exists [Code]
- Three-task MDM chain, identical in DEV/TEST/PROD, producing golden records.
- DEV only (not in TEST/PROD exports): 24 Dynamics views, 2 payload dynamic tables, a central **load gate** list (`VW_D365_REF_LOAD_GATE`: open items that hold rows back with `HOLD_REASON = GATE:<code>`), reference-data views (gift type, schedule status, pledge status, tribute type, consent rule and others), and a "Proof Staging Done" check extract.
- **Raisers Edge ingest [Verified: `PIPELINE_METADATA` extract, DEV]:** ADF (black box) copies 72 SQL Server tables (`T_<Name>`) in full into `RAISERS_EDGE.STG_T_<NAME>`. All 72 are enabled. The Blackbaud API is used only for write-back (6 `VIEW` rows); 2 more `VIEW` rows target the Dynamics API. The pipelines, schedule and run results have not been seen.
- **Raw layer [Verified: `GET_DDL`, DEV]:** the code reads `RAW.RAISERS_EDGE.VW_ODS_T_*`, a thin view over `RAW_PROD.RAISERS_EDGE.ODS_T_*` with `WHERE NOT IS_DELETED`. **How `ODS_T_*` is written is not known** (probably from `STG_T_*`; not proven). **Assumed for now:** DEV's view layer reads PROD-named raw data, so DEV and PROD are not cleanly separated **[Verify live]**.
- **Two existing routes into Dynamics [Code]:** (a) via the MDM (`VW_ODS_T_*` to standardise, match and golden record); `SP_ETL_DYNAMICS` is switched off. (b) Direct build: the 24 DEV `VW_D365_*` views read `VW_ODS_T_*`; CONTACT and ACCOUNT feed two payload dynamic tables keyed on `GOLDEN_RECORD_ID`, then `VW_D365_REQUESTS` (the ADF hand-off view, matched to the `D365_WRITEBACK` metadata rows). The payloads therefore still depend on MDM golden IDs. Only CONTACT and ACCOUNT exist; Flow B entities (gifts, events, memberships, tax) have no payloads yet.
- `RAW.RAISERS_EDGE` in the export holds only `RE_REQUESTS` (outbound requests) and 15 `VW_RE_*` enrichment views. The `STG_`, `ODS_` and `VW_ODS_` definitions are not in the exports.
- `SP_ETL_DYNAMICS` exported but not called; known issue blocks it.

### 3.2 What the mapping workbook says is outstanding [Map]
Figures are from a quick profile; treat as approximate.
- About 3,985 field rows over 81 Dynamics entities; only **463 are marked required** for migration.
- Of the 463 required fields, about **259 (56%) have a source** filled in and **about 204 do not**.
- Business logic is written for roughly 72 rows; roughly 806 rows are marked reviewed; roughly 149 have a DevOps ticket.
- Largest gaps (required fields / with a source): Transaction 35/16, Event Participant 34/10, Enquiry 22/5, Tax Declaration 14/1, Membership 14/1, Donor Commitment 12/5, Transaction Line 11/5.
- Contact (73/63) and Organisation (26/24) are the most complete.
- "Cut off criteria" (what makes a contact or organisation active, and how many years back) is **blank**. It decides how much data moves.
- "Gift Splits Challenge" is an unresolved placeholder.
- The progress sheet and the row counts do not reconcile cleanly **[Verify with NAS]**.

## 4. Requirements and how each is met

| # | Requirement | How it is met in Snowflake |
|---|-------------|----------------------------|
| R1 | Every required Dynamics field has a defined source or an agreed default | Complete the mapping; load it into Snowflake as a table (section 5.1) so gaps are queryable and tested |
| R2 | People and organisations arrive in Dynamics de-duplicated, with stable IDs | Existing MDM chain, extended per Spec 1; Dynamics ID written back to XREF |
| R3 | Transactions, schedules, events and memberships link to the correct supporter | Resolve RE constituent ID to golden ID to Dynamics ID through the crosswalk before building payloads |
| R4 | Only in-scope records move | Cut-off rules (section 5.3) applied once, in one place |
| R5 | Rows with open questions are held, not guessed | Reuse the load-gate pattern for every entity |
| R6 | Reference/lookup values match Dynamics option sets | REF views fed from the lookup sheets (gift code, pay type); validated against Dynamics values |
| R7 | The load is repeatable and restartable | Idempotent payload views; state table records what was sent, result and Dynamics ID; retries pick up failures only |
| R8 | Results are provable | Reconciliation queries per entity (section 7) |
| R9 | Consistent across DEV, TEST and PROD | One deployment route (DLSync) and a check that all three match |
| R10 | Least-privilege access | Roles per layer; read-only role for reviewers; secrets only in ADF/Key Vault, never in Snowflake objects |

## 5. Work to be done (Snowflake side)

### 5.1 Make the mapping executable
1. Load the **Mapping V6** sheet (required rows) into `MDM_DB.MAPPING` tables: entity, field, RE source table/field, Snowflake source, business logic, status, ticket. Version it (V6 is current; V1-V5 are history only).
2. Generate a **gap report** from it: required fields with no source, no logic or not reviewed. This becomes the work list and the estimate driver.
3. Load the lookup sheets (Gift Code, Pay Type, Existing Gift Code Use) as reference tables feeding the REF views.
4. Agree who signs off each entity (the progress sheet has an owner and sign-off date column, mostly blank).

### 5.2 RAW and standardisation
- All 72 RE tables are already landed as `STG_T_*` and exposed as `VW_ODS_T_*`. About 32 are read by existing code; about 40 are loaded but unread, including TaxDeclarations, GiftAttributes, MembershipGifts, ProposalAttributes/Notes and EventParticipantFees/Prices. Match the mapping's RE source table names (written about 46 different ways) to these 72 before treating any field as "no source". Some of the ~204 gaps may close this way.
- Find and document how `ODS_T_*` is written (query history on `ODS_T_ACTIONATTRIBUTES`), and decide whether Flow B payloads read raw RE (route b) or golden records, because Flow A needs golden IDs **[Verify live]**.
- Entities still not found among the 72: bank/finance institution and gift amendments.
- Confirm the Dynamics RAW tables needed for ID lookups (`RAW.DYNAMICS.ODS_CONTACTS`, `ODS_ACCOUNTS` and any reference tables) exist and refresh.
- Add a freeze marker for RE (see Spec 1, config flags) so a static RE source is treated as complete, not deleted.

### 5.3 Cut-off rules (blocker)
- Obtain the decisions: years of inactivity, what "active" means for a contact and for an organisation, how deceased, opted-out and merged records are treated.
- Implement as one table-driven view (`VW_MIGRATION_SCOPE`) that every payload view joins. Changing a rule then needs one edit, not many.

### 5.4 Flow A: supporters
1. Apply Spec 1 (RE removal, identity crosswalk, source flags). Enable and validate `SP_ETL_DYNAMICS` after the known issue is fixed.
2. Ensure `DT_D365_CONTACT_PAYLOAD` and `DT_D365_ACCOUNT_PAYLOAD` exist in TEST/PROD, and refresh within the daily window.
3. Cover the remaining Supporters objects: Address (including address type and country alias REF views), Consent (consent rule REF), Relationship, Connection, Title, Exclusion, Postcode, Canvasser.
4. Write the Dynamics ID returned by ADF back to the XREF and the crosswalk, so every later flow can find the supporter.

### 5.5 Flow B: transactional and reference data
Build in this order, each with its own payload view, load gate and reconciliation:

| Order | Entity group | Notes from the mapping |
|-------|--------------|------------------------|
| 1 | Reference: Appeal, Package, Campaign, Designation, Income Type, Payment Type, Event Type/Category, Membership Category, Consent Type, Relationship Type, Title | Lookup data first; small; DEV views already exist for several |
| 2 | Event, Event Participant, Fundraising Page | Event views exist in DEV; participant has a large gap (34 required, 10 with source) |
| 3 | Payment Schedule, Direct Debit, Payment Method, Payment Schedule Line | Recurring giving; depends on supporter and payment type |
| 4 | Transaction, Transaction Line, Restriction, Tribute or Memory, Soft Credit | Largest gap; gift splits unresolved (Gift Splits Challenge); gift code mapping drives income type and payment processor |
| 5 | Tax Declaration and Tax Claim | Gift Aid window date in `VW_D365_REF_LOAD_GATE` is marked ASSUMED; owner must confirm |
| 6 | Membership, Donor Commitment (pledges, proposals), Enquiry/Opportunities | Low current source coverage |
| 7 | Historic Activity, Exclusion and other low-volume objects | Only if confirmed required |

Entities marked "Not Required" in the progress sheet (Lead, Consent Declaration, Journal, Journal Line, Transaction Adjustment and so on) are excluded and should be listed in the sign-off pack as out of scope.

### 5.6 Payload and hand-off layer
- One payload object per Dynamics entity with the same columns: entity, request type (POST/PATCH), natural key, Dynamics key (if known), JSON body, hold reason, batch id.
- Use dynamic tables only where refresh cost and lag are acceptable; otherwise views plus a staged snapshot per batch, so a re-run sends identical data.
- Extend the write-back state table to cover every entity, with attempt count, last error and returned Dynamics ID.
- Dispatch caps (2,000 rows per entity today) become configuration.
- Apply the payload size and rate limits the Dynamics partner confirms.

### 5.7 Data quality and observability
- Checks before payloads are released: required fields present, valid option-set values, foreign keys resolvable, no duplicate keys, length and format limits (the mapping sheet carries max lengths).
- Failures write to an exceptions table with a reason code, not silently drop rows.
- Row counts per run, per entity, per hold reason, into the audit database; alerting on the task chain.
- Resolve the gaps found earlier: the empty `SP_XREF_CAPTURE*` bodies, `SP_VALIDATE_MDM` not being in the chain **[Verify live]**.

### 5.8 Security and deployment
- Roles: service role for ADF (read payloads, write results only), engineering role, read-only review role (`NAS_DEV_READONLY`, requested), no use of ACCOUNTADMIN for run-time work.
- Network policy and IP allow-listing for the build engineer.
- All objects deployed by DLSync DEV → TEST → PROD; add the DEV-only Dynamics objects to the repository's TEST/PROD promotion plan (the promotion matrix shows 69 DEV paths absent from both).
- Environment parity check: object list and DDL comparison before every release.

## 6. Load sequence (data dependencies)

1. Reference and lookup data.
2. People and organisations (Flow A), with the Dynamics ID captured back.
3. Address, consent, relationships.
4. Events, then participants.
5. Payment schedules and direct debits.
6. Transactions and lines, then restrictions, tributes and soft credits.
7. Tax declarations.
8. Memberships, commitments, enquiries.
9. Final delta load at cut-over, then freeze.

Each step is released only when the previous step reconciles (section 7).

## 7. Testing and acceptance

| Test | Pass condition |
|------|----------------|
| Mapping completeness | 100% of required fields have a source, a default or a signed-off exclusion |
| Row reconciliation (per entity) | Source in-scope count = payload count = loaded count + held + exceptions |
| Financial reconciliation | Total gift value and count per year and fund equals RE, within a tolerance NAS agrees (proposal: 0 difference for posted gifts) |
| Referential integrity | Every transaction, schedule and participant resolves to a Dynamics supporter |
| Duplicate check | No supporter or key loaded twice; golden IDs stable (Spec 1, section 9) |
| Idempotency | A re-run sends no new POSTs for already-loaded rows |
| Sample review | NAS reviews a sample of records per entity in a Dynamics test environment |
| Dress rehearsal | Full load into a Dynamics test environment, timed, before cut-over |

## 8. Phasing

| Phase | Work | Output |
|-------|------|--------|
| 0 | Live verification (task state, DDL, missing objects); load mapping into Snowflake; gap report; cut-off decisions | Baseline and a costed gap list |
| 1 | Spec 1 changes; Flow A enabled in TEST; reference data | Supporters loadable and reconciled |
| 2 | Flow B in the order of section 5.5 | Each entity reconciled in TEST |
| 3 | Dress rehearsal; PROD deployment; final delta; freeze | Signed-off migration |
| 4 | Decommission RE feeds and old code (Spec 1, phase 3) | Clean steady state |

## 9. Estimate (rough; assessment-grade) [Assumed]

| Work package | Person-days |
|--------------|-------------|
| Mapping into Snowflake, gap report, cut-off rules | 3 – 5 |
| Reference data and lookup tables | 2 – 4 |
| Flow A completion (incl. Spec 1 items not counted there) | 3 – 6 |
| Flow B payloads: about 6 entity groups, 2 to 4 days each at current source coverage | 12 – 24 |
| Payload, state table and hand-off contract | 3 – 5 |
| Data quality, reconciliation, observability | 4 – 6 |
| Security, deployment promotion, parity checks | 2 – 4 |
| Dress rehearsal, cut-over support | 3 – 5 |
| **Total (this spec only)** | **32 – 59** |

- Spec 1 estimate (17 – 32 days) overlaps in the Flow A and identity areas. Combined, count the overlap once; likely combined total about 45 – 80 days.
- These are wider than my earlier 15 – 32 day figure because the workbook shows about half the required fields still lack a source. **If the gaps are closed by NAS or the partner first, the range falls towards the low end.**
- Parallelism: after Phase 0, Flow A and Flow B reference data can run in parallel with two engineers; Flow B entity groups are independent of each other once the supporter ID is available. Dynamics-side access is on the critical path.
- AI assistance (Cortex / CoCo) could speed payload view and JSON body generation from the mapping rows. No saving is assumed here; test it on one entity first (human-first, as NAS asked).

## 10. Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Mapping reported as done, but about half the required fields have no source | Scope and quote disagreement | Gap report agreed with NAS and the partner before any estimate is fixed |
| Cut-off criteria undecided | Volume, cost and test scope unknown | Decision from NAS (owner Alex) in Phase 0 |
| Gift splits and gift codes unresolved | Wrong income and payment values | Resolve with finance; hold rows with a gate until closed |
| Identity anchor lost in Spec 1 | Transactions linked to wrong supporter | Crosswalk and golden-ID stability test |
| DEV-only objects not promoted | TEST/PROD cannot run Dynamics flows | Promotion plan; parity check |
| Dynamics landing zone details unknown | Payload format rework | Early contract with the Dynamics partner |
| Gift Aid rule assumed | Tax claim errors | Owner confirmation, kept behind a gate |
| Dynamics documentation does not yet exist [Talk] | Building to a moving target | Treat the workbook plus the partner's confirmation as the spec; version both |

## 11. Open questions for NAS
1. What are the cut-off rules for contacts and organisations?
2. Who owns each entity's sign-off (finance for gifts, fundraising for events and membership)?
3. How are gift splits, soft credits and adjustments to be handled?
4. Is the mapping workbook the agreed source of truth, and who updates it?
5. What does the Dynamics landing zone accept (formats, limits, keys, error responses)?
6. Is there a Dynamics test environment for dress rehearsals, and when?
7. Which entities are phase 2 (one mapping row says "Professionals is for phase 2")?
8. Who builds Flow A, Flow B and the hand-off layer: NAS, the incumbent partner or another party?
