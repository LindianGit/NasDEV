# NAS Current-State Assessment

## Snowflake, MDM and ADF

**Status:** Preliminary; based on local SQL and document exports  
**Assessment date:** 30 October 2026  
**Audience:** NAS project stakeholders

## Executive summary

The supplied files show a substantial Snowflake and MDM implementation, including source-specific staging procedures, matching and golden-record processing, and a Dynamics 365 integration layer. They are useful evidence of design and code, but they do not establish which definitions are deployed, enabled, current, or operating successfully.

The most important implementation concern visible in the TEST and PROD exports is that the standardisation procedure calls Raisers Edge and HubSpot ingestion but explicitly skips Dynamics ingestion. A Dynamics ETL procedure is present, but is commented out in the orchestration wrapper. This means the supplied code does not evidence an end-to-end MDM refresh from Dynamics.

The exported Dynamics layer includes Account and Contact mappings and a request view that builds POST/PATCH requests. The DEV export has additional entity/reference views and payload dynamic tables; these dynamic table definitions are not present in the TEST or PROD file exports, although the request view refers to them. This is an export/deployment reconciliation item, not proof that the objects are absent from the live accounts.

No Azure Data Factory pipeline definitions, linked-service configurations, trigger definitions, or run-history evidence were found in the supplied environment folders. ADF status therefore cannot be assessed from these files. The Snowflake metadata tables and procedures are not substitutes for ADF evidence.

**Overall conclusion:** the files support a preliminary code-based assessment, but not a verified live-state or go-live-readiness conclusion. The highest-priority follow-up is to verify the deployed Snowflake definitions and task history, establish the Dynamics MDM processing status, and obtain ADF configuration and monitoring evidence.

## Scope and evidence reviewed

Reviewed local files under `C:\NAS Dev`, `C:\NAS Test`, and `C:\NAS PROD`, including SQL definitions and the engagement context file. This was a static file review only; no Snowflake or Azure environment was queried.

The engagement context says the mapping covers approximately 36 objects and that TEST and PROD are separate Snowflake accounts. The mapping document itself was not among the reviewed files, so coverage against that scope and the account-to-folder mapping remain to be confirmed.

### Evidence status

- **Present in export:** the object definition or configuration appears in a supplied file.
- **Incomplete in export:** the supplied implementation explicitly omits or disables a step, or a required definition is not included.
- **Not evidenced:** the supplied files do not establish the capability or runtime status.
- **Requires live verification:** the export may be incomplete or may differ from deployed Snowflake.

## Findings

| Area | Current state indicated by supplied files | Status / confidence | Gap or implication |
|---|---|---|---|
| Snowflake object design | The DEV export contains AUDIT, INTEGRATION, MDM and RAW-related SQL assets. It includes configuration tables, Raisers Edge views, MDM procedures/tables, and Dynamics integration objects. | Present in export; deployment unverified. **Medium** for file contents, **low** for live state. | Confirm each environment's deployed DDL, dependencies, grants, and object status. |
| MDM source ingestion | TEST and PROD include procedures for Raisers Edge, HubSpot, and Dynamics ingestion. The `SP_STANDARDISE_RECORDS` wrapper calls the first two and explicitly comments out the Dynamics call. | Dynamics step incomplete in the supplied wrapper. **High** confidence in the captured code. | Confirm whether Dynamics ingestion is intentionally excluded, separately scheduled, or enabled in live Snowflake. Resolve the noted known issue and validate before enabling. |
| MDM processing | TEST and PROD define a task chain: standardise records on a daily 06:00 UTC schedule, then build match groups, then generate golden records. Matching and golden-record procedures are present in the exports. | Present in export; task enablement and successful runs unverified. **Medium**. | Check task state, run history, failures, row counts, and end-to-end reconciliation in each account. |
| Cross-reference capture | Three exported `SP_XREF_CAPTURE*` procedure definitions in TEST have empty bodies (`AS ''`). These procedures are important to recording source/Dynamics identifiers. | Potentially incomplete export; **high** confidence in file content, live implementation unknown. | Compare with deployed `GET_DDL` and test identifier capture. Do not conclude the live procedures are empty until verified. |
| Dynamics integration | TEST and PROD exports contain Account and Contact transformation views plus `VW_D365_REQUESTS`, which builds POST/PATCH requests and caps dispatch at 2,000 records per entity. The request view references payload dynamic tables and `AUDIT_DB.MONITORING.D365_WRITEBACK_STATE`. | Present in export; end-to-end dispatch and dependencies unverified. **Medium**. | Verify dynamic tables, state-table definitions, freshness, API invocation, response handling, retries, and writeback in live environments. |
| Dynamics breadth | DEV includes additional Dynamics entity/reference views and two payload dynamic-table definitions beyond the three Dynamics views in TEST/PROD. | Broader DEV export; deployment and functional completeness unverified. **Medium** for inventory. | Reconcile intended scope, object mappings, and promotion status. A view's existence alone does not demonstrate a complete tested migration entity. |
| ADF | No ADF pipeline JSON, linked services, datasets, triggers, or run logs were found in the supplied folders. | Not evidenced. **High** confidence about these folders only. | Obtain ADF exports and monitoring evidence; identify orchestration, authentication, retries, alerting, and source/target boundaries. |
| Object/mapping coverage | The context refers to approximately 36 Dynamics objects, but no mapping document or signed-off object-to-object coverage matrix was reviewed. | Not evidenced. | Compare each in-scope object and field to source, transformation, destination/API, and test evidence. |

