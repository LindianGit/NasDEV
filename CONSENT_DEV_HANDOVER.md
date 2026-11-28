# Consent DEV pilot handover

## Status at 27 November 2026

**The user reported ADF success for one fixed Donations opt-out pilot.**
The source preference history, privacy/identity resolution, target metadata
and pre-run duplicate checks were supplied. Post-run Dynamics readback,
isolated tracking, audit state and repeat-dispatch checks have been requested
but their results have not yet been supplied.

Do not describe target creation or automatic capture as independently
verified yet. ADF pipeline success can include zero dispatched rows.
**Do not rerun the POST to establish proof.**

All work is DEV-only. This is a technical pilot using real explicit RE
opt-outs, a synthetic name and an isolated test identity. It is not a full
Consent migration, approval of all consent rules or an ongoing sync.

| Item | Value |
|---|---|
| Workbook | [Mapping V6](<./NAS DM Source to Target Mappings Current WIP 1.xlsx>), rows 2892-2924 |
| Dynamics table / entity set | `mha_consent` / `mha_consents` |
| Primary ID | `mha_consentid` |
| Planned Dynamics ID; post-run existence unverified | `9d1fdf0d-00cd-40a0-a40d-8e06e6053af8` |
| Synthetic name | `TEST-CONSENT-2273445` |
| Source anchor attribute | `2273445` |
| Golden record | `GR-205748389` |
| Dynamics Contact | `1bcce781-9ee0-f111-84ea-002248425074` |
| Donations Consent Type | `b6825be3-c160-f111-a825-7ced8d9cafea` |
| Test identity, not a shared XREF capture | `CONSENT_TEST:2273445` |
| Pipeline ID | `D365_CONSENT_PILOT` |
| SourceInstance / EntityId / TestRowsPerCombo | `SNOWFLAKE_DEV` / `CONSENT_TEST` / `1` |
| DEV endpoint | `https://nasdatamig.crm11.dynamics.com/api/data/v9.2` |

## What was done

1. Reviewed Consent Type readiness. Eighteen rule-derived types already
   matched active live Dynamics records, including Donations. No Consent
   Types were created. See the [Consent Type handover](./CONSENT_TYPE_DEV_HANDOVER.md).
   Help Mailing, Membership Payments, Newsletter and Unsolicited Mail
   remain unresolved with NAS/mhance.
2. Reviewed user-supplied live Consent metadata, relationship navigation
   names and channel option values. No numeric consent choices were guessed.
3. The user chose a source-backed explicit opt-out pilot and confirmed DEV
   creation could not trigger external communications, synchronise consent
   to live systems or overwrite existing preferences through automation.
4. Profiled No Donations source rows without returning constituent details:

   | Channel | Source rows | Parseable dates |
   |---|---:|---:|
   | Email Preferences | 2,976 | 2,343 |
   | Postal Preferences | 5,264 | 5,233 |
   | SMS Preferences | 1,870 | 1,869 |
   | Telephone Preferences | 5,078 | 4,107 |

   These are point-in-time extract counts, not approved migration scope.
5. Inspected full preference/exclusion history for candidates. Candidate
   `2079204` also had unresolved `z No Unsolicited Mail` and was not used.
   The selected candidate, `2273445`, had eight reviewed rows: four
   No Donations and four No Political Campaigns. No general preferences or
   Contact Exclusions rows appeared in the supplied history result.
6. Confirmed one exposed Contact, no Account, and known non-suppressed
   privacy status. The live Contact was active. A live search for its
   Donations consents returned no records, and the planned GUID lookup
   returned record-not-found immediately before the reported run.
7. With user approval, prepared a fixed all-channels-Out payload, omitting
   dates, comments and declared-by fields. Added an isolated tracking
   procedure and three local shared-dispatcher wrappers. The user compiled
   the views, supplied the expected request and validated the pipeline in ADF.
8. Corrected capture-procedure access for the ETL role. The user then
   reported ADF "success". The final verification results remain outstanding.

## Source evidence and pilot mapping

All eight reviewed preference rows are dated **23 August 2012**.

| RE attribute ID | Attribute | Value | Used for Donations payload |
|---:|---|---|---|
| 2273444 | Email Preferences | No Political Campaigns | No |
| 2273448 | Email Preferences | No Donations | Email = Out |
| 2273441 | Postal Preferences | No Political Campaigns | No |
| 2273445 | Postal Preferences | No Donations | Post = Out |
| 2273443 | SMS Preferences | No Political Campaigns | No |
| 2273447 | SMS Preferences | No Donations | SMS = Out |
| 2273442 | Telephone Preferences | No Political Campaigns | No |
| 2273446 | Telephone Preferences | No Donations | Telephone = Out |

Political Campaigns remains separate; this pilot does not create that
Consent record. Other channels were not defaulted or inferred: each of the
four Out values has an explicit Donations source row.

