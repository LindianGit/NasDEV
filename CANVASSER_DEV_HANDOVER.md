# Canvasser DEV pilot handover

## Status and scope

This is a **one-record technical pilot**, not a full load or a confirmed
business Canvasser assignment. All work and any further testing remain in
DEV. Business rules, field mappings and the population to migrate are not
yet agreed.

The user reported that the ADF DEV run succeeded. A Canvasser XREF result
and Dynamics record readback have **not** yet been supplied, so the creation
and captured Dynamics ID are not verified. A successful pipeline run alone
does not prove a record was created; it may have processed no requests.

| Item | Value |
|---|---|
| Workbook object name | Canvasser; the workbook calls the table Canvassers |
| Dynamics logical name | `mhnas_canvasser` |
| Dynamics entity set | `mhnas_canvassers` |
| RE relationship extract | `RAW.RAISERS_EDGE.VW_ODS_T_RELATIONSHIPS` |
| RE constituent extract | `RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT` |
| Pilot pipeline ID | `D365_CANVASSER_PILOT` |
| Pilot XREF key | `CANVASSER:189986` |

The Dynamics logical name and entity set were checked against DEV metadata;
the live display label was not checked. The Snowflake views are RE extracts,
not the live RE application.

## What was done

1. Reviewed Canvasser in the local WIP workbook, **Mapping V6**, rows
   2809-2830, and checked Dynamics DEV metadata and RE source information.
2. Profiled relationship rows involving flagged canvassers and reviewed
   relationship descriptions. A canvasser flag alone does not establish that
   a relationship is a canvassing assignment.
3. Selected RE relationship `189986`, with constituent `672036` and related
   constituent `395086`. The latter is flagged as a canvasser and was
   matched to an active Dynamics System User using an identifier verified by
   the user. The Dynamics Contact was also confirmed active.
4. The user could not confirm whether this is a genuine canvassing
   assignment and explicitly approved the pair **only as a provisional DEV
   technical test**. The user also confirmed that creating it in DEV would
   not trigger external actions.
5. A Dynamics DEV search for existing Canvasser records for the Contact
   returned no rows at that time. This was a point-in-time check, not a
   general duplicate-detection mechanism.
6. Prepared fixed preview and request views. The user created them in
   Snowflake DEV and saw one `PILOT_CANDIDATE` and one POST request.
7. Added a Canvasser route, response-ID selection and XREF capture branch
   to the local dispatcher. The JSON and expressions passed static checks.
   The user operated ADF DEV and reported success; publication status and
   equivalence to the local file are not confirmed here.

### Pilot evidence

| Layer | Result |
|---|---|
| RE relationship | `189986`: constituent `672036`, related constituent `395086` |
| Proposed canvasser | RE `395086`; Dynamics System User `9b050b25-7103-ed11-82e5-000d3a0cbb18` |
| Proposed customer | RE `672036`; Dynamics Contact `f2df31e4-9be0-f111-84ea-70a8a575b5fc` |
| Preview | `PILOT_CANDIDATE`; `PREVIEW_DISPATCH_ALLOWED = FALSE` |
| Request | One POST with key `CANVASSER:189986` |
| ADF DEV | User reported success; activity-level POST result not supplied |
| XREF and Dynamics readback | Not yet supplied; create and ID capture unverified |

The preview's `PREVIEW_DISPATCH_ALLOWED` is an informational false marker;
the separate request view uses the preview status and its own guards. It is
not itself a dispatch authorisation mechanism.

### Pilot payload

```json
{
  "mhnas_Canvasser@odata.bind": "/systemusers(9b050b25-7103-ed11-82e5-000d3a0cbb18)",
  "mhnas_Customer_contact@odata.bind": "/contacts(f2df31e4-9be0-f111-84ea-70a8a575b5fc)"
}
```

No Type, Start Date or End Date was sent. The payload is a minimal test,
not an approved complete mapping. The lookup navigation names were checked
against the supplied Dynamics metadata snapshot.

The user ran with `PipelineId=D365_CANVASSER_PILOT`,
`SourceInstance=SNOWFLAKE_DEV`, `EntityId=CANVASSER`, and
`TestRowsPerCombo=1`.