## Environment inventory comparison

These are local file counts, not counts of live Snowflake objects.

| Folder | SQL files | Other files | Notable observation |
|---|---:|---:|---|
| `C:\NAS Dev` | 99 | 5 | Broadest export, including 24 Dynamics views, 2 Dynamics payload dynamic tables, and 15 Raisers Edge views. |
| `C:\NAS Test` | 30 | 1 | Smaller SQL export; includes 3 Dynamics views. |
| `C:\NAS PROD` | 31 | 0 | Same SQL paths as TEST plus `MDM_DB\Staging\Tables\STANDARDISED_RECORDS_20260715.sql`. |

All 30 TEST SQL paths are present in the PROD export. Three task definitions differ in their warehouse names (`WH_NAS_MDM_TEST` versus `WH_NAS_MDM_PROD`); the task schedule/dependency chain is otherwise consistent in the captured files. The dated PROD table is an additional file requiring explanation (for example, whether it is an intentional snapshot or a deployment artefact).

The DEV export has 69 SQL paths not present in TEST. This indicates the supplied DEV folder is materially broader; it does not, by itself, prove TEST is behind or PROD is missing those objects. Confirm the intended promotion baseline and compare live account definitions.

## Key risks and dependencies

1. **Dynamics processing gap:** the MDM wrapper in TEST/PROD skips Dynamics ingestion, so downstream golden-record and ID behavior for Dynamics requires explicit verification.
2. **Identifier capture uncertainty:** empty procedure bodies in the export could be a serious functional gap or an export artefact; deployed DDL and a controlled test are needed to distinguish these.
3. **Incomplete environment evidence:** the object inventories differ substantially, and the DEV export includes dependencies not represented in TEST/PROD files.
4. **ADF visibility gap:** without pipeline configuration and runtime history, orchestration, data movement, authentication, retry behavior, and operational monitoring cannot be assessed.
5. **Scope traceability gap:** without the mapping document and an object-level coverage matrix, completion against the stated Dynamics scope cannot be confirmed.

## Recommended evidence and next steps

1. Confirm which Snowflake account each local folder represents and whether the folders are complete, authoritative exports.
2. Obtain read-only metadata access or reproducible exports from DEV, TEST, and PROD. Compare deployed `GET_DDL` with the supplied files, including dependencies, grants, dynamic-table freshness, task state, and task history.
3. Verify the three XREF procedure definitions and test creation/update of source and Dynamics identifiers in a non-production environment.
4. Confirm the intended status of Dynamics ingestion in MDM, resolve the documented known issue, and establish acceptance tests before enabling it.
5. Obtain ADF pipeline, dataset, linked-service, integration-runtime, trigger, and monitoring/run-history exports. Redact secrets and personal data.
6. Obtain the source-to-Dynamics mapping and build a coverage matrix for every in-scope object, including transformation, MDM treatment, destination, dependencies, and test evidence.
7. Reconcile the dated PROD table and document a controlled DEV → TEST/UAT → PROD promotion process.

## Limitations

This assessment describes what the supplied files indicate; it is not confirmation of deployed or operational behavior. No live Snowflake metadata, task/run history, ADF configuration, Dynamics API logs, data-quality results,
 or migration mapping was reviewed. Findings marked as requiring live verification should not be represented as confirmed production defects until that verification is complete.


Thanks for reaching out.

Unfortunateely, I no longer deal with Indian companies regarding IT work. The reasons are.

1. They get me to sign a Right To Represent form while never giving me any feedback
2. The rates are always inside IR35
3. The rates are always below the market value

I suspect Indian recruiters obtain CVs, get a the Right To Represent signed, then don't bother putting you threw to the final client. Meanwhile, if you do go through another agency they will present the Right To Represent
form and block you, while putting in a resource of their own that is super cheap.

I have applied to more than 100 Indian recruiters and I have never once got any feedback from them.

Kind Regards,
Lindian Thomas   




Daily schedule: 06:00 UTC

TK_STANDARDISE_RECORDS
          |
          | runs after standardisation completes
          v