The source date is checked in the preview but not sent to Dynamics.
Consequently this pilot does not prove original effective-date or
record-created-date preservation.

## Target metadata and fixed payload

The supplied live metadata marks Name, Consent Type and all four channel
fields as application-required and create-valid. Party is a create-valid
Customer field supporting Contact or Account. The pilot uses:

- Contact navigation property: `mha_consentfor_contact`.
- Type navigation property: `mha_consenttypeid`.
- All four channels share these values and default to No Response:

  | Label | Value |
  |---|---:|
  | No Response | 862940000 |
  | Out | 862940001 |
  | In | 862940002 |

The user supplied the compiled request containing exactly:

```json
{
  "mha_consentfor_contact@odata.bind": "/contacts(1bcce781-9ee0-f111-84ea-002248425074)",
  "mha_consentid": "9d1fdf0d-00cd-40a0-a40d-8e06e6053af8",
  "mha_consenttypeid@odata.bind": "/mha_consenttypes(b6825be3-c160-f111-a825-7ced8d9cafea)",
  "mha_email": 862940001,
  "mha_name": "TEST-CONSENT-2273445",
  "mha_post": 862940001,
  "mha_sms": 862940001,
  "mha_telephone": 862940001
}
```

No opt-in values, comments, source notes, effective date, declaration,
declared-by, owner or explicit status were sent. Target defaults and
automation outcomes require readback; name preservation is not assumed.

## Implementation and safety

| File | Purpose |
|---|---|
| [Tracking setup](./AUDIT_DB/Config/CONSENT_PILOT_TRACKING_DEV.sql) | Dedicated DEV tracking table, fixed-ID capture procedure and ETL-role grants. |
| [Preview](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_CONSENT_PILOT_PREVIEW_DEV.sql) | Pins all eight reviewed rows, their dates/values, privacy, cross-system Contact resolution and Donations type. |
| [Requests](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_CONSENT_PILOT_REQUESTS_DEV.sql) | Pins eight payload keys and values and the DEV endpoint; blocks tracked, state or XREF identities. |
| [Dispatcher](<./ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>) | Approved routing to the request view, `mha_consentid` response selection and isolated capture call. |
| [Load gates](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_REF_LOAD_GATE.sql) | Existing Consent business/safety gates remain unchanged. |

The test key deliberately stays outside shared GOLD.XREF. This avoids
claiming a real full-load identity is migrated and avoids relying on the
generic capture procedure whose supplied definition was blank.

The capture procedure accepts only the planned GUID. It inserts the test
tracking row or accepts one matching existing row; conflicts/duplicates
raise an error. Its `CAPTURED` return can mean either case. Do not call it
with the planned ID merely to test access before verifying a real creation:
that would create success-shaped tracking without target evidence.

The preview is read-only and its `PREVIEW_DISPATCH_ALLOWED = FALSE` is
informational, not an execution switch. The request view independently
applies dispatch guards. Source-history changes cause the fixed preview
to stop returning a row. It does not generalise latest-value selection.

The planned GUID helps reconcile uncertain outcomes and prevents a second
record with that same GUID. It does not replace checking for an existing
Consent under a different GUID. Duplicate/state/tracking guards are not
atomic; do not overlap writers or blindly retry.

The request uses the existing Campaign pipeline metadata row as a DEV
connection template. It is not general Consent pipeline configuration.

Three new dispatcher wrappers passed JSON parsing and expression delimiter
checks. Removing those wrappers restored the previous expressions exactly
before related description updates. This is static validation, not a live
regression test of earlier object routes.

## Permissions and execution evidence

Use the object owner/authorised administrator for setup scripts. Use the
ADF role with secondary roles disabled for access checks:

```sql
USE ROLE R_NAS_ETL_DEV;
USE SECONDARY ROLES NONE;
```

An attempt to replace the preview using the ETL role failed with an
ownership error. No ownership elevation was required: setup belongs under
the administrative role, while ETL needs read/execute access.

The initial capture test under the ETL role failed with:

```text
Unknown user-defined function AUDIT_DB.MONITORING.SP_CAPTURE_CONSENT_PILOT_DEV.
```

After instructions to check existence and apply grants, the user reran
the invalid-ID call and supplied:

```text
Unexpected Consent pilot ID.
```

That demonstrates the procedure was reached and its guard executed; it
does not prove the successful insert path or a target record.

Before the run, the tracking count was zero. Logging-procedure grants
explicitly showed `USAGE` for `R_NAS_ETL_DEV` on:

```text
AUDIT_DB.MONITORING.SP_D365_LOG_RESPONSE(
    VARCHAR, VARCHAR, VARCHAR, NUMBER, VARCHAR, VARCHAR, VARCHAR
)
```

