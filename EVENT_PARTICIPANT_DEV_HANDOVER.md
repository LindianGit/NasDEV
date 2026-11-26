# Event Participant DEV handover

## Status and scope

This handover records a one-row Event Participant pilot in Dynamics 365 DEV.
It is **not** approval or readiness evidence for a full load. All further
profiling, changes, and dispatches remain DEV-only until the business signs off
on scope and mappings.

The Raiser’s Edge Event Participant is represented in Dynamics by the
**Event Participant** table (`msnfp_eventpackage`; entity set
`msnfp_eventpackages`).

## Completed

1. Identified RE participant `115847` as the pilot candidate. It belongs to
   RE Event `1004` and constituent `558745`; the source status is `Accepted`
   and participation is `Delegate`.
2. Found why the initial participant diagnostic had no resolved parent Event:
   the Event view did not use captured DEV Event IDs as a fallback. The local
   Event view was updated to use those IDs and hold conflicts. After the user
   compiled it in Snowflake DEV, the diagnostic found 357 Events with IDs and
   one complete participant candidate. These are historical diagnostic
   counts; re-profile before planning a load.
3. Prepared a read-only candidate preview with guards for unique source row,
   resolved Event, a unique Contact, no Account ambiguity, privacy status,
   mapped status, and a unique status/state metadata match.
4. Prepared a single-row request using only confirmed fields. The payload
   included `mha_source = RE`, `mha_sourceid = 115847`, Event and Contact
   bindings, `statecode = 0`, `statuscode = 844060001` (Accepted), and
   `overriddencreatedon = 2015-12-09`. This was a minimal technical pilot,
   not a mapping-complete participant record.
5. Added a local `D365_EVENTPARTICIPANT_PILOT` route to the dispatcher JSON,
   including response-ID selection and XREF capture. The JSON was parsed and
   statically checked. The user reports validating and running the route in
   ADF DEV; publication state is not confirmed here.
6. Confirmed the DEV write:
   - Writeback audit: HTTP 201, one attempt, non-retryable, no error code or
     error message.
   - XREF: `EVENTPARTICIPANT:115847` maps to Dynamics GUID
     `afd0dac4-ede8-f111-84e9-70a8a575b39d`.
   - Dynamics readback returned that Event Participant record with
     `mha_source = RE`, `mha_sourceid = 115847`, `statecode = 0`, and
     `statuscode = 844060001`.

This verifies the create and identity capture for one row. The readback so far
did not include the Event and Contact lookups, so verify those bindings as
part of pilot acceptance.

## Relevant implementation

- [Event Participant preview](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_EVENTPARTICIPANT_PILOT_PREVIEW_DEV.sql)
- [Single-row request view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_EVENTPARTICIPANT_PILOT_REQUESTS_DEV.sql)
- [Participant status mapping](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_REF_PARTICIPANT_STATUS.sql)
- [Dynamics Event view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_MSNFP_EVENT.sql)
- [Dispatcher JSON](./ADF%20Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json)

The pilot request view is deliberately hard-coded to participant `115847`,
the pilot pipeline ID, and a duplicate check for source ID `115847`. Do not
remove those filters and use it as a full-load view.

## Alignment with the source-to-target workbook

The local WIP workbook’s Mapping V6 rows 899–952 identify `msnfp_eventpackage`
as Event Participant. The pilot aligns with key rows for `mha_source`,
`mha_sourceid`, Customer, Event, `statecode`, `statuscode`, and
`overriddencreatedon`.

The pilot’s `Accepted` status code is present in the workbook’s status list.
However, the workbook lists the `statuscode` source as Event Participant /
Participation, while the pilot logic prefers RE `STATUSDESCRIPTION` and only
falls back to `PARTICIPATIONDESCRIPTION` for selected values. The candidate
had `STATUS = Accepted` and `PARTICIPATION = Delegate`, so the pilot sent
Accepted. Confirm the intended source-field precedence with the mapping owner
before scaling.

However, the workbook’s “Required field for migration/sync” column also marks
many fields omitted from the pilot as `Y`. Examples include Identifier, Date,
Appeal, Campaign, Package, Primary Participant, Response Channel, Dietary
Requirements, Fundraising Target, and participant attributes/new fields. The
workbook contains unresolved notes for several of these: Identifier may need
an autonumber or concatenation rule; Date needs an Own Place decision;
guest/primary participant handling needs review; and participant attributes
and new fields are linked to DevOps ticket 733. Access Requirements is flagged
`Y` but also noted as old sensitive data that may not need retaining.

The pilot therefore proves that a minimal create and ID capture can work; it
does **not** satisfy the workbook’s full migration/sync mapping. The workbook
flag is not the same as Dataverse create-required metadata: the record was
accepted without these fields, but that does not make their omission an
approved migration decision. Resolve each `Y` field with the business and
mapping owner, including whether it is populated, calculated, held, excluded,
or handled in another object. Reconcile this WIP workbook against the
authoritative project mapping before full-load design.

