# Postcode DEV pilot handover

## Status at 28 November 2026

**The user reported success after the synthetic Postcode pilot run
instructions. Final Dynamics readback, Snowflake capture/audit results and
the post-run dispatch count have not yet been supplied.**

The deployed request query returned one row with the expected fixed GUID
and synthetic Name. Live preflight checks found no matching test name and
confirmed that the planned GUID did not exist. The user approved synthetic
DEV creation and confirmed safety from external communications, live
synchronisation and unwanted changes to other records. The local shared
dispatcher update was separately approved.

This is technical creation testing, not migration of a real RE postcode,
an approved postcode classification model or full-load readiness.
**Do not repeat an uncertain POST, clear tracking or change the planned
GUID to force another attempt. Reconcile the existing attempt first.**

| Item | Value |
|---|---|
| Workbook | [Mapping V6](<./NAS DM Source to Target Mappings Current WIP 1.xlsx>), rows 3592-3609 |
| Dynamics object / entity set | `mhnas_postcode` / `mhnas_postcodes` |
| Primary ID / primary name | `mhnas_postcodeid` / `mhnas_name` |
| Synthetic Name | `TEST-POSTCODE-DEV-001` |
| Planned Dynamics GUID | `6d60ded3-97a2-409a-bb8f-d62abb08315d` |
| Test identity | `POSTCODE_TEST:DEV-001` |
| Source evidence | `SYNTHETIC_ONLY`; no corresponding RE postcode was selected |
| Tracking table | `AUDIT_DB.MONITORING.POSTCODE_PILOT_TRACKING_DEV` |
| Pipeline / source / entity parameters | `D365_POSTCODE_PILOT` / `SNOWFLAKE_DEV` / `POSTCODE_TEST` |
| TestRowsPerCombo | `1` |
| Target environment | `https://nasdatamig.crm11.dynamics.com` |

## ADF run parameters

Pipeline: `PL_D365_DispatchRequests` in DEV, using the
[updated dispatcher definition](<ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>).

The parameters supplied for the run instructions were:

| Parameter | Value |
|---|---|
| `PipelineId` | `D365_POSTCODE_PILOT` |
| `SourceInstance` | `SNOWFLAKE_DEV` |
| `EntityId` | `POSTCODE_TEST` |
| `TestRowsPerCombo` | `1` |

```json
{
  "PipelineId": "D365_POSTCODE_PILOT",
  "SourceInstance": "SNOWFLAKE_DEV",
  "EntityId": "POSTCODE_TEST",
  "TestRowsPerCombo": 1
}
```

The user then reported success. The ADF run ID, actual run-input export and
individual activity results have not yet been supplied; retain them with
the final proof. This section records the instructed parameters, not an
independently verified run-input export. It is not an instruction to rerun.

## RE source investigation

The read-only source checks returned:

| Check | Supplied result |
|---|---:|
| Rows in `RAW.RAISERS_EDGE.VW_ODS_T_ADDRESSES` | 2,021,748 |
| Nonblank postcode values | 2,021,748 |
| Original uppercase full-postcode pattern matches | 0 |
| Pattern matches after UPPER/TRIM | 0 |
| Rows returned by Constituent preferred-address join | 1,400,863 |
| Postcode values equal to `********` after TRIM | 2,021,748 |
| Other nonblank postcode values | 0 |

Sample address IDs 6481-6490 each returned `********`, length 8.
The preferred-address join was therefore not the reason for zero pilot
candidates; no usable full-postcode value was returned by these checks.
The masking mechanism and underlying unmasked values were not established.

The source-backed pilot was changed, with the user's approval, to a
synthetic Name-only test. The placeholder `********` was not loaded.
`TEST-POSTCODE-DEV-001` was generated locally and has no corresponding RE
postcode record. These Snowflake queries are evidence about the RE extract,
not direct proof of what is visible in the RE application.

For real source-to-target proof, obtain an authorised usable postcode
source, retain its RE address/source identity, and verify the mapped value
in Dynamics. Do not bypass masking or infer a postcode from masked data.

## Dynamics metadata and existing reference data

Supplied live DEV metadata confirmed:

- `mhnas_name`: String, application-required, create-valid, maximum 850.
- `mhnas_postcodeid`: Uniqueidentifier, system-required and create-valid;
  it is a GUID, not postcode text.
- `mhnas_nation`: optional create-valid Picklist.
- `mhnas_crossborder`: optional create-valid Boolean.
- Supplied outgoing lookups were system/organisation relationships, with
  no application-required business lookup dependency shown.
- The supplied incoming one-to-many relationships contained system tables,
  but no Contact or Account postcode lookup. This does not establish the
  absence of automation or other application logic.

The user supplied 144 active existing reference rows with no next-page
link. They include areas such as `AB`, `CH` and `SY`, plus district entries
such as `CH5`-`CH8`, `SY10` and `TD15`. Several district entries have Cross
Border set to true and different Nation option values from their area row.
Nation option labels and matching/precedence rules were not verified.

