# Address Change DEV pilot handover

## Status at 27 November 2026

**One synthetic Address Change record was created and verified in Dynamics
DEV by API readback and the user's Power Apps table inspection.** Its Party
was resolved from an RE constituent-address link through Snowflake.

ADF failed after creation when its Snowflake role could not access the
isolated capture procedure. The returned ID was manually reconciled into
test-only tracking. Required permissions were subsequently granted and the
capture procedure was successfully called using the ADF role alone.

This demonstrates a synthetic DEV write, not migration of real RE address
values, full-load readiness or a fully verified automated capture/audit flow.
**Do not rerun the POST, remove the tracking row or clear guards to retry.**

| Item | Value |
|---|---|
| Workbook | [Mapping V6](<./NAS DM Source to Target Mappings Current WIP 1.xlsx>), rows 2782-2808 |
| Dynamics object / entity set | `mha_addresschange` / `mha_addresschanges` |
| Dynamics primary ID | `mha_addresschangeid` |
| RE constituent-address link ID | `8478` |
| DEV Account | `e9054cfe-3359-f111-a825-6045bd0f7c7f` |
| Created Dynamics ID | `27db1744-52ea-f111-84e9-7c1e5202a949` |
| Test identity | `ADDRESSCHANGE_TEST:8478` |
| Reserved real migration identity | `ADDRESSCHANGE:8478`; not used to capture this test |
| Tracking table | `AUDIT_DB.MONITORING.ADDRESSCHANGE_PILOT_TRACKING_DEV` |
| Pipeline / source / entity parameters | `D365_ADDRESSCHANGE_PILOT` / `SNOWFLAKE_DEV` / `ADDRESSCHANGE_TEST` |
| TestRowsPerCombo | `1` |
| Target environment URL | `https://nasdatamig.crm11.dynamics.com` |

## Source checks and pilot selection

The supplied source metadata confirmed:

- Address values in `RAW.RAISERS_EDGE.VW_ODS_T_ADDRESSES`.
- Constituent-address links in
  `RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTADDRESSES`.
- Join: constituent-address `ADDRESS_ID` to address `ID`.

User-supplied aggregate profiling returned:

| Check | Result |
|---|---:|
| Constituent-address link rows | 2,125,713 |
| Distinct link IDs | 2,125,713 |
| Missing link IDs, constituents or address IDs | 0 each |
| Links resolving to exactly one address | 2,125,713 |
| Links to duplicate address IDs / missing addresses | 0 each |
| Links with `PREFERRED = 1` | 0 |
| Links with `PREFERRED = 0` | 724,850 |
| Links with a nonblank end date | 122,904 |

These are point-in-time extract counts, not approved migration scope.
The remaining preferred-flag values were not profiled; do not interpret
`PREFERRED` as a reliable current-address selector yet.

Candidate `8478` had a parseable end date before the selection date, one
source link and one address, one golden record, known non-suppressed privacy
status, and one matching Dynamics Account identity across golden IDs and
Dynamics XREF. An end date was only a technical selection criterion, not an
approved rule for address history or a verified address-change event date.

The user selected synthetic address values and confirmed DEV creation was
safe from unwanted automation effects. Real address values were neither
returned in the preview nor included in the request.

## Payload and target evidence

The request contained exactly:

```json
{
  "mha_address_line1": "SYNTHETIC TEST ADDRESS 8478",
  "mha_name": "TEST-ADDRESSCHANGE-8478",
  "mha_partyid_account@odata.bind": "/accounts(e9054cfe-3359-f111-a825-6045bd0f7c7f)"
}
```

Before dispatch, the Account was active (`statecode = 0`) and a search for
the test name returned no records.

After dispatch, the user supplied API readback confirming:

| Target field | Returned value |
|---|---|
| `mha_addresschangeid` | `27db1744-52ea-f111-84e9-7c1e5202a949` |
| `mha_address_line1` | `SYNTHETIC TEST ADDRESS 8478` |
| `_mha_partyid_value` | `e9054cfe-3359-f111-a825-6045bd0f7c7f` |
| `mha_name` | `27/11/2026 11:04` |

The user subsequently located the record in Power Apps.
**Dynamics returned a timestamp instead of the submitted test name.**
The mechanism was not established. Do not rely on the name marker for
future duplicate detection. Live metadata identifies `mha_name` as text,
not a date field, despite its display label "Changed On".

Other address fields, country, dates, owner and status were not sent.
Country is a create-valid string, not a lookup, in the supplied live
metadata. All seven address strings have a maximum length of 100;
`mha_name` has a maximum length of 850. Party is create-valid and
application-required.

## ADF failure, reconciliation and permissions

The capture activity attempted:

```sql
CALL AUDIT_DB.MONITORING.SP_CAPTURE_ADDRESSCHANGE_PILOT_DEV(
    '27db1744-52ea-f111-84e9-7c1e5202a949'
);
```