## Verify the pilot before any retry

First inspect the XREF:

```sql
SELECT GOLDEN_RECORD_ID, SOURCE_SYSTEM, SOURCE_RECORD_ID
FROM MDM_DB.GOLD.XREF
WHERE GOLDEN_RECORD_ID = 'CANVASSER:189986'
  AND SOURCE_SYSTEM = 'DYNAMICS';
```

If there is exactly one valid Dynamics GUID, use it in the following
read-only Dynamics DEV request, replacing `<DYNAMICS_GUID>`:

```text
GET https://nasdatamig.crm11.dynamics.com/api/data/v9.2/mhnas_canvassers(<DYNAMICS_GUID>)?$select=mhnas_canvasserid,_mhnas_canvasser_value,_mhnas_customer_value,mhnas_type
```

Confirm the ID and both lookups against the pilot evidence above. Also
inspect the ADF activity result and writeback audit. If XREF is missing,
duplicated or does not agree with Dynamics, reconcile the live target,
writeback state and ADF result before deciding what to do. Do **not** blindly
retry a POST: it may have created a Dynamics record despite an uncertain
response or missing XREF.

## Implementation and limitations

- [Pilot preview](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_CANVASSER_PILOT_PREVIEW_DEV.sql)
- [Pilot request view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_CANVASSER_PILOT_REQUESTS_DEV.sql)
- [Local dispatcher](<./ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>)
- [Source-to-target workbook](<./NAS DM Source to Target Mappings Current WIP 1.xlsx>)
- [Connection view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_CONNECTION.sql)

The preview fixes the relationship and person IDs, checks source and
identity uniqueness, flags, privacy state and Contact resolution, and
constructs the minimal payload. It uses a fixed, manually verified System
User ID. The request view restricts the DEV endpoint and uses writeback
state and Dynamics XREF guards.

These are not a full-load implementation. The guards do not query Dynamics
for duplicates and do not provide atomic concurrency control. The view
produces only a create POST, not an update. Do not remove the fixed filters
and use it as a batch loader.

The existing Connection view holds relationships involving a flagged
canvasser. This is not proof that all such relationships belong in
Canvasser or should be excluded from Connection. Agree and reconcile the
two object populations before full loading.

## Workbook mapping and gaps

Confirm the authoritative workbook and resolve each migration/sync field
before a full load. A workbook `Y` is not the same as a Dataverse
create-required setting.

| Mapping V6 row | Field | Flag | Pilot and decision |
|---:|---|:---:|---|
| 2813 | Canvasser lookup (`mhnas_canvasser`) | N | Pilot binds an active System User. Metadata says the lookup is create-valid and optional. Agree the user-matching rule and resolve the workbook flag. |
| 2814 | Canvasser ID (`mhnas_canvasserid`) | Y | Primary record ID, not the user lookup. The workbook note mentions finding a User ID; clarify the intent. Dynamics ID capture remains unverified for this pilot. |
| 2815 | Customer | Y | Pilot binds one Contact. Agree Contact/Account scope and identity handling. |
| 2816 | End Date | Y | Marked deprecated in the workbook and omitted from the pilot. Decide whether and where historical end dates belong. |
| 2818 | Start Date | Y | Omitted; confirm source, meaning and missing-value handling. |
| 2819 | Type (`mhnas_type`) | Y | Omitted; no reliable RE-to-Dynamics type mapping has been agreed. Dynamics metadata says it is create-valid and optional. |

The workbook covers additional rows; review all of them, including any
fields marked N and target defaults, rather than assuming this table is the
complete object mapping. The source inventory includes relationship
`DATE_FROM` and `DATE_TO`, but their business meaning for this object must
be confirmed. A confirmed RE `Canvasser_type` source was not identified.

## Point-in-time profiling

The earlier relationship profile found 1,099 rows with only the related
side flagged as canvasser, 910 with only the constituent side flagged,
384 with the constituent side flagged and the related flag unknown, and
193 with both sides flagged. These are relationship-row counts, not counts
of distinct relationships or confirmed assignments. Re-run the diagnostics
against current DEV data before sizing a full load.

