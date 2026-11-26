# Package DEV pilot handover

## Status and scope

One Raiser’s Edge (RE) Package was created and verified in Dynamics DEV,
together with its parent Appeal and Campaign. The three IDs were captured
in Snowflake XREF, and Dynamics readback confirmed the Package's Appeal and
Campaign links.

This is a **one-record pilot**, not a full load or an ongoing update process.
Some workbook fields were omitted and business decisions remain open. All
further work and testing remain DEV-only.

| Item | Value |
|---|---|
| Workbook | [Source-to-target workbook](<./NAS DM Source to Target Mappings Current WIP 1.xlsx>), Mapping V6, rows 705-736 |
| Dynamics object | Package, logical name `msnfp_package`, entity set `msnfp_packages` |
| RE Package extract | `RAW.RAISERS_EDGE.VW_ODS_T_PACKAGES` |
| RE parent extracts | `RAW.RAISERS_EDGE.VW_ODS_T_APPEALS` and `RAW.RAISERS_EDGE.VW_ODS_T_CAMPAIGNS` |
| Pilot pipeline ID | `D365_PACKAGE_CHAIN_PILOT` |

The Snowflake views above are extracts of RE data, not the live RE
application. The workbook's populated Package source entries are in its
**FS source columns**, while the RE source columns are blank. The RE
Package mapping used here is a candidate that needs business confirmation.

## What we did and why

1. Reviewed the Package workbook mapping and the existing candidate view.
   At that point all **3,507** rows returned by the view were held with
   `PARENT_MISSING:msnfp_appeal`. This was a point-in-time DEV result; it
   did not prove every parent Appeal was absent from live Dynamics.
2. Searched for available parent Appeals and Campaigns. No appropriate
   existing parent was found in the candidate checks. A proposed earlier
   Package had no RE Campaign, while Dynamics metadata reported the
   Appeal's Campaign lookup as `ApplicationRequired`.
3. The user chose to create the actual RE Campaign, Appeal and Package
   chain for the DEV pilot instead of testing an Appeal without a Campaign.
   The user confirmed that creating the three object types in DEV was safe.
4. Selected RE Campaign **6**, Appeal **1359** and Package **71**. The
   source relates the Appeal to the Campaign and the Package to the Appeal.
5. Prepared a fixed, read-only preview and a separate one-chain request
   view. The disabled Campaign metadata row was used only as a DEV
   connection template, with the user's approval; the general Campaign
   metadata row was **not enabled**.
6. With the user's permission, updated the local dispatcher to select the
   pilot request view and capture the correct returned ID for each of the
   three entities. The user compiled the Snowflake views and operated ADF
   DEV; publication status is not confirmed.
7. Performed the creates sequentially: Campaign, then Appeal, then Package.
   Before each child, the parent XREF and live Dynamics record were
   verified. The user reported successful ADF runs and supplied XREF and
   Dynamics readback for all three records.

Live duplicate searches found no match at the time using the selected source
IDs, names and/or codes. They were point-in-time checks, not proof that no
duplicate could exist under another identifier.

## Verified pilot chain

| Object | RE ID | Name / code | XREF key | Dynamics DEV ID |
|---|---:|---|---|---|
| Campaign | 6 | Events Fundraising / `EVENTS` | `CAMPAIGN:6` | `5c2f0f59-e3e9-f111-84e9-70a8a575b39d` |
| Appeal | 1359 | Stars Shine for Autism 09 | `APPEAL:1359` | `1c6e4185-e8e9-f111-84e9-70a8a575b39d` |
| Package | 71 | Stars Shine 2009 Donations / `Stars Shine Donation` | `PACKAGE:71` | `c22c0f0d-efe9-f111-84e9-70a8a575b39d` |

Dynamics readback showed:

- The Campaign had source ID `6`, code `EVENTS`, active state `0`,
  status reason `3`, and the approved DEV `TEST ONLY` operating entity.
- The Appeal had source ID `1359` and linked to the Campaign ID above.
- The Package had source ID `71`, the name and code above, and linked to
  both the Appeal and Campaign IDs above.
- All three had `mha_eligibleforgiftaid = true` on readback. This was a
  Dynamics default, **not an approved business rule**.

The XREF and live readbacks verify the three creates and the returned IDs.
Separate HTTP-status or writeback-audit results were not supplied.

## Pilot payload and limitations