TK_BUILD_MATCH_GROUPS
          |
          | runs after match groups are built
          v
TK_GENERATE_GOLDEN_RECORDS

Execution order:
1. MDM_DB.STAGING.TK_STANDARDISE_RECORDS
2. MDM_DB.STAGING.TK_BUILD_MATCH_GROUPS
3. MDM_DB.STAGING.TK_GENERATE_GOLDEN_RECORDS

The downstream tasks are dependency-triggered by the preceding task.


MDM TASK PROCESSING - PLAIN-TEXT DIAGRAM
========================================

Scheduled daily at 06:00 UTC
Warehouse: WH_NAS_MDM_PROD (PROD task definitions)

  +--------------------------------------------------------------+
  | TK_STANDARDISE_RECORDS                                       |
  | Calls MDM_DB.STAGING.SP_STANDARDISE_RECORDS()                |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  | SP_STANDARDISE_RECORDS() - sequential source processing      |
  +------------------------------+-------------------------------+
                                 |
               +----------------+----------------+
               |                                 |
               v                                 v
  +---------------------------+    +----------------------------+
  | SP_ETL_RAISERS_EDGE()     |    | SP_ETL_HUBSPOT()           |
  | Reads RAW.RAISERS_EDGE    |    | Reads RAW.HUBSPOT          |
  | ODS views                 |    | contacts and companies     |
  |                           |    |                            |
  | Maps constituent/person   |    | Maps contacts and          |
  | and organisation data     |    | organisations              |
  | Merges into standardised  |    | Merges into standardised   |
  | records; updates contact  |    | records; updates contact   |
  | arrays, attributes, flags |    | arrays, attributes, flags  |
  | and four-year rule        |    | and normalises fields      |
  | Deactivates absent or     |    | Deactivates absent or      |
  | ineligible records        |    | ineligible records         |
  +-------------+-------------+    +--------------+-------------+
                |                                 |
                +----------------+----------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  | MDM_DB.STAGING.STANDARDISED_RECORDS                          |
  | Shared active/inactive records, source IDs, fields and arrays|
  +------------------------------+-------------------------------+
                                 |
                    Dynamics ETL status:
                    SP_ETL_DYNAMICS() exists, but its call is
                    commented out in the exported TEST/PROD wrapper.
                    It is therefore skipped by this task chain.
                                 |
                                 v
  +--------------------------------------------------------------+
  | TK_BUILD_MATCH_GROUPS                                        |
  | Calls MDM_DB.MDM.SP_BUILD_MATCH_GROUPS()                     |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  | Rebuild match working data                                   |
  | Clear MATCH_CANDIDATES, MATCH_COMPONENTS, MATCH_GROUPS and   |
  | MATCH_GROUP_MEMBERS, then generate candidate pairs from      |
  | active standardised records using configured identity rules. |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  | SP_BUILD_MATCH_COMPONENTS()                                  |
  | Propagates labels across eligible candidate links to identify|
  | connected record groups (until stable or 20 iterations).     |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  | Write MATCH_GROUPS and MATCH_GROUP_MEMBERS                   |
  | Score groups and assign statuses such as Auto-Approved,      |
  | Pending Review, or Low Confidence.                           |
  +------------------------------+-------------------------------+
                                 |
                    Task dependency: runs after
                    TK_BUILD_MATCH_GROUPS completes
                                 |
                                 v
  +--------------------------------------------------------------+
  | TK_GENERATE_GOLDEN_RECORDS                                   |
  | Calls MDM_DB.GOLD.SP_GENERATE_GOLDEN_RECORDS()               |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  | Build/refresh GOLDEN_RECORDS                                 |
  | Fuse eligible match groups; keep other active records as     |
  | singletons. Select representative values by recency and      |
  | completeness, and retain or generate golden IDs.             |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  | Maintain XREF and staging links                              |
  | Insert/update source-to-golden links, prune stale links,     |
  | deactivate superseded golden records, and backfill           |
  | GOLDEN_RECORD_ID to STANDARDISED_RECORDS.                    |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +---------------------------------------------------------------+
  | Outputs                                                       |
  | STANDARDISED_RECORDS | MATCH_GROUPS / MEMBERS | GOLDEN_RECORDS|
  | XREF                                                          |
  +--------------------------------------------------------------+

Separate checks and boundaries
------------------------------
- SP_VALIDATE_MDM() is a separate procedure; it is not called by these tasks.
- A successful task state confirms SQL completion, not record-level correctness.
  Review procedure return counts, data-quality results, and reconciliations.
- This diagram describes the exported Snowflake MDM chain. It does not show
  ADF orchestration, Dynamics API dispatch, or prove that either ran.
- Task definitions are exported SQL; confirm deployed task state and definitions
  in the relevant Snowflake account.