This confirms execution permission, not logging correctness. The user
reported ADF validation and later run success but did not supply individual
activity results, a run ID, captured row or final audit output.

## Proof queries: RE extract -> Snowflake -> Dynamics

### 1. RE extract evidence

```sql
SELECT
    ID AS RE_ATTRIBUTE_ID,
    ATTRIBUTENAME AS RE_CHANNEL,
    ATTRIBUTEVALUE AS RE_PREFERENCE,
    ATTRIBUTEDATE AS RE_PREFERENCE_DATE
FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTATTRIBUTES
WHERE ID IN (2273445, 2273446, 2273447, 2273448)
ORDER BY ATTRIBUTENAME;
```

Expected: four No Donations rows, one per channel, dated 23 August 2012.
The supplied full-history result already included those rows. This query
reads the RE extract held in Snowflake, not the RE application directly.
It omits comments, names and contact details.

### 2. Snowflake tracking, audit and repeat-dispatch proof

```sql
SELECT TEST_KEY, D365_GUID, CAPTURED_AT
FROM AUDIT_DB.MONITORING.CONSENT_PILOT_TRACKING_DEV
WHERE TEST_KEY = 'CONSENT_TEST:2273445';

SELECT *
FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE
WHERE ENTITY_ID = 'CONSENT_TEST'
  AND GOLDEN_RECORD_ID = 'CONSENT_TEST:2273445';

SELECT COUNT(*) AS DISPATCHABLE_ROWS
FROM INTEGRATION_DB.DYNAMICS.VW_D365_CONSENT_PILOT_REQUESTS_DEV;
```

Expected after a verified successful run: exactly one matching tracked ID,
an audit state indicating success and zero dispatchable rows. These final
results are **not yet supplied**. Zero requests alone does not prove
creation: changed source/identity/metadata can also hold the request.
Review audit output for sensitive details before sharing it with managers.

### 3. Dynamics API readback

```text
https://nasdatamig.crm11.dynamics.com/api/data/v9.2/mha_consents(9d1fdf0d-00cd-40a0-a40d-8e06e6053af8)?$select=mha_consentid,mha_name,_mha_consentfor_value,_mha_consenttypeid_value,mha_email,mha_post,mha_sms,mha_telephone
```

Verify the planned ID, expected Contact and Donations type, with all four
channels equal to `862940001`. This readback remains outstanding.

