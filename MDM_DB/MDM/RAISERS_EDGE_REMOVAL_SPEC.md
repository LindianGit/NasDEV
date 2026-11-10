# Specification: Remove Raisers Edge (RE) Processing from MDM and Replace It With an Equivalent Source

Status: DRAFT for discussion. Supersedes the high-level note [POST_RAISERS_EDGE_MDM_DESIGN.md](./POST_RAISERS_EDGE_MDM_DESIGN.md).
Scope note: the contract is assessment-only. This is a description of the work and its acceptance criteria, not a commitment to build.

Evidence labels used throughout:
- **[Code]** seen in the exported SQL files (DEV/TEST/PROD folders)
- **[Talk]** stated by NAS in `Nas_Talks.txt` (Talk 1 / Talk 2)
- **[Assumed]** my inference, to be confirmed
- **[Verify live]** needs Snowflake / ADF access to confirm

---

## 1. Objective

Stop `SP_ETL_RAISERS_EDGE()` from being a live input to the MDM, and replace it with another source (or sources) so that the MDM still produces **the same golden records, the same cross-references (XREF) and the same downstream HubSpot / Dynamics payloads as before**.

"Same result as before" is defined as a measurable parity test (section 9), not a feeling.

## 2. What NAS said that shapes this spec [Talk]

| # | Statement | Implication |
|---|-----------|-------------|
| T1 | Flow is RE → ADF → Snowflake → MDM → HubSpot and Dynamics. Snowflake stays the integration layer after RE is retired. | The replacement must live in Snowflake; the task chain stays. |
| T2 | RE data was already migrated into HubSpot and "is being kept concurrent with Snowflake", synced back to RE by the ETL. Donor, donation and event objects are already in HubSpot. | HubSpot is the natural stand-in for RE attributes. |
| T3 | At Dynamics go-live (Q1 next year) the legacy CRM "will be a static data set". | RE stops changing. It becomes a frozen history, not a live feed. |
| T4 | The MDM "currently works for HubSpot"; a "huge additional number of tables" for Dynamics must be built into the MDM layer. | Dynamics must be added as an MDM source; `SP_ETL_DYNAMICS` is the starting point. |
| T5 | Mapping RE → Dynamics is done (about 2,000 tables, about 36 objects). | Field mapping exists outside the repo; it must be reused, not redone. |
| T6 | Dynamics is reached through a landing zone/API; Snowflake pushes. | Write-back and ID capture are the integration points. |
| T7 | RE "is the golden layer … when we decommission it, [Snowflake] will make sure HubSpot and Dynamics remain in alignment." | After RE goes, the golden ID and XREF in Snowflake become the system of record for identity. |
| T8 | NAS hopes to "close out the MDM with the existing partner as a bare minimum". | Who builds this is undecided; the spec must be partner-neutral. |
| T9 | Human-first estimate wanted; Snowflake CoCo/Cortex may speed payload building. | Estimate gives a manual figure and an AI-assist saving separately. |

**Important tension to resolve with NAS:** T7 describes RE as the golden layer that is later removed, while the MDM matches on RE constituent IDs today. Removing RE therefore removes an *identity anchor*, not just a data feed. That is the main risk in this spec.

## 3. Current state being replaced [Code]

### 3.1 Task chain (identical in DEV/TEST/PROD)
`TK_STANDARDISE_RECORDS` (06:00 UTC) → `TK_BUILD_MATCH_GROUPS` → `TK_GENERATE_GOLDEN_RECORDS`.

### 3.2 Where RE is used

