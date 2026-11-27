# Historic Activity DEV pilot handover

## Status and scope

One Raiser’s Edge (RE) Action was prepared as a notes-free technical pilot
for Dynamics DEV. The user reported ADF success, but has not supplied the
post-run XREF or Dynamics readback. **Creation and ID capture are not yet
verified.** Do not rerun the POST to verify it.

The objective is a full DEV load where feasible; otherwise, the strongest
practical pilot. This pilot is not a full load or an ongoing update process.
All work remains DEV-only.

| Item | Value |
|---|---|
| Workbook | [Source-to-target workbook](<./NAS DM Source to Target Mappings Current WIP 1.xlsx>), Mapping V6, rows 392-419 |
| Dynamics object | `mha_historicactivity`, entity set `mha_historicactivities` |
| RE source extracts | `RAW.RAISERS_EDGE.VW_ODS_T_ACTIONS` and `VW_ODS_T_ACTIONNOTES` |
| Pilot RE Action | `24` |
| Pilot XREF key | `HISTORICACTIVITY:24` |
| Pipeline ID | `D365_HISTORICACTIVITY_PILOT` |

## What we did and why

1. Reviewed the workbook, the supplied RE extract columns and live Dynamics
   metadata. Dynamics reports `mha_subject` as application-required and
   create-valid. The supplied Action columns do not include the workbook's
   Action Subject, Import ID or Created On fields.
2. Profiled the RE extracts without returning activity or note text. At that
   point there were **73,969,858 Action rows**, the same number of distinct
   Action IDs, no missing constituent IDs, and a parseable date in the first
   ten characters of every Action date. **69,998,490 Action rows** had at
   least one related note. These are point-in-time extract counts, not an
   approved migration scope.
3. Prepared a read-only candidate view that excludes Actions with notes and
   checks constituent XREF, known non-suppressed privacy status and a unique
   Dynamics Contact or Account identity. It returned candidate Action `24`
   with an Account. The user approved a synthetic subject and Action ID as
   provisional pilot mappings, omitting notes, type and original created date.
4. The user confirmed DEV creation would not trigger unwanted external
   actions. Live metadata confirmed the Account navigation property and
   entity set. Activity Date is displayed as DateOnly but has UserLocal
   behaviour; the user approved midnight UTC for this pilot, with later API
   and UI date verification. This is not a full-load timezone rule.
5. The fixed preview found Action `24`, date `1999-09-01`, and Account
   `199c60cd-02e1-f111-84ea-70a8a575b5fc`. A live Dynamics search found
   no matching source ID or synthetic subject, and the Account was active.
   The search was a point-in-time check, not a complete duplicate strategy.
6. With the user's permission, added a fixed one-record request and local
   shared-dispatcher routing. The compiled request view returned one POST
   with the five approved fields. The user reported ADF success; the exact
   deployed ADF definition, activity results, XREF and target record have
   not been independently confirmed.

## Pilot payload and limitations

| Field | Pilot treatment |
|---|---|
| `mha_subject` | Synthetic `RE Action 24`; not the original Action Subject |
| `mha_source` | `Raisers Edge` |
| `mha_sourceid` | RE Action ID `24`; not a verified Action Import ID |
| `mha_activitydate` | `1999-09-01T00:00:00Z`; verify API and UI date |
| `mha_CustomerId_account@odata.bind` | Verified DEV Account binding |
| Notes, title and description | Omitted; selected source Action has no note rows |
| Activity type, original created date and source status | Omitted; mappings remain open |

The pilot does not establish that the synthetic subject or RE Action ID is
the correct business mapping for a full load. It does not prove that the
Activity Date appears as the intended date in every user's time zone.
Dynamics state, status, owner and other defaults must be checked on readback;
the pilot did not send them.

The workbook's Action Date and constituent ID entries are in its FS source
columns. Its RE source column names Action Import ID, Subject, Notepad Title,
Created On and Status. The supplied live target attribute list did not
include the workbook's `mhnas_title`; investigate before mapping it.

## Code and safety

| File | Change or role |
|---|---|
| [Candidate view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_HISTORICACTIVITY_PILOT_CANDIDATES_DEV.sql) | Read-only privacy and identity screening; excludes Actions with notes. |
| [Pilot preview](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_HISTORICACTIVITY_PILOT_PREVIEW_DEV.sql) | Fixed Action `24`, source-uniqueness check and provisional five-field payload. |
| [Pilot requests](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_HISTORICACTIVITY_PILOT_REQUESTS_DEV.sql) | Fixed DEV POST, exact payload and customer checks, plus state and XREF exclusion guards. Uses the Campaign metadata row as a DEV connection template. |
| [Dispatcher JSON](<./ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>) | Added the pilot request-view route, returned `mha_historicactivityid` selection and XREF capture branch. |
| [Load gates](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_REF_LOAD_GATE.sql) | `HISTORIC_ACTIVITY_SCOPE` remains open; it was not changed for this pilot. |

