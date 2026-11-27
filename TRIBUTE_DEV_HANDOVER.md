# Tribute or Memory DEV pilot handover

## Status and scope

One Raiser’s Edge (RE) Tribute was prepared as a technical pilot for
Dynamics DEV. The user reported ADF success, but the post-run XREF and
Dynamics readback have not yet been supplied. **Creation and ID capture
are therefore not yet verified.** Do not rerun the POST to verify it.

This is not a full load, a complete Tribute record, or an ongoing
synchronisation. All work remains DEV-only.

| Item | Value |
|---|---|
| Workbook | [Source-to-target workbook](<./NAS DM Source to Target Mappings Current WIP 1.xlsx>), Mapping V6, rows 1694-1716 |
| Dynamics object | `msnfp_tributeormemory`, entity set `msnfp_tributeormemories` |
| RE source extract | `RAW.RAISERS_EDGE.VW_ODS_T_TRIBUTES` |
| Pilot RE Tribute | `1113` |
| Pilot XREF key | `TRIBUTE:1113` |
| Pipeline ID | `D365_TRIBUTE_PILOT` |

The workbook's populated Tribute source entries are in its FS columns,
not the RE columns. The RE mappings in this pilot need business approval
before a full load.

## What we did and why

1. Reviewed the workbook, the supplied RE extract columns, the existing
   Tribute type reference and the open load gates. Live Dynamics metadata
   confirmed that name and Tribute type are application-required and
   create-valid. State is not create-valid; status reason is create-valid.
2. Initially selected RE Tribute `37`, but held it: its constituent existed
   in the RE extract and had no matching RE XREF, leaving its privacy status
   unknown. It was not dispatched.
3. Selected active RE Tribute `1113`, type `In memory of`, with a
   19-character description and no notes. The user approved using its
   description in DEV and confirmed Tribute creation would not cause
   unwanted external or financial actions.
4. The Snowflake preview returned one source row, one golden record, zero
   unknown privacy rows and zero suppressed rows. It returned one matching
   extracted option for each of Tribute type and status, and
   `PILOT_CANDIDATE`. Before the run, there were no Dynamics XREF rows for
   `TRIBUTE:1113`.
5. Live Dynamics metadata confirmed `844060001` = `In Memory` and status
   reason `1` = `Active`, state `0`. A live search for the synthetic name
   `RE Tribute ID 1113` returned no match. This was a point-in-time name
   check, not a comprehensive duplicate-identity strategy.
6. Prepared a fixed one-record request and, with the user's permission,
   updated the local shared dispatcher. The compiled request view returned
   one `POST` to the DEV Tribute entity set, with the expected name,
   description length, type and status.
7. The user reported ADF success. The exact deployed ADF definition,
   individual activity results, post-run XREF, Dynamics ID and live record
   readback have not been independently confirmed.

## Pilot payload and limitations

| Dynamics field | Pilot value or treatment |
|---|---|
| `msnfp_name` | Synthetic name `RE Tribute ID 1113` |
| `msnfp_identifier` | Trimmed RE `DESCRIPTION`; actual text is not reproduced here |
| `msnfp_tributeormemorytypecode` | `844060001` (`In Memory`) |
| `statuscode` | `1` (`Active`) |
| `mhnas_description` | Omitted; the selected RE row has no notes |
| `overriddencreatedon` | Omitted; Date Added was not among the supplied RE extract columns |
| `statecode` | Omitted; live metadata reports it is not valid for create |
| Supporter, Tributee, Acknowledgee and Fund links | Not sent; relationships and their meaning need agreement |

The source `CONSTITUENTID` was used for the privacy/identity check, not
bound as a Dynamics lookup. A fundraiser navigation property does not by
itself establish that this RE constituent is a fundraiser. The pilot also
does not map RE start/end dates, sequence or default fund.

The workbook marks Description, Identifier, Name, ID, Tribute Type, Record
Created On and Status Reason for migration. Omitting fields in this pilot
does not approve omitting them from a full load.

## Code and safety

| File | Change or role |
|---|---|
| [Pilot preview](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_TRIBUTE_PILOT_PREVIEW_DEV.sql) | Fixed RE ID and source, privacy and extracted-option checks; constructs a draft payload only for a candidate. `PREVIEW_DISPATCH_ALLOWED = FALSE` is informational. |
| [Pilot requests](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_TRIBUTE_PILOT_REQUESTS_DEV.sql) | Fixed DEV POST, description-length check, and writeback-state and Dynamics-XREF exclusion guards. Uses the Campaign metadata row as a DEV connection template without enabling the general Campaign load. |
| [Dispatcher JSON](<./ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>) | Added the pilot request-view route, returned `msnfp_tributeormemoryid` selection and XREF capture branch. |
| [Tribute type reference](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_REF_TRIBUTE_TYPE.sql) | Existing proposed type mappings; not changed or approved for a full load. |
| [Load gates](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_REF_LOAD_GATE.sql) | `TRIBUTE_CUSTOMER_LINK` and `TRIBUTE_SCOPE` remain open; they were not changed for this pilot. |