[Open the planned pilot record](https://nasdatamig.crm11.dynamics.com/main.aspx?pagetype=entityrecord&etn=mha_consent&id=9d1fdf0d-00cd-40a0-a40d-8e06e6053af8).

Alternatively, in the matching Power Apps DEV environment, open
Tables -> Consent -> Data and look for `TEST-CONSENT-2273445`.
If the name differs, use the GUID and verify the actual values.
No target UI confirmation has yet been supplied.

## Workbook mapping and pilot gaps

| Row | Workbook field | Flag | Pilot treatment / gap |
|---:|---|:---:|---|
| 2896 | Declaration (`mha_consentdeclarationid`) | N | Omitted; workbook notes elsewhere say not to use declaration table. |
| 2897 | For (`mha_consentfor`) | N | Verified Contact binding. |
| 2898 | Consent (`mha_consentid`) | N | Fixed technical GUID. |
| 2899 | Type (`mha_consenttypeid`) | N | Existing Donations binding; application-required live. |
| 2900 | Effective From (`mha_effectivefrom`) | N | Omitted; source date not migrated. |
| 2901 | Email (`mha_email`) | Y | Explicit No Donations -> Out. |
| 2902 | Name (`mha_name`) | N | Synthetic test name; application-required live. |
| 2903 | Post (`mha_post`) | Y | Explicit No Donations -> Out. |
| 2904 | SMS (`mha_sms`) | Y | Explicit No Donations -> Out. |
| 2905 | Source (`mha_source`) | N | Omitted. |
| 2906 | Source ID (`mha_sourceid`) | N | Omitted; test identity retained only in Snowflake. |
| 2907 | Telephone (`mha_telephone`) | Y | Explicit No Donations -> Out. |
| 2921 | Consent Source (`mhnas_consentsource`) | Y | Workbook mentions Comment; mapping unresolved and omitted. |
| 2922 | Consent Source Note (`mhnas_consentsourcenote`) | Y | Workbook says single-line, max 50; mapping unresolved and omitted. |
| 2923 | For (`mhnas_consentfor`) | Y | Workbook custom name absent from supplied live attributes. |
| 2924 | By (`mhnas_declaredby`) | Y | Workbook custom name absent from supplied live attributes. |

There are eight Y fields. Other workbook fields in this object are N:
audit/system fields, owner, created-date override and state/status fields.

The supplied live metadata exposes `mhnas_sourcenote` and Contact lookup
`mhnas_consentby` (navigation `mhnas_ConsentBy`), not the four custom names
in rows 2921-2924. It also exposes `mha_source` and `mha_consentfor`, but
similar labels do not establish approved equivalents. Do not substitute
these automatically. Name/ID/Party/Type fields sent despite N flags are
pilot technical/dependency choices, not a workbook amendment.

## Outstanding business questions

1. **Scope and record grain:** Which people, historical periods, channels
   and types are in scope? Is the target one record per Party/type, a
   history of declarations, or another approved model?
2. **Consent interpretation:** Approve channel/type/value mappings,
   general opt-ins/opt-outs, FPS, assumed preferences, exclusions, blanks,
   unknown and retired values. Never infer permission from missing data.
3. **History and precedence:** How should multiple values, equal or
   missing dates, cross-channel/general conflicts and later corrections
   be handled? The pilot avoided rather than solved these cases.
4. **Missing types:** Confirm whether the four unresolved names should be
   created by mhance, mapped to approved existing types or excluded.
5. **Fields and metadata:** Reconcile workbook/live field differences.
   Confirm Consent Source, source notes, For/By, name, effective date,
   original dates, source identity and fields marked N that are needed
   to form a meaningful target record.
6. **Privacy and Party:** Approve Contact/Account handling, ambiguous or
   missing identities, suppressed constituents, comments, retention and
   access. Confirm the implications of writing historical consent as a
   current target record.
7. **Existing records and automation:** Agree matching, updates versus
   creation, manual Dynamics preferences and conflict handling. Confirm
   target automation and downstream effects for full loads, separately
   from the user's DEV-only safety confirmation.
8. **Transition and acceptance:** Agree field ownership, future changes,
   deletes, RE retirement/history retention, reconciliation, exceptions
   and business sign-off before full loading.

## Follow-up: missing destination records and dependencies

Revisit this issue before generalising the pilots into full-load routes.
For an in-scope source object, a missing destination record is a candidate
for creation, not an automatic migration exclusion. Required missing
lookup/parent records must be resolved first through an approved migration
load or their designated owner; do not omit required bindings or assume
that each child pipeline creates its dependencies.

The review confirmed one explicit own-record creation exception:
`VW_D365_MHA_CONSENTTYPE` returns EXISTS for matched types and HOLD for
missing types, with CLIENT_LOADS when no other gate applies. The workbook
assigns Consent Type loading to mhance. Confirm that ownership and how
missing types will be supplied; do not silently exclude affected Consents.
See [Consent Type handover](CONSENT_TYPE_DEV_HANDOVER.md).

Other reviewed pilot routes include POST creation, but fixed-record pilots
do not establish a general "load every missing record" implementation.
The count above is not a complete dependency-loading or full-load audit.

Follow-up review must:

- Check each configured object's missing-record creation path and pilot
  restrictions.
- Identify required missing references/parents, their loading owner and
  load order; retain explicit reasons for held records.
- Verify with a controlled DEV case that a missing in-scope record is
  created once, dependencies resolve, and a rerun does not duplicate it.
- Reconcile source, held, existing and created counts before full loading.

Third Party Supporter Reference remains unimplemented; its empty source
table requires an agreed source-row setup. Postcode now has a user-approved
synthetic Name-only DEV pilot and dispatcher route. Its deployed request
returned the expected payload and the user reported success; final target
readback, tracking and audit reconciliation remain outstanding.
See [Postcode handover](POSTCODE_DEV_HANDOVER.md). All 2,021,748
queried RE address rows returned the masked postcode placeholder ********,
so this pilot does not prove real RE postcode migration. Existing Postcode
values include areas and districts; confirm the intended record grain and
obtain an authorised usable source before loading missing RE values.
Neither destination absence nor existing reference data alone is a
migration exclusion rule.

## Next actions

1. Obtain the pending post-run tracking, audit, dispatch-count and Dynamics
   readback results. If anything is missing, reconcile this fixed GUID and
   the ADF activity history without repeating the POST.
2. Record the ADF run ID and outcomes of `WEB_Post`, `SCR_CAPTURE_XREF`
   and `SCR_LogPostSuccess`. Inspect any failure branches.
3. Once evidence agrees, mark this one opt-out pilot verified. Preserve
   test tracking and distinguish the test key from any future real-load
   identity; agree treatment of the existing pilot record before full load.
4. Resolve business decisions, update mappings/payload logic, and test
   representative cases, controlled batches and failure recovery before
   approving a full DEV load.
5. Return to the missing-destination/dependency review above. Confirm
   Consent Type provisioning and review the other configured routes before
   claiming they migrate all missing in-scope records.

Current manager-facing wording:

> A source-backed Donations opt-out pilot has been prepared and ADF success
> reported in DEV. The source has explicit opt-outs for all four channels.
> Final target readback, capture and audit reconciliation are outstanding.
> Full migration remains subject to business mapping and acceptance decisions.