The preview's `PREVIEW_DISPATCH_ALLOWED = FALSE` is informational; the
separate request view applies its own guards. After a successful capture or
writeback-state entry, a candidate or request may no longer be returned.
That alone does not prove creation.

The dispatcher JSON parsed and its changed expressions passed static quote
and delimiter checks. Removing the three Historic Activity wrappers restored
the previous expressions exactly. This is not a live regression test of
earlier objects. The generic XREF procedure has worked for other pilots, but
its local export has an empty body; its Historic Activity result must be
verified.

The duplicate, state and XREF checks are not atomic, and Snowflake extracts
can lag. ADF lookup output can expose the Account GUID and Activity Date.
Do not run concurrent creates or blindly retry an uncertain POST; reconcile
ADF activity results, live Dynamics, XREF and writeback state first.

## Read-only proof: RE, Snowflake, Dynamics

The RE query below reads an **extract in Snowflake**, not the live RE
application. Current source data is not an immutable record of what was
sent. Keep personal activity and note text out of shared evidence.

### 1. RE source extract

```sql
SELECT ID, DATE
FROM RAW.RAISERS_EDGE.VW_ODS_T_ACTIONS
WHERE ID = 24;

SELECT COUNT(*) AS NOTE_ROWS
FROM RAW.RAISERS_EDGE.VW_ODS_T_ACTIONNOTES
WHERE ACTIONID = 24;
```

### 2. Snowflake

```sql
SELECT GOLDEN_RECORD_ID, SOURCE_RECORD_ID AS DYNAMICS_ID
FROM MDM_DB.GOLD.XREF
WHERE SOURCE_SYSTEM = 'DYNAMICS'
  AND GOLDEN_RECORD_ID = 'HISTORICACTIVITY:24';

SELECT LAST_HTTP_STATUS, IS_RETRYABLE, ATTEMPT_NO,
       LAST_ATTEMPTED_AT, LAST_ERROR_CODE
FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE
WHERE ENTITY_ID = 'HISTORICACTIVITY'
  AND GOLDEN_RECORD_ID = 'HISTORICACTIVITY:24';
```

Confirm exactly one valid Dynamics ID in XREF and inspect the ADF POST,
capture and audit results. A successful pipeline can also represent zero
dispatched rows.

### 3. Dynamics DEV

```text
GET https://nasdatamig.crm11.dynamics.com/api/data/v9.2/mha_historicactivities?$select=mha_historicactivityid,mha_source,mha_sourceid,mha_subject,mha_activitydate,_mha_customerid_value,statecode,statuscode&$filter=mha_sourceid%20eq%20%2724%27%20or%20mha_subject%20eq%20%27RE%20Action%2024%27
```

Confirm exactly one matching pilot record, its ID matches XREF, its Account
matches the pilot, and source, subject and API date match the payload.
Verify the displayed date in Dynamics UI as well. If a result is missing,
duplicated or inconsistent, reconcile before deciding whether to retry.

## Business questions for a full load

1. **Scope and retention:** Which Actions and historical periods are in
   scope? Should all 73.9 million profiled rows be considered, and what
   retention or exclusion rules apply?
2. **Privacy and notes:** Which Action subjects, note titles and note
   contents may be migrated to Dynamics? What access controls, retention and
   treatment of suppressed or unresolved constituents are required?
3. **Identity and duplicates:** Is RE Action ID or Action Import ID the
   stable source identity? Where is Import ID extracted, and how should
   existing Dynamics activities and duplicates be matched?
4. **Subject and description:** Where is the original Action Subject?
   How should missing subjects, multiple notes, titles and descriptions be
   represented? Is `mhnas_title` available in the target?
5. **Customer and relationships:** Confirm Contact/Account resolution and
   the rules for missing or ambiguous customers, Campaigns and other links.
6. **Type and status:** How do RE communication type, channel, completed
   flag and status map to Dynamics Activity Type and Status Reason? What
   should happen for unknown or unmapped values?
7. **Dates and ownership:** Where is the original created date? How should
   Action dates, timestamps, time zones, owners and target defaults be
   handled, including dates missing or invalid at load time?
8. **Automation and acceptance:** Which Dynamics automations may run during
   migration? Who approves scope, mappings, privacy controls, exceptions
   and reconciliation before a full load?
9. **Transition:** Which RE changes should create or update activities
   until retirement, and how should deletes and conflicts be handled?

## Work before a full load

1. Complete the three-way pilot proof and UI date check. Resolve any
   mismatch without creating another record; decide whether the synthetic
   pilot should be corrected or retained.
2. Agree the open scope, privacy, field, identity, status and date rules.
   Locate and validate the missing source fields and target title field.
3. Re-profile the current source, target, identities and duplicates. Design
   a separate held-first, scalable DEV load with explicit exceptions,
   access controls, bounded batches and uncertain-POST recovery.
4. Reconcile approved loads across RE, Snowflake, Dynamics, XREF and audit.
   Separately design and test the transition update path; this pilot does
   not implement one.