The dispatcher JSON parsed and its changed ADF expressions passed static
quote and delimiter checks. Removing the three Tribute wrappers restored
the previous expressions exactly. This is not a live regression test of
all previous objects. The live generic XREF procedure has worked for
other pilots, but its local export has an empty body and its Tribute
result must be verified.

The request guards are not atomic and the Snowflake extracts can lag.
The description-length check does not prove that the description text
has not changed. The live name search is not a complete duplicate check.
Do not run concurrent creates or blindly retry an uncertain POST;
reconcile ADF activity results, live Dynamics, XREF and writeback state
first.

## Read-only proof: RE, Snowflake, Dynamics

Run the following checks and compare results. The source query reads an
RE **extract in Snowflake**, not the live RE application. A current
extract or preview is not an immutable record of what was sent at run
time. Keep personal descriptions private when sharing evidence.

### 1. RE source extract

```sql
SELECT ID, TRIBUTETYPEDESCRIPTION, DESCRIPTION, ACTIVE
FROM RAW.RAISERS_EDGE.VW_ODS_T_TRIBUTES
WHERE ID = 1113;
```

### 2. Snowflake

```sql
SELECT RE_TRIBUTE_ID, SOURCE_ROWS, GOLDEN_RECORDS,
       UNKNOWN_PRIVACY_ROWS, SUPPRESSED_ROWS,
       TYPE_OPTION_MATCHES, STATUS_OPTION_MATCHES, PREVIEW_STATUS
FROM INTEGRATION_DB.DYNAMICS.VW_D365_TRIBUTE_PILOT_PREVIEW_DEV;

SELECT GOLDEN_RECORD_ID, SOURCE_RECORD_ID AS DYNAMICS_TRIBUTE_ID
FROM MDM_DB.GOLD.XREF
WHERE SOURCE_SYSTEM = 'DYNAMICS'
  AND GOLDEN_RECORD_ID = 'TRIBUTE:1113';
```

The XREF should contain exactly one valid Dynamics ID. A request-view row
may disappear after successful state or XREF capture; that alone does not
prove the record was created. Review ADF's POST and capture activities
and writeback audit as well.

### 3. Dynamics DEV

```text
GET https://nasdatamig.crm11.dynamics.com/api/data/v9.2/msnfp_tributeormemories?$select=msnfp_tributeormemoryid,msnfp_name,msnfp_identifier,msnfp_tributeormemorytypecode,statecode,statuscode&$filter=msnfp_name%20eq%20%27RE%20Tribute%20ID%201113%27
```

Confirm exactly one matching record, its ID matches XREF, type is
`844060001`, and state/status are `0`/`1`. Privately compare the
identifier with the source description, allowing for the pilot's trimming.
If the source changed after dispatch, current values alone do not prove
the original payload. If a result is missing, duplicated or inconsistent,
reconcile rather than retrying.

## Business questions for a full load

1. **Scope:** Are RE Tributes in scope despite the workbook's FS source
   mappings? Which active, inactive and historical records should migrate?
2. **Identity and duplicates:** Is `TRIBUTE:<RE ID>` the agreed XREF
   identity? How should existing Dynamics Tributes and duplicate or
   ambiguous records be matched, including records without this pilot name?
3. **Relationships:** What does RE `CONSTITUENTID` represent for each
   Tribute? How should the supporter, Tributee, Acknowledgee and fundraiser
   be represented, and what happens when links are missing or ambiguous?
4. **Privacy:** What is the approved policy for suppressed, unknown or
   missing constituent identities, including the unresolved Tribute `37`?
5. **Type mapping:** Confirm every RE type, including celebrations and
   `Other`, against live Dynamics options. The existing mapping is a
   proposal, not a business decision.
6. **Fields and dates:** Confirm the RE sources and rules for name,
   identifier, notes/description, record-created date, start/end dates,
   sequence and default fund. How should blanks, invalid dates and
   over-length values be handled?
7. **Status and defaults:** How should active and inactive RE records map
   to Dynamics state/status? Which owners, defaults and automations are
   appropriate for migrated records?
8. **Transition and acceptance:** Which RE changes should create, update
   or retire Dynamics records during transition? Who approves mappings,
   exceptions, reconciliation and the point at which the RE flow stops?

## Work before a full load

1. Complete the three-way pilot proof above and resolve any mismatch
   without creating another record. Decide whether the pilot record needs
   completion or correction under the agreed business rules.
2. Agree the open gates, mappings and privacy policy; re-profile the current
   source and target for scope, duplicates, identities and relationships.
3. Build a separate generalised, held-first DEV load with explicit exception
   reasons and approved mappings. Design safe identity, reconciliation,
   non-overlapping batches and recovery from uncertain POSTs.
4. Reconcile approved loads across RE, Snowflake, Dynamics, XREF and audit.
   Separately design and test the transition update path; this pilot does
   not implement one.