It failed with:

```text
SQL compilation error:
Unknown user-defined function AUDIT_DB.MONITORING.SP_CAPTURE_ADDRESSCHANGE_PILOT_DEV.
```

Snowflake query history identified query
`01c8b098-0002-7a47-0002-472a022300c6`, user `U_NAS_ETL_DEV`,
role `R_NAS_ETL_DEV`, and status `FAILED_WITH_ERROR`.

Initial worksheet tests appeared successful with primary role
`R_NAS_ETL_DEV`, but secondary roles included `ACCOUNTADMIN`. Repeating
the checks with secondary roles disabled exposed missing access to
`AUDIT_DB.MONITORING`. This establishes a permissions problem consistent
with the ADF capture failure.

The verified Dynamics ID was manually captured under `ACCOUNTADMIN`.
The tracking row returned:

```text
ADDRESSCHANGE_TEST:8478
27db1744-52ea-f111-84e9-7c1e5202a949
2026-11-27 11:15:26.048 Z
```

The user successfully applied:

```sql
GRANT USAGE ON DATABASE AUDIT_DB TO ROLE R_NAS_ETL_DEV;
GRANT USAGE ON SCHEMA AUDIT_DB.MONITORING TO ROLE R_NAS_ETL_DEV;
GRANT SELECT ON TABLE
    AUDIT_DB.MONITORING.ADDRESSCHANGE_PILOT_TRACKING_DEV
TO ROLE R_NAS_ETL_DEV;
GRANT USAGE ON PROCEDURE
    AUDIT_DB.MONITORING.SP_CAPTURE_ADDRESSCHANGE_PILOT_DEV(VARCHAR)
TO ROLE R_NAS_ETL_DEV;
```

With `USE SECONDARY ROLES NONE`, the ADF role subsequently read one
tracking row and called the procedure with the existing matching ID,
returning `CAPTURED`. The procedure accepts that matching row without
inserting another; this return value does not mean a new row was inserted.

**Automatic capture through ADF has not been reverified after the fix.**
The user found no writeback-state row for the test identity. Audit logging
for the original run therefore remains unresolved; do not claim a logged
successful end-to-end ADF run.

## Files and safety

| File | Purpose |
|---|---|
| [Tracking setup](./AUDIT_DB/Config/ADDRESSCHANGE_PILOT_TRACKING_DEV.sql) | DEV-only table and owner-executed capture procedure; validates GUIDs and rejects conflicting or duplicate tracking rows. |
| [Preview](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_ADDRESSCHANGE_PILOT_PREVIEW_DEV.sql) | Fixed source link, privacy and Account checks; synthetic-only payload. |
| [Requests](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_ADDRESSCHANGE_PILOT_REQUESTS_DEV.sql) | Exact three-field payload, DEV URL and identity guards; uses Campaign metadata as a connection template. |
| [Dispatcher](<./ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>) | Approved pilot wrappers for request selection, returned ID selection and isolated capture. |
| [Load gates](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_REF_LOAD_GATE.sql) | Address slot, address type and country gates remain unchanged and open. |

The generic XREF procedure's supplied `GET_DDL` and `DESCRIBE` outputs
contained a blank body. Its handling of a synthetic identity could not be
verified, so the user approved isolated tracking and local dispatcher
updates. This pilot does not write its ID into shared GOLD.XREF.

The three dispatcher wrappers passed JSON and expression delimiter checks;
removing them restored the previous expressions exactly before related
description updates. The user validated the updated pipeline in ADF.
This is not a regression test of earlier object routes.

The user confirmed that dataset `DS_Snowflake_Metadata` uses `LS_Snowflake`;
the capture activity also uses `LS_Snowflake`.

The final supplied checks showed **zero dispatchable rows, one tracking
row and no test writeback-state row**. Tracking currently blocks repeat
dispatch. The guards and tracking writes are not concurrency-safe; do not
overlap writers or use this pilot as a full-load retry design.

## Demonstrable proof: RE extract -> Snowflake -> Dynamics

### RE extract held in Snowflake

This query displays only technical IDs and counts, not real address values.
It is not direct verification inside the RE application. A result from this
specific proof query was not supplied at handover time.

```sql
SELECT CA.ID AS RE_CONSTITUENT_ADDRESS_ID,
       CA.ADDRESS_ID AS RE_ADDRESS_ID,
       COUNT(*) AS JOINED_ROWS
FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTADDRESSES CA
JOIN RAW.RAISERS_EDGE.VW_ODS_T_ADDRESSES A
    ON A.ID = CA.ADDRESS_ID
WHERE CA.ID = 8478
GROUP BY CA.ID, CA.ADDRESS_ID;
```

Expected: one joined row. The earlier candidate and fixed-preview outputs
already established the source-link and resolved-Party path.