Relationship descriptions included ordinary relationships such as Contact,
Friend, Employer and Supported By, as well as blanks. This reinforces the
need for an approved assignment rule; the flag does not by itself establish
which rows belong in Dynamics Canvasser.

## Business questions for a full load

Record answers, approvers and any exceptions against the authoritative
mapping before implementation.

1. **Purpose and scope:** What does a Canvasser record mean in Dynamics?
   Which RE records represent real canvassing assignments? Are historical,
   ended and inactive assignments included, and is there a date cutoff?
2. **Identifying assignments:** Which RE relationship types and
   relationship/reciprocal descriptions qualify? Are there other source
   fields or authoritative lists? How should blank or ambiguous descriptions
   be handled? Is the pilot pair `189986` a real assignment, and should it
   be retained, corrected or removed in DEV?
3. **Direction:** Which party is the canvasser and which is the customer
   for each relationship direction? What should happen when both parties
   are flagged, a flag is unknown, or neither is flagged?
4. **Connection overlap:** Should qualifying relationships be represented as
   Canvassers, Connections, both, or neither? How should non-canvassing
   relationships involving a canvasser-flagged person be handled?
5. **Dynamics user:** Must every canvasser be a Dynamics System User? How
   should RE canvassers be matched reliably to users, including former staff,
   disabled users, missing users and multiple possible matches? May an
   assignment be loaded without a user, despite the lookup being optional
   in API metadata?
6. **Customer:** Can the customer be a Contact, an Account, or either?
   What is the approved action for a missing, inactive, ambiguous or
   suppressed customer, or a customer not yet migrated?
7. **Type:** What do the Dynamics Canvasser Type choices mean and which
   RE fields determine them? How should blank, unknown or unmapped types
   be handled? Is an approved default permitted?
8. **Dates and status:** Do `DATE_FROM` and `DATE_TO` represent the
   assignment's start and end? What happens when dates are absent,
   inconsistent or in the future? Given the workbook's deprecated End
   Date, where should historical end dates and active/inactive status go?
9. **Identity and duplicates:** Is one RE relationship one Dynamics
   assignment? How should reciprocal rows, repeated assignments for the
   same user and customer, overlapping dates and existing Dynamics records
   be matched, merged, retained or held?
10. **Remaining fields and privacy:** For every workbook field, what is the
    source or derivation, acceptable missing value, default and exception?
    Are there privacy or retention restrictions on either party or on
    historical assignments?
11. **Transition updates:** Which system owns each field while RE remains
    operational? Which RE creations, corrections, endings and deletions
    should update Dynamics, how often, and how should conflicting changes
    and records created directly in Dynamics be handled? Is any reverse
    update to RE or synchronisation with HubSpot required for this object?
12. **Acceptance and retirement:** Who approves the mapping, exceptions,
    counts and representative samples? What retained RE snapshot and
    identity history are required for reconciliation after RE retirement,
    and when may the RE-to-Dynamics flow be stopped?

## Work required before a full load

1. Verify and reconcile the pilot, including the provisional assignment and
   its omitted fields. Resolve any uncertain create before further dispatch.
2. Agree and record the business answers; update the authoritative mapping
   and validate target metadata, navigation properties and DEV automations.
3. Re-profile source relationships using the approved definition. Measure
   eligible rows and explicit holds for direction, users, customers,
   privacy, duplicates, types, dates and missing target dependencies.
   Reconcile Canvasser and Connection coverage.
4. Build a separate generalised DEV preview and request path, with stable
   identity, approved field mappings, per-row hold reasons, target duplicate
   and XREF conflict checks, and payload validation.
5. Design bounded non-overlapping DEV batches, monitoring, reconciliation,
   recovery from uncertain POSTs and safe reruns. Start with small approved
   batches and reconcile source, ADF, Dynamics, XREF and writeback audit.
6. After full-load design, develop and test the agreed change-detection
   and update path for the transition. The local dispatcher has a generic
   PATCH branch, but this Canvasser pilot generates no PATCH requests and
   does not establish ongoing synchronisation. Agree cutover and safe
   retirement of RE-dependent flows separately.