- **Campaign:** sent source ID, source, code, name, description,
  state/status and the DEV `TEST ONLY` operating entity. The source preview
  included expected revenue of `895000`, but this was **not sent** because
  its currency was not confirmed. The `TEST ONLY` binding was approved for
  this pilot, not as the full-load operating-entity rule.
- **Appeal:** sent source ID, source, name and Campaign binding.
- **Package:** sent source ID, source, code, name, Appeal binding and
  Campaign binding. Expected Revenue and Number Solicited were not sent.

Successful API creation does not approve the omitted fields, defaults or
business mappings. The workbook migration/sync flag is not the same as
Dataverse create-required metadata.

## Code and configuration

| File | Change or role |
|---|---|
| [Pilot preview](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_PACKAGE_PILOT_PREVIEW_DEV.sql) | New read-only, fixed-chain preview. Its `PREVIEW_DISPATCH_ALLOWED = FALSE` is informational; the separate request view applies its own guards. |
| [Pilot requests](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_PACKAGE_CHAIN_PILOT_REQUESTS_DEV.sql) | New fixed-chain DEV POST requests. Child requests require exactly one syntactically valid parent XREF; state, XREF and extract guards restrict creation. |
| [Dispatcher JSON](<./ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>) | Added the pilot request-view route and entity-specific response-ID and XREF capture handling. |
| [Existing Package view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_MSNFP_PACKAGE.sql) | Existing candidate source and mapping; not changed for this pilot. |
| [Existing Appeal view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_MSNFP_APPEAL.sql) and [Campaign view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_CAMPAIGN.sql) | Existing parent mappings and source previews; not changed for this pilot. |

The dispatcher JSON parsed and its three modified expressions passed
static delimiter checks. Removing the pilot wrappers restored the previous
expressions exactly; this is **not** a live regression test of every
previous object. The three pilot runs were reported successful and their
records were read back, but the live ADF version and publication status
have not been independently established.

The pilot views contain fixed DEV IDs, names and endpoint restrictions.
The request view uses XREF to resolve parent IDs but does not check the
live parent at dispatch time. Its state/XREF/extract guards are not an
atomic concurrency control, and Snowflake's Dynamics extracts can lag.
Do not run overlapping creates, blindly retry an uncertain POST, or remove
the fixed filters to make a full loader. Reconcile live Dynamics, XREF and
writeback state first.

## Workbook fields marked Y

| Row | Dynamics field | Pilot / outstanding work |
|---:|---|---|
| 711 | Source `mha_source` | Sent `Raisers Edge` for the Package. |
| 712 | Source ID `mha_sourceid` | Sent RE Package ID `71`; confirm the identity rule for all records. |
| 717 | Appeal `msnfp_appealid` | Linked to the verified Appeal. Parent coverage and missing-parent rules remain open. |
| 718 | Campaign `msnfp_campaignid` | Linked to the verified Campaign associated with the Appeal; confirm the derivation rule for all records. |
| 720 | Estimated Revenue `msnfp_expectedrevenue` | Not sent; source, currency and handling of blanks need agreement. |
| 721 | Number Solicited `mhnas_numbersolicited` | Not sent. The existing view uses a null placeholder; verify the target field and the RE source before mapping. |
| 722 | Package Code `mhnas_packagecode` | Sent RE `PACKAGEREF`; the live record returned the expected value. |
| 723 | Name `msnfp_identifier` | Sent RE `DESCRIPTION`; the live record returned the expected value. Workbook states a 150-character limit; verify current metadata and overflow handling. |
| 724 | Package ID `msnfp_packageid` | Dynamics generated the pilot ID and XREF captured it. |

Review the authoritative workbook and all other fields and defaults as
well. A field marked N may still have business, automation or target
implications.

## Business questions for a full load

1. **Scope and source:** Are RE Packages in scope despite the workbook
   listing FS rather than RE source fields? Which historical, active and
   ended Packages should be included?
2. **Parent relationships:** Must every Package have an Appeal and every
   Appeal a Campaign? How should missing, ambiguous or unavailable parents
   be handled, and should parents be migrated first?
3. **Campaign derivation:** Should the Package Campaign always come from
   its Appeal? What should happen where the relationships disagree or the
   Campaign is missing?
4. **Identification and duplicates:** Is RE Package ID the agreed stable
   identity? How should existing Dynamics records, duplicate source IDs,
   repeated Package codes and possible duplicate names be matched and
   reconciled?