This pattern supports investigating classification use, but does not
authorise a matching algorithm or establish the required migration grain.
The synthetic pilot deliberately does not resolve those business rules.

## Payload and implementation

Exactly two fields were prepared and returned by the user-run request query:

```json
{
  "mhnas_postcodeid": "6d60ded3-97a2-409a-bb8f-d62abb08315d",
  "mhnas_name": "TEST-POSTCODE-DEV-001"
}
```

Name is the only business field sent; the GUID is a fixed technical
identity. Nation, Cross Border, state/status and audit fields were not
explicitly sent. Target defaults or automation may populate omitted fields;
their resulting values have not yet been supplied. No Contact/Account
update is part of this route.

### Local files and deployment order

1. [Tracking setup and grants](AUDIT_DB/Config/POSTCODE_PILOT_TRACKING_DEV.sql).
2. [Synthetic preview](INTEGRATION_DB/DYNAMICS/Views/VW_D365_POSTCODE_PILOT_PREVIEW_DEV.sql).
3. [Request view and read grants](INTEGRATION_DB/DYNAMICS/Views/VW_D365_POSTCODE_PILOT_REQUESTS_DEV.sql).
4. [Shared dispatcher](<ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>).

Deploy SQL as an authorised object owner/admin, not by giving ETL ownership.
The tracking procedure uses CREATE, not CREATE OR REPLACE; if it already
exists, inspect the deployed version rather than blindly rerunning setup.
Preserve any existing tracking row.

The request view pins the API URL to DEV and uses the existing
`D365_WRITEBACK / SNOWFLAKE_DEV / CAMPAIGN` connection-metadata template.
Its actual request entity is `POSTCODE_TEST`, not Campaign.
It checks the exact two-field payload and holds dispatch when test
tracking, writeback state or a Dynamics XREF identity is present.
A uniqueness check prevents dispatch from ambiguous metadata rows.
It does not perform a live Dynamics duplicate query; live preflight remains
necessary immediately before any first run.

The dispatcher gained three Postcode branches:

- Select the dedicated request view for `D365_POSTCODE_PILOT`.
- Select `mhnas_postcodeid` in the POST representation response.
- Call the dedicated capture procedure for the returned GUID.

Capture accepts only the planned GUID. It inserts one matching test row,
returns CAPTURED for a matching existing row, and raises on conflicting or
duplicate tracking. It runs as owner with rollback and rethrow on failure.
The ordinary Snowflake table and request guards are not concurrency-safe;
do not overlap writers or treat them as full-load idempotency guarantees.

Setup includes ETL database/schema USAGE, tracking-table SELECT, capture
procedure USAGE and USAGE on the existing seven-argument logging procedure.
The request script grants SELECT on both pilot views.
Other existing dependency privileges still need to be available.

Reliable role checks use:

```sql
USE ROLE R_NAS_ETL_DEV;
USE SECONDARY ROLES NONE;
SELECT CURRENT_ROLE(), CURRENT_SECONDARY_ROLES();
```

A deliberately invalid capture-ID test was supplied. Its individual result
was not returned. Never test capture with the planned ID before verified
target creation: that would fabricate successful tracking.

Local validation passed JSON parsing, expression quote/parenthesis balance,
exact restoration of prior route expressions when the new wrappers were
removed, payload shape/length checks, capture/grant/request invariants and
`git diff --check`. These are not live regression tests of earlier routes.
The assistant did not access external systems or execute a DEV write.

## Proof in RE, Snowflake, Dynamics order

### 1. RE extract proof: source masking, not migrated postcode

```sql
SELECT
    COUNT(*) AS ADDRESS_ROWS,
    COUNT_IF(TRIM(POSTCODE) = '********') AS MASKED_POSTCODE_ROWS,
    COUNT_IF(
        NULLIF(TRIM(POSTCODE), '') IS NOT NULL
        AND TRIM(POSTCODE) <> '********'
    ) AS OTHER_NONBLANK_ROWS
FROM RAW.RAISERS_EDGE.VW_ODS_T_ADDRESSES;
```

Supplied result: 2,021,748 address rows, 2,021,748 masked values, zero other
nonblank values. There is no source-to-target value match for this test.

### 2. Snowflake payload, capture, audit and dispatch proof

```sql
SELECT TEST_KEY, SOURCE_EVIDENCE, DRAFT_PAYLOAD
FROM INTEGRATION_DB.DYNAMICS.VW_D365_POSTCODE_PILOT_PREVIEW_DEV;

SELECT TEST_KEY, D365_GUID, CAPTURED_AT
FROM AUDIT_DB.MONITORING.POSTCODE_PILOT_TRACKING_DEV
WHERE TEST_KEY = 'POSTCODE_TEST:DEV-001';

SELECT *
FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE
WHERE ENTITY_ID = 'POSTCODE_TEST'
  AND GOLDEN_RECORD_ID = 'POSTCODE_TEST:DEV-001';

SELECT COUNT(*) AS DISPATCHABLE_ROWS
FROM INTEGRATION_DB.DYNAMICS.VW_D365_POSTCODE_PILOT_REQUESTS_DEV;
```