| Area | Object | RE dependency |
|------|--------|---------------|
| Ingest | `SP_STANDARDISE_RECORDS` | Calls `SP_ETL_RAISERS_EDGE()` then `SP_ETL_HUBSPOT()`. `SP_ETL_DYNAMICS()` is commented out ("disabled until known-issue fixed and validated in TEST"). |
| Ingest | `SP_ETL_RAISERS_EDGE` | Reads `RAW.RAISERS_EDGE.VW_ODS_T_*` (constituent, addresses, emails, phones, constituent addresses, types, attributes, solicit codes, gifts). MERGEs into `STANDARDISED_RECORDS` as `RE-<CONSTITUENT_ID>`, source `RAISERS_EDGE`, matched on `MD5_HASH`. |
| Match | `SP_BUILD_MATCH_GROUPS` | `exact_re_constituent_id` and `exact_re_constituent_id_org` link HubSpot records to `RE-` records (score 100, identity-grade, floor group at Pending Review). |
| Golden | `SP_GENERATE_GOLDEN_RECORDS` | Fuses RE records with HubSpot ones; recency-only survivorship; XREF `LINKED_BY` includes `RE_WRITEBACK`. |
| Validate | `SP_VALIDATE_MDM` | RE-specific counts (`v_re_total`, `v_re_matched`, `v_re_dup_xref`, `v_method_exact_re_constituent_id`). Not called by the tasks. |
| ID capture | `SP_XREF_CAPTURE*` | Bodies are empty in the exports **[Verify live]**. |
| Raw layer | `RAW.RAISERS_EDGE` | Landing is `STG_T_*` (72 tables, ADF full copy from SQL Server, verified from `PIPELINE_METADATA`). The code reads `VW_ODS_T_*`, a view over `RAW_PROD.RAISERS_EDGE.ODS_T_*` with `WHERE NOT IS_DELETED` (verified `GET_DDL`). How `ODS_T_*` is written is unknown; assumed for now that DEV reads PROD-named raw data. The export holds only `RE_REQUESTS` and 15 `VW_RE_*` views. |
| Dynamics views | `VW_D365_*` (24, DEV) | Also read `VW_ODS_T_*` directly, so removing or freezing RE affects the Dynamics migration views as well as the MDM. CONTACT and ACCOUNT payloads are keyed on `GOLDEN_RECORD_ID`. |

### 3.3 What RE contributes to a golden record
- Identity: name, DOB, title, constituent type, individual vs organisation.
- Contact: all emails, phones and addresses (as arrays plus primary values).
- Derived flags: four-year rule, major donor, politician, celebrity, in-memory, benevolent, corporate, NAS branch contact, PR case study, statutory authority, special eventer, trusts, legacy supporter.
- Attributes: licensed user type, work sector, job title, legacy intender / pledger / considerer / enquirer.
- Solicit codes (consent / contact preferences).
- Active / deceased state (soft-delete).

## 4. Key finding: HubSpot likely already carries most of this [Assumed, high value]

`SP_ETL_HUBSPOT` loads contacts (`HS-<OBJECTID>`) and companies (`HSC-<OBJECTID>`) and already reads the same attribute families as properties: legacy_* fields, `PROPERTY_N4_YEAR_RULE`, solicit codes, and `PROPERTY_CONSTITUENT_ID` (the RE ID held on the HubSpot record). Contacts with `PROPERTY_ADD_TO_RE = 'No'` are excluded.

So the replacement is mostly **"stop duplicating RE data that HubSpot already holds"**, plus covering the gaps below. This must be proven with a field-level coverage test (section 5.3) before any code is changed.

## 5. Replacement design

### 5.1 Source options

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A. Freeze RE | Keep `STANDARDISED_RECORDS` RE rows as a static snapshot; stop refreshing. | Lowest risk; matches T3; no result change at cut-over. | RE rows never update; RE is still a dependency for history; soft-delete logic must be disabled. |
| B. HubSpot as source | Drop RE rows; HubSpot supplies the attributes. | Simplest long-term; matches T2. | Only works where HubSpot has the field; ID anchor lost; records only in RE (no HubSpot contact) disappear. |
| C. Dynamics as source | Enable `SP_ETL_DYNAMICS` (`D365-<CONTACTID>`, `D365C-<ACCOUNTID>`). | Aligns with T4/T7; the end-state design. | Carries far fewer attributes (four-year rule and most flags are NULL today); blocked by the known issue; needs the Dynamics load to happen first. |
| D. Hybrid (recommended) | Phase 1 freeze RE (A); Phase 2 HubSpot + Dynamics sources live and validated; Phase 3 remove RE code and raw layer. | Lets parity be proven before anything is deleted; rollback is a flag. | Longest path. |

**Recommendation: D.** It is the only option where "same result as before" can be demonstrated at each step.

