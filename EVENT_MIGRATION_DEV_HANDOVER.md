# Event migration DEV handover

## Decisions

On 2026-11-23 the Event field rules were agreed for DEV, with acceptance
issues to be revisited:

- Locations containing `virtual` or `online` map to Virtual; other nonblank
  locations map to In-person / Hybrid. A blank location is not sent.
- Start and end dates are sent; start and end times are not sent.
- No owning team is explicitly supplied; Dynamics applies its own default.
- The RE Event reference is used for the Event code and unique ID.

The four RE Event categories are provisional. The source `CATEGORY` field was
associated with a deprecated Event field in the mapping workbook, not explicitly
with the new Event Category table. Event Types were provisionally assigned
Community; Charity exceptions and the Category mapping require acceptance review.

## Work completed, in order

1. Identified 26 distinct Event Type descriptions used by RE Events. Migrated
   `External Training` as a single DEV pilot and captured its Dynamics ID.
2. Created the four Event Categories manually in Dynamics DEV. All were returned
   as active:

   | RE category | Dynamics DEV ID |
   | --- | --- |
   | Other | `1e819518-70e7-f111-84e9-70a8a575b5fc` |
   | Sporting event | `43ed1d21-70e7-f111-84e9-70a8a575b5fc` |
   | Dinner | `44ed1d21-70e7-f111-84e9-70a8a575b5fc` |
   | Class | `34ea7f2c-70e7-f111-84e9-70a8a575b5fc` |

   The optional Event Source Category flag was not agreed; the Dynamics default
   was left unchanged.
3. Updated the Event view to match those names to the DEV IDs and build the
   Event Category lookup. The deployed DEV view reported matches for all 2,008
   Events.
4. Used the existing ADF dispatcher to send the remaining Event Types one at a
   time. The batch preview returned zero remaining, and Snowflake reported 26
   source types and 26 captured IDs. The last reported capture was
   `SPONSORED RUN`.
5. The Event view initially found zero Event Type IDs in the Dynamics extract.
   Updated the view to use captured DEV IDs when the extract has no matching
   name; conflicting extract and capture IDs are held. The deployed DEV view
   then reported 2,008 Events and 2,008 Event Type IDs.
6. All 2,008 Events were initially held by `EVENT_FIELD_RULES`. Following the
   DEV decision above, the Event view was updated and run in Snowflake DEV to
   bypass that one gate. The central gate and all other gates are unchanged.
   The resulting view reported 954 `CREATE` rows and 1,054 rows held for a
   missing Campaign.
7. Selected RE Event ID 14, reference `LM 2008 Organisations`, as a DEV pilot
   candidate. Its proposed start date is 1900-01-01 and requires acceptance
   review. Dynamics metadata confirmed the `msnfp_events` entity set and
   `msnfp_eventid` primary ID. A live Dynamics check found no exact Event code
   match before the pilot was sent.
8. Prepared a local single-Event request, Event identity table and capture
   procedure, and added a pilot route to the existing dispatcher. The planned
   DEV Event ID is `609825fb-8311-46a9-85c8-b372cbba3ae0`. Dynamics metadata
   confirmed that `msnfp_eventid` is valid for create. The user created the
   Snowflake dependencies and the request preview returned one row. The user
   validated and debug-ran the dispatcher. Dynamics returned the Event with
   its expected ID, reference and name; Snowflake identity capture returned
   the same ID. Dynamics also confirmed Event Type `Sponsored Run` and Event
   Category `Other`.
9. Prepared a DEV batch request preview and a sequential Event branch in the
   existing dispatcher. The user created the preview in Snowflake DEV and it
   returned 953 Events. The user validated and debug-ran the new ADF branch for
   one Event. Snowflake captured RE Event 100 as
   `85bf085e-3f26-55a8-b90a-38ae468b47fa`; the preview then returned 952.
   This second Event has not yet been independently read back from Dynamics.
10. The user confirmed Event automations are safe or disabled in DEV and
    ran a 10-Event batch. Snowflake subsequently reported 12 captured Events
    in total and 942 remaining in the batch preview.

## Code and deployment

- [Event view](INTEGRATION_DB/DYNAMICS/Views/VW_D365_MSNFP_EVENT.sql):
  provisional DEV Category IDs, Event Type captured-ID fallback and DEV-only
  field-rule gate override.
- [Event Type preview](INTEGRATION_DB/DYNAMICS/Views/VW_D365_MHA_EVENTTYPE.sql)
  and [batch request view](INTEGRATION_DB/DYNAMICS/Views/VW_D365_EVENTTYPE_BATCH_REQUESTS_DEV.sql).
- [Event Type identity table](MDM_DB/GOLD/Tables/EVENTTYPE_D365_IDENTITY_DEV.sql)
  and [capture procedure](MDM_DB/GOLD/Procedures/SP_CAPTURE_EVENTTYPE_D365_ID_DEV.sql).
- [Existing ADF dispatcher](ADF%20Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json):
  the Event Type batch route uses one request per run and captures the returned
  ID against the current source name. The user validated and debug-ran that
  route and the Event pilot and batch routes in DEV; publication status is
  unknown.
- Event pilot: [request view](INTEGRATION_DB/DYNAMICS/Views/VW_D365_EVENT_PILOT_REQUESTS_DEV.sql),
  [identity table](MDM_DB/GOLD/Tables/EVENT_D365_IDENTITY_DEV.sql), and
  [capture procedure](MDM_DB/GOLD/Procedures/SP_CAPTURE_EVENT_D365_ID_DEV.sql).