Expected after a reconciled success: the synthetic payload, exactly one
matching tracking row, successful writeback state and zero dispatchable
rows. These post-run results have not yet been supplied. A zero request
count alone does not prove successful target creation or logging.

### 3. Dynamics target readback and UI proof

```text
https://nasdatamig.crm11.dynamics.com/api/data/v9.2/mhnas_postcodes(6d60ded3-97a2-409a-bb8f-d62abb08315d)?$select=mhnas_postcodeid,mhnas_name,statecode,mhnas_nation,mhnas_crossborder
```

Verify the exact planned GUID and Name `TEST-POSTCODE-DEV-001`.
State 0 (Active) is expected; record actual Nation/Cross Border values
without claiming they were mapped from RE.

For UI proof, use the matching Power Apps DEV environment:
Tables -> Postcode (`mhnas_postcode`) -> Data, then locate the test Name
and confirm the GUID. No post-run API or UI proof has yet been supplied.

Before the reported run, the exact-Name query returned `value: []` and the
planned-GUID GET returned record-not-found (`0x80040217`). Those are
preflight evidence, not post-run proof.

## Workbook mapping

| Row | Display name | Logical field | Migration/sync |
|---:|---|---|:---:|
| 3592 | Created By | `createdby` | N |
| 3593 | Created On | `createdon` | N |
| 3594 | Created By (Delegate) | `createdonbehalfby` | N |
| 3595 | Import Sequence Number | `importsequencenumber` | N |
| 3596 | Cross Border | `mhnas_crossborder` | N |
| 3597 | Name | `mhnas_name` | N |
| 3598 | Nation | `mhnas_nation` | N |
| 3599 | Postcode | `mhnas_postcodeid` | Y |
| 3600 | Modified By | `modifiedby` | N |
| 3601 | Modified On | `modifiedon` | N |
| 3602 | Modified By (Delegate) | `modifiedonbehalfby` | N |
| 3603 | Organization Id | `organizationid` | N |
| 3604 | Record Created On | `overriddencreatedon` | N |
| 3605 | Status | `statecode` | N |
| 3606 | Status Reason | `statuscode` | N |
| 3607 | Time Zone Rule Version Number | `timezoneruleversionnumber` | N |
| 3608 | UTC Conversion Time Zone Code | `utcconversiontimezonecode` | N |
| 3609 | Version Number | `versionnumber` | N |

Row 3599 comment, verbatim:

> to populate with poscode from contact.Address1_PostalCode and organistaion postcode

RE source-table/source-field cells are blank. The Y on the GUID field and
N on required Name need clarification; postcode text cannot be inserted
into a GUID. The pilot's Name and technical ID choices do not amend the
workbook or prove its mapping is complete.

## Outstanding decisions and next actions

1. Obtain the ADF run ID and individual outcomes of `WEB_Post`,
   `SCR_CAPTURE_XREF` and `SCR_LogPostSuccess`, including failure branches.
2. Obtain post-run proof in the order above. If anything disagrees,
   reconcile the planned GUID and activity history without another POST.
3. Once evidence agrees, mark only the synthetic technical pilot verified.
   Agree retention or authorised cleanup of this test row and tracking;
   do not let the marker become a real classification or full-load input.
4. Obtain an authorised usable RE postcode source. Establish source
   identity, address selection and Contact/organisation scope.
5. Confirm whether target rows represent full postcodes, areas, districts
   or a mixed classification model. Define normalisation, validation,
   missing/foreign/invalid values, duplicates and any precedence rules.
6. Reconcile workbook ID/Name flags and confirm Nation/Cross Border
   mapping/defaults, reference-data ownership and automation behaviour.
7. Missing destination records for an in-scope object should be prepared
   for creation, not automatically excluded. Resolve required missing
   parents/references through migration or their designated owner.
   Existing rows alone do not exclude new RE values. Review fixed pilot
   restrictions before claiming all missing records will be loaded.
   See the [cross-object follow-up](CONSENT_DEV_HANDOVER.md#follow-up-missing-destination-records-and-dependencies).
8. Test representative source-backed cases, controlled batches,
   reconciliation and rerun/failure recovery before full-load approval.

Current manager-facing wording:

> A synthetic Postcode creation pilot has been prepared and success
> reported in DEV. Final target readback, capture and audit reconciliation
> remain outstanding. All queried RE extract postcodes were masked, so
> real RE postcode migration is not yet demonstrated. Usable source data,
> mapping clarification and full-load acceptance remain required.