### 5.2 Identity replacement (the hard part)
- Today `exact_re_constituent_id` is the strongest link between HubSpot and RE.
- Replace with a **legacy-ID crosswalk** table (`MDM_DB.MDM.LEGACY_ID_XWALK`): `LEGACY_RE_ID`, `HUBSPOT_ID`, `D365_ID`, `GOLDEN_ID`, `SOURCE_OF_LINK`, `CREATED_AT`. Seed it from the current RE-linked match groups and from `XREF` (including `RE_WRITEBACK` rows).
- Re-point `SP_BUILD_MATCH_GROUPS` identity edges to: HubSpot `PROPERTY_CONSTITUENT_ID` ↔ Dynamics legacy-ID field (name to be confirmed from the mapping document) so the identity-grade rule survives without an `RE-` record.
- Golden IDs **must not change**. They carry forward via XREF (oldest `CREATED_AT` wins); no re-minting during cut-over.
- Decide the fate of `RE_WRITEBACK` / `SP_XREF_CAPTURE_RE_ID`: keep read-only history, stop writing.

### 5.3 Field-level coverage test (first deliverable)
For each target column in `STANDARDISED_RECORDS` (and each golden-record column), build this table from live data:

| Column | RE source | HubSpot source | Dynamics source | % populated: RE / HS / D365 | Gap action |
|--------|-----------|----------------|-----------------|------------------------------|-----------|

Gap actions: *map from HubSpot*, *map from Dynamics*, *derive*, *accept loss (sign-off)*, *backfill from frozen RE snapshot*. Any "accept loss" needs a named NAS owner.

## 6. Code changes

1. **`SP_STANDARDISE_RECORDS`**: add a config table `MDM_DB.STAGING.SOURCE_CONFIG (SOURCE_NAME, IS_ENABLED)` and call each ETL only if enabled. Default RE = on, so behaviour is unchanged until switched. (Avoids commenting code in and out, which is how Dynamics is parked today.)
2. **`SP_ETL_RAISERS_EDGE`**: when frozen (option A), skip the MERGE and the `NOT IN` soft-delete. Today an empty/static source would deactivate every RE record **[Code]**; this must be guarded first.
3. **`SP_ETL_DYNAMICS`**: fix and validate the known issue ("exact org name with no postcode check", doc `docs/known-issues/mdm-exact-org-name-no-postcode-check.md`, not in the export), then enable in DEV → TEST. Fill the NULL four-year-rule and flag columns from the Dynamics mapping.
4. **`SP_ETL_HUBSPOT`**: add any gap fields from 5.3; keep the `PROPERTY_ADD_TO_RE = 'No'` exclusion but rename/review its meaning once RE is gone.
5. **`SP_BUILD_MATCH_GROUPS`**: replace the two RE-ID methods (section 5.2); keep thresholds and frequency caps unchanged so scores stay comparable.
6. **`SP_GENERATE_GOLDEN_RECORDS`**: add a **source-priority rule** (today survivorship is recency-only). Needed because with RE frozen its `LAST_UPDATED` is always older, so HubSpot/Dynamics will always win; confirm that is the intended outcome. Update `SURVIVORSHIP_RULES` accordingly.
7. **`SP_VALIDATE_MDM`**: make RE counts conditional; add HubSpot/Dynamics equivalents; add it to the chain as a final task or a monitored step (currently not called).
8. **Dynamics write-back**: `VW_D365_REQUESTS` references the payload dynamic tables (`DT_D365_ACCOUNT_PAYLOAD`, `DT_D365_CONTACT_PAYLOAD`) that exist only in DEV **[Code]**. Confirm they exist in TEST/PROD **[Verify live]** before relying on write-back.
9. **Deployment**: all changes via DLSync DEV → TEST → PROD. The golden-record seed and code changes must land in the same deploy (existing code comment).
10. **Cleanup (Phase 3 only)**: drop `RAW.RAISERS_EDGE` views, `SP_ETL_RAISERS_EDGE`, RE branches in validation. Retain a frozen archive table of RE history.

Task chain: unchanged (three tasks, same schedule). No new task required unless validation is automated.

## 7. Dependencies outside Snowflake
- **ADF**: RE ingestion pipelines are paused only at the end of Phase 2; the Dynamics landing-zone/API pipelines must be running first **[Verify live]**.
- **Dynamics partner**: confirm the legacy-ID field and key names in the landing zone (T6).
- **RE → HubSpot sync (CTL)**: T2 says it stays concurrent with Snowflake. Its retirement date must be agreed; MDM must not lose HubSpot refreshes while RE is still the writer.
- **Azure DevOps / DLSync repo** access, not yet granted: needed to confirm deployed code matches the exports.

## 8. Phasing