- [Event batch request preview](INTEGRATION_DB/DYNAMICS/Views/VW_D365_EVENT_BATCH_REQUESTS_DEV.sql):
  excludes captured pilot IDs, writeback state and duplicate source references.
  The new ADF branch is sequential and checks for an exact live Event code
  before each create. A zero `TestRowsPerCombo` defaults to one Event for this
  branch; a positive value sets the limit, capped at 2,000.

The current dispatcher is based on the Event Type pilot and does not include
the earlier Gift pilot route. Do not overwrite a newer ADF definition without
comparing it first.

## Proof of the Event pilot

The RE query below reads the RE source extract in Snowflake, not live RE.

```sql
SELECT ID, EVENTREF, NAME, TYPEDESCRIPTION, CATEGORY, STARTDATE
FROM RAW.RAISERS_EDGE.VW_ODS_T_EVENTS
WHERE ID = 14;
```

```sql
SELECT E.RE_EVENT_ID, E.RE_EVENT_REF, E.RE_EVENT_TYPE, E.RE_EVENT_CATEGORY,
       I.D365_GUID
FROM INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_EVENT AS E
JOIN MDM_DB.GOLD.EVENT_D365_IDENTITY_DEV AS I
    ON TO_VARCHAR(E.RE_EVENT_ID) = I.RE_EVENT_ID
WHERE E.RE_EVENT_ID = 14;
```

[Dynamics DEV Event 14](https://nasdatamig.crm11.dynamics.com/api/data/v9.2/msnfp_events(609825fb-8311-46a9-85c8-b372cbba3ae0)?$select=msnfp_eventid,mha_eventcode,msnfp_name&$expand=mha_EventTypeId($select=mha_eventtypeid,mha_name),mhnas_EventCategory($select=mhnas_eventcategoryid,mhnas_name))

These queries prove the example, not the contents of every captured Event.

## Outstanding

- Process the remaining 942 eligible Events in DEV; no further run has been
  reported since the 12 captured count. Reconcile results after processing.
- Resolve Campaign dependencies for the 1,054 held Events.
- Reconcile any uncertain POST in Dynamics before retrying.
- Do not overlap Event runs or other writers. The live preflight is an exact Event-code match,
  not a guarantee against all historical duplicates or concurrent writes.
  The sequential ForEach may continue other iterations after one fails; review
  activity-level results and reconcile any uncertain POST before another run.
- The Event view reads existing Events from the Dynamics extract and may still
  show the captured pilot as `CREATE` until that extract refreshes. The batch
  preview excludes captured IDs; making rows eligible does not send them.
- Review Event rules, Category mapping, Event Source Category flag and Community
  assignments during acceptance. Changes to Community/Charity decisions do not
  automatically update Event Types already created in Dynamics.
- Restore a reliable Dynamics-to-Snowflake extract. Captured IDs do not reflect
  later Dynamics changes or deletion.
- Before any deployment outside DEV, replace the hard-coded DEV Category IDs,
  remove the DEV gate override and review the Event Type identity fallback.

## Event Sub Category DEV pilot

See the [detailed DEV handover and business questions](EVENT_SUBCATEGORY_DEV_HANDOVER.txt).

The RE Event attribute `Event Type Subcategory` is a candidate source, not a
confirmed business mapping. In the source preview, Walk and Cycle had exact
active Dynamics matches; 11 other names had no exact match. Three Events
(1293, 1428 and 1433) had two distinct values. The user agreed to hold them
for subcategory mapping pending a business rule; this hold is not yet
implemented and does not hold or change existing Events.

The user agreed a one-record Marathon pilot, provisionally linked to the DEV
Sporting event Category. Marathon occurs in RE; the Category choice needs
business review. Existing Walk, Cycle, Run and Trek/Hike belong to the
different Dynamics Category Sponsored Activity. No Event Category or Event
is updated by this pilot, and no wider subcategory load is implemented.

- [Pilot request view](INTEGRATION_DB/DYNAMICS/Views/VW_D365_EVENTSUBCATEGORY_PILOT_REQUESTS_DEV.sql)
  creates one request only when Marathon is in the source and no matching
  writeback state or pilot XREF exists.
- [Pilot capture procedure](MDM_DB/GOLD/Procedures/SP_CAPTURE_EVENTSUBCATEGORY_PILOT_DEV.sql)
  records the planned ID in XREF and rejects a different returned ID or
  conflicting XREF.
- The existing dispatcher includes the `D365_EVENTSUBCATEGORY_PILOT` route.
  The user validated and debug-ran it in DEV; publication status is unknown.
- Dynamics readback confirmed Marathon is active, with ID
  `3cb39ca4-d310-4aa5-9c44-dca36bf9f161` and Category Sporting event
  (`43ed1d21-70e7-f111-84e9-70a8a575b5fc`). Snowflake XREF returned the
  same ID for `EVENTSUBCATEGORY:5bb346961a5b7973e114b3a5189f179d`.

Before any pilot run, check live Dynamics for Marathon and the planned ID,
validate the dispatcher, and run only one writer. The preview does not check
the live Dynamics name or prevent concurrent creates with different IDs. If
the POST or capture is uncertain, reconcile in Dynamics before any retry.
After a successful run, verify the live name, Category and XREF; an empty
request preview alone is not proof of a successful create. The pilot stores
its identity in XREF, which does not reflect later Dynamics changes/deletions.

## Event Participant DEV pilot

See the [Event Participant DEV handover](EVENT_PARTICIPANT_DEV_HANDOVER.md)
for the one-row pilot evidence, full-load prerequisites, and business questions.