## Work required before a full load

1. **Agree the population and rerun profiling.** The earlier diagnostic
   reported 526,505 source participants, 460,903 with mapped status values,
   initially zero Events resolved, then 357 resolved Events and one complete
   candidate after the Event-ID fallback. Re-run counts against current DEV
   data, including unique participant IDs, parent Event matches, Contact and
   Account matches, privacy/suppression, duplicate Dynamics `mha_sourceid`,
   status mapping, and final eligible/held counts.
2. **Complete status decisions.** The current status view has 18 mapped
   values and the earlier full-population profile found 13 unresolved values.
   `NEW`, `UNMAPPED`, and `NO_D365_OPTION` values must remain held until
   decisions are agreed and the mappings are updated and revalidated.
3. **Resolve parent and customer coverage.** Every eligible row needs exactly
   one valid Dynamics Event and a permitted customer binding. The pilot allows
   one Contact and holds account matches, ambiguous links, unresolved
   suppression state, and suppressed constituents. Define handling for
   missing Events, accounts, duplicate Contacts, and privacy holds.
4. **Close workbook-required field decisions.** The workbook flags fields
   omitted from the pilot as required for migration/sync. Resolve their source
   mapping, business rule, target dependency, or approved exclusion before
   building the full request. Do not silently treat an omitted field as
   optional merely because Dataverse accepted the pilot without it.
5. **Build a separate full-load preview and request view.** Remove the
   single-record restrictions only in a new full-load design. Retain
   per-record hold reasons, source uniqueness, idempotency checks, target
   duplicate checks, XREF conflict checks, and payload validation. Use a
   distinct pipeline ID and ensure the request view only returns approved,
   eligible rows.
6. **Design controlled batch execution.** The current pilot is one row. The
   dispatcher’s generic `TestRowsPerCombo = 0` path does not provide a
   participant-specific full-load cap. Add explicit bounded batch behavior,
   ordering, restart/reconciliation procedure, and concurrency controls before
   scaling. Start with small DEV batches and review every failed or uncertain
   POST before retrying.
7. **Agree ongoing behavior and sign-off.** Decide whether this is a one-time
   migration or an ongoing sync, how source corrections/deletions are handled,
   and who accepts the final reconciliation. The XREF and writeback audit prove
   captured responses, not ongoing synchronization or later Dynamics edits.

## Business questions

1. Which Event Participants are in scope: all historical rows, only current
   or active registrations, or a date-bounded subset? Are cancelled,
   duplicate, transferred, rejected, and completed records included?
2. For each unresolved RE `STATUS` value, what Dynamics status should it map
   to, or should the row be excluded/held? Specifically, what do values such
   as `OP`, `GB`, `Pack Sent`, `Pending`, `Planned`, `Multiple Event`, and
   `OP&GB` mean operationally?
3. Confirm the rule that uses a mapped RE `STATUS` first and only falls back
   to `PARTICIPATION` when the status has no target. Should outcomes such as
   Event Enquiry, Event Rejection, Event Dropout, and Event Deferral map to
   status reasons? How should Event Waiting List be represented when Dynamics
   has no matching option?
4. Is one source participant row always one Dynamics Event Participant? How
   should repeated registrations, duplicate source rows, transfers, or
   multiple registrations for the same Contact and Event be handled?
5. Should participant records link only to Contacts, or may an Account be
   the customer? What is the approved rule when Contact and Account links
   both exist, multiple Contacts resolve, or GDPR/suppression data is missing?
6. What business values should populate `msnfp_identifier` and
   `msnfp_date`? Is the source `DATEADDED` appropriate only for
   `overriddencreatedon`, or should it also populate the participant date?
7. Should Appeal, Campaign, Package, fees, gifts, and other participant
   attributes be migrated in this object load, loaded separately, or omitted?
   Identify any parent-object dependencies and owner for each decision.
8. What should happen when the Event is missing or ambiguous in Dynamics DEV:
   hold the participant, create the Event first, or use another approved
   relationship rule?
9. After initial load, should changes in RE update Dynamics? How should
   deletions, late-arriving rows, and corrections to previously held rows be
   reconciled?
10. Who is the business approver for status/payload decisions, and what
    counts and sample checks are required for acceptance?

## DEV acceptance checklist

- Business answers are recorded and the relevant mappings are updated.
- Current source, lookup, privacy, status, target-duplicate, and XREF
  diagnostics have been rerun; every excluded row has a visible hold reason.
- Event and Contact lookup bindings are read back on the pilot record.
- A new full-load preview is reviewed before any batch is dispatched.
- DEV automations, credentials, batch limits, concurrency, and monitoring are
  confirmed by the operator.
- Each batch is reconciled across ADF activity results, Dynamics rows, XREF,
  and writeback audit before proceeding. No uncertain POST is blindly retried.
- Full-load counts, failures, holds, and business exceptions are signed off.