| Phase | Content | Exit criterion |
|-------|---------|----------------|
| 0 | Live verification: `SHOW TASKS`, `GET_DDL` of the 3 tasks and ETL procs, empty `SP_XREF_CAPTURE*`, dynamic tables in TEST/PROD, task history. Capture baseline snapshot. | Baseline snapshot stored and reproducible. |
| 1 | Config flags, soft-delete guard, crosswalk table, field coverage test. Behaviour unchanged. | Parity test = 100% identical with flags at defaults. |
| 2 | Run RE-frozen and HubSpot/Dynamics path in parallel in TEST. | Parity thresholds (section 9) met for two consecutive daily runs. |
| 3 | Switch PROD flag; retire RE ADF pipelines; remove code after a cooling-off period. | Parity plus no production incident for an agreed period. |

Rollback at every phase before 3 is re-enabling the flag.

## 9. Acceptance criteria ("same result as before")

Baseline = golden-record, XREF and `STANDARDISED_RECORDS` snapshot taken at Phase 0 (zero-copy clone in the same account).

| Check | Threshold |
|-------|-----------|
| Golden ID stability: baseline golden IDs still present and mapped to the same member set | 100% (exceptions listed and signed off) |
| Golden record count vs baseline | within an agreed tolerance (proposal: ±0.5%) and every difference explained |
| Match group outcomes (Auto-Approved / Pending Review / Low Confidence) for baseline groups | ≥ 99% unchanged |
| Field values on golden records for the 4-year rule, flags and solicit codes | ≥ 99.5% identical or explained |
| Duplicate XREF (`v_re_dup_xref` equivalent) | 0 |
| Dynamics/HubSpot payload row counts per entity | equal to baseline ± records changed in source that day |
| No row unintentionally set `_IS_ACTIVE = FALSE` | 0 |

Thresholds are proposals for NAS to agree.

## 10. Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| RE-ID identity edge lost | Golden IDs split or merge incorrectly | Crosswalk seeded from baseline; golden-ID stability test. |
| Records exist only in RE, not HubSpot | Disappear from the MDM | Option D keeps the frozen snapshot; list and size them in Phase 0. |
| Static RE + recency-only survivorship | RE-only attributes lose to stale-but-newer values | Add source priority; sign-off on the rule. |
| Empty-source soft-delete | Mass deactivation | Guard in 6.2 before anything else. |
| Dynamics known issue unfixed | False merges on org names | Fix and validate in TEST first. |
| Exports differ from live (empty XREF procs, missing dynamic tables in TEST/PROD) | Wrong baseline | Phase 0 live verification. |
| Ownership undecided (T8) | Delay | Spec is partner-neutral; boundaries in section 12. |

## 11. Estimate (rough, assessment-grade) [Assumed]

| Work package | Person-days |
|--------------|-------------|
| Phase 0 verification and baseline | 2 – 3 |
| Field coverage test and gap decisions | 2 – 4 |
| Config flags, soft-delete guard, crosswalk, matching changes | 3 – 5 |
| Dynamics ETL enablement, known-issue fix, flag/attribute mapping | 4 – 8 |
| Survivorship and validation changes | 2 – 3 |
| Parallel-run, reconciliation, DEV→TEST→PROD deploys | 3 – 6 |
| Cut-over, cleanup, handover | 1 – 3 |
| **Total** | **17 – 32** |

Parallelism: coverage test, Dynamics ETL and validation work can run in parallel by two engineers after Phase 0; the identity/matching change and parallel run are serial. CoCo/Cortex could speed Dynamics payload/mapping code (T9) but is untested by the author, so no saving is assumed here.

## 12. Responsibilities (proposed)

| Item | Owner |
|------|-------|
| Business sign-off on field loss and parity thresholds | NAS (Alex) |
| Dynamics landing zone, legacy-ID field, API | Dynamics partner |
| Existing MDM/HubSpot behaviour and known issue | Incumbent partner |
| Snowflake build, tests, deploy | To be decided (T8) |
| Sequencing against Dynamics go-live | NAS (Ben) |

## 13. Open questions for NAS
1. Which fields do you consider mandatory for the golden record after RE is gone?
2. Is HubSpot expected to remain the system of record for the donor attributes, or does Dynamics take over?
3. When does the RE → HubSpot sync stop?
4. What is the Dynamics field that will hold the legacy RE ID?
5. Are RE-only constituents (no HubSpot record) expected to go to Dynamics?
6. Is the known-issue fix already built? Where is it tracked?
7. Is the three-task chain the only scheduler, or are ADF triggers also involved?
8. Who owns this build (T8)?