### Snowflake tracking and repeat-dispatch guard

```sql
SELECT TEST_KEY, D365_GUID, CAPTURED_AT
FROM AUDIT_DB.MONITORING.ADDRESSCHANGE_PILOT_TRACKING_DEV
WHERE TEST_KEY = 'ADDRESSCHANGE_TEST:8478';

SELECT COUNT(*) AS DISPATCHABLE_ROWS
FROM INTEGRATION_DB.DYNAMICS.VW_D365_ADDRESSCHANGE_PILOT_REQUESTS_DEV;

SELECT ENTITY_ID, GOLDEN_RECORD_ID
FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE
WHERE GOLDEN_RECORD_ID = 'ADDRESSCHANGE_TEST:8478';
```

Latest supplied results: one matching tracking row, zero dispatchable
requests and no writeback-state row.

### Dynamics API and UI

```text
https://nasdatamig.crm11.dynamics.com/api/data/v9.2/mha_addresschanges(27db1744-52ea-f111-84e9-7c1e5202a949)?$select=mha_addresschangeid,mha_name,mha_address_line1,_mha_partyid_value
```

[Open the record](https://nasdatamig.crm11.dynamics.com/main.aspx?pagetype=entityrecord&etn=mha_addresschange&id=27db1744-52ea-f111-84e9-7c1e5202a949).
Alternatively, select the matching environment in Power Apps, open
Tables -> Address Change -> Data, and display Line 1. Find
`SYNTHETIC TEST ADDRESS 8478`, not the submitted name marker.

Suitable manager-facing wording:

> A synthetic Address Change record was successfully created in Dynamics
> DEV using a Party resolved from RE through Snowflake. Its returned ID was
> manually reconciled into isolated tracking. Real-address mapping,
> automatic ADF capture and audit verification remain outstanding.

## Workbook mappings and business questions

Eight fields are marked Y in Mapping V6:

| Row | Workbook RE source | Dynamics field | Pilot treatment |
|---|---|---|---|
| 2786 | Addresses: City | `mha_address_city` | Omitted |
| 2787 | Addresses: Country Description; ISO-country reference notes | `mha_address_country` | Omitted; target is text |
| 2788 | Addresses: AddressLine1 | `mha_address_line1` | Synthetic value only |
| 2789 | Addresses: AddressLine2 | `mha_address_line2` | Omitted |
| 2790 | Addresses: AddressLine3 | `mha_address_line3` | Omitted; workbook says line 4 not required |
| 2791 | Addresses: Postcode | `mha_address_postalcode` | Omitted |
| 2792 | Addresses: CountyDescription | `mha_address_stateorprovince` | Omitted |
| 2795 | Addresses: Constituent ID via joining table; Contact or organisation | `mha_partyid` | Verified DEV Account binding |

Changed On (`mha_name`), Record Created On, Owner and Status are marked N.
The pilot name marker was a technical test choice, not an approved mapping.

Business input is needed on:

1. **Meaning and scope:** Does Address Change represent an old address,
   a new address or a change event? Which current/historical records and
   periods belong here, and which remain in Contact/Account address slots?
2. **Source selection and dates:** What do preferred flags and start/end
   dates mean? What proves an actual address change, and what stable source
   ID identifies it?
3. **Field mapping:** Confirm all Y fields, blanks, length exceptions,
   county and postcode handling. Confirm how the workbook's ISO-country
   notes translate to the live text field, and retain or revise the agreed
   omission of address line 4.
4. **Party, privacy and retention:** Confirm Contact/Account rules,
   missing or ambiguous identities, suppressed constituents, permitted real
   address data, access controls and retention.
5. **Duplicates and automation:** Agree existing-record matching,
   repeat loads, target-generated Changed On values, owner/defaults and
   whether Address Change creation changes other addresses or triggers
   automation. The user's safety confirmation applied to this DEV pilot.
6. **Transition and acceptance:** Agree updates/deletions, field ownership,
   retained RE history, reconciliation and business sign-off.

## Next technical actions

1. Preserve the created record, tracking row and original ADF failure
   evidence. Do not rerun the POST.
2. Verify capture through an ADF Script-only test using the already
   verified ID and `LS_Snowflake`; do not include a Web POST. Confirm that
   the tracking count remains one. Obtain approval before changing or
   adding pipeline activities.
3. Investigate the original failure-logging activity and missing
   writeback-state row. Do not overwrite failure evidence with an invented
   success or blindly call an unverified logging procedure.
4. Investigate why Dynamics replaced the name marker; establish reliable
   duplicate detection before any further creates.
5. After business decisions, implement real address transformations,
   durable source identity/capture, controlled batches, retries and
   reconciliation. Retest representative records before a full DEV load.

The synthetic pilot does not close the existing business gates or prove
that the implementation will run independently of RE after retirement.