5. **Fields and defaults:** Confirm the source and treatment of every
   migration/sync field, especially Expected Revenue, its currency, Number
   Solicited, Package Code and Name. What should happen to missing or
   over-length values, and are any exceptions approved?
6. **Gift Aid:** What should Gift Aid eligibility be for Campaigns, Appeals
   and Packages? Is the default Yes appropriate, and should the three DEV
   pilot records be corrected?
7. **Operating entity and automation:** What operating entity and owner
   should migrated records use? Which Dynamics automations, notifications,
   financial effects and defaults are permitted during migration?
8. **Dates and status:** Should source dates, active/inactive status or
   other historical Package fields be migrated? How should blanks,
   conflicting dates and ended Packages be represented?
9. **Transition changes:** After the initial load, which RE changes should
   create or update Dynamics records, how should deletions and conflicts be
   handled, and which system owns each field? When should the RE flow stop?
10. **Acceptance:** Who approves the mapping, exceptions and reconciliation,
    and what source, target and sample checks are needed before a full load
    is accepted?

## Work before a full load

1. Resolve the questions above and confirm the authoritative workbook and
   target metadata. Re-profile the current source, parent coverage,
   duplicates, field values and target records; the 3,507-row result is
   historical.
2. Reconcile or complete the pilot records according to the agreed rules,
   including Gift Aid and omitted fields. Do not create duplicates.
3. Build a separate generalised, held-first DEV preview and request path
   with explicit exception reasons, parent and XREF uniqueness checks,
   target duplicate checks and full approved mappings. The existing
   Package view currently chooses the oldest Dynamics row when source IDs
   duplicate; decide and implement safe duplicate handling before scaling.
4. Design bounded non-overlapping batches, dependency ordering, monitoring,
   uncertain-POST recovery and reruns. Reconcile each approved batch across
   RE extracts, Dynamics, XREF and writeback audit.
5. Separately design and test the agreed RE-to-Dynamics change/update path
   for the transition, then plan its safe retirement when RE closes.

## Read-only proof

```sql
SELECT
    C.ID AS RE_CAMPAIGN_ID,
    C.CAMPAIGNCODE,
    C.CAMPAIGNDESCRIPTION AS CAMPAIGN_NAME,
    A.ID AS RE_APPEAL_ID,
    A.CAMPAIGNDESCRIPTION AS APPEAL_NAME,
    P.ID AS RE_PACKAGE_ID,
    P.PACKAGEREF AS PACKAGE_CODE,
    P.DESCRIPTION AS PACKAGE_NAME
FROM RAW.RAISERS_EDGE.VW_ODS_T_PACKAGES P
JOIN RAW.RAISERS_EDGE.VW_ODS_T_APPEALS A ON P.APPEALID = A.ID
JOIN RAW.RAISERS_EDGE.VW_ODS_T_CAMPAIGNS C ON A.CAMPAIGNCODE = C.ID
WHERE P.ID = 71;
```

```sql
SELECT GOLDEN_RECORD_ID, SOURCE_SYSTEM, SOURCE_RECORD_ID AS DYNAMICS_ID
FROM MDM_DB.GOLD.XREF
WHERE SOURCE_SYSTEM = 'DYNAMICS'
  AND GOLDEN_RECORD_ID IN ('CAMPAIGN:6', 'APPEAL:1359', 'PACKAGE:71')
ORDER BY GOLDEN_RECORD_ID;
```

```text
GET https://nasdatamig.crm11.dynamics.com/api/data/v9.2/campaigns(5c2f0f59-e3e9-f111-84e9-70a8a575b39d)?$select=campaignid,mha_sourceid,codename,name,statecode,statuscode,mha_eligibleforgiftaid,_mha_operatingentityid_value
GET https://nasdatamig.crm11.dynamics.com/api/data/v9.2/msnfp_appeals(1c6e4185-e8e9-f111-84e9-70a8a575b39d)?$select=msnfp_appealid,mha_sourceid,msnfp_identifier,_msnfp_campaignid_value,mha_eligibleforgiftaid
GET https://nasdatamig.crm11.dynamics.com/api/data/v9.2/msnfp_packages(c22c0f0d-efe9-f111-84e9-70a8a575b39d)?$select=msnfp_packageid,mha_sourceid,msnfp_identifier,mhnas_packagecode,_msnfp_appealid_value,_msnfp_campaignid_value,mha_eligibleforgiftaid
```
