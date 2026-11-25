# Membership Category DEV pilot handover

Status: 24 November 2026  
Environment: Dynamics DEV only

## Summary

One Raiser’s Edge Membership Category was migrated end to end as a DEV pilot:
**Individual Life**, RE category code `2113`.

The pilot created the Dynamics record with its name only. The Snowflake
Dynamics ID was captured in XREF and the live Dynamics record was read back.
This proves one pilot, not a full Membership Category load and not a
Membership record migration.

Membership Category (`msnfp_membershipcategory`) is a separate Dynamics
object from Membership Sub Category (`mhnas_membershipsubcategory`).

## Pilot result

| Layer | Evidence |
|---|---|
| RE source extract in Snowflake | Category `2113`, `Individual Life`; 669 membership records. The record-level `AMOUNT` varies and was not used as a category price. |
| Snowflake request preview | Exactly one POST to the DEV `msnfp_membershipcategories` endpoint. Payload contains only `msnfp_name = Individual Life`. |
| ADF DEV | `PL_D365_DispatchRequests` validated and debug-ran successfully with the pilot parameters below. |
| XREF | `MEMBERSHIPCATEGORY:2113` maps to Dynamics ID `ee5c5851-4fe8-f111-84e9-70a8a575b39d`. |
| Dynamics DEV readback | Confirmed name `Individual Life`, matching ID, and null amount and duration fields. |

### RE source evidence

This query reads the Raiser’s Edge extract in Snowflake; it does not query the
live Raiser’s Edge application.

```sql
SELECT
    MEMBERSHIPCATEGORYCODE,
    TRIM(MEMBERSHIPCATEGORYDESCRIPTION) AS CATEGORY_NAME,
    COUNT(DISTINCT ID) AS RE_MEMBERSHIPS,
    COUNT(DISTINCT AMOUNT) AS DISTINCT_MEMBERSHIP_AMOUNTS,
    MIN(AMOUNT) AS MIN_MEMBERSHIP_AMOUNT,
    MAX(AMOUNT) AS MAX_MEMBERSHIP_AMOUNT
FROM RAW.RAISERS_EDGE.VW_ODS_T_MEMBERSHIP
WHERE MEMBERSHIPCATEGORYCODE = 2113
  AND UPPER(TRIM(MEMBERSHIPCATEGORYDESCRIPTION)) = 'INDIVIDUAL LIFE'
GROUP BY MEMBERSHIPCATEGORYCODE, TRIM(MEMBERSHIPCATEGORYDESCRIPTION);
```

The source analysis found 26 distinct membership `AMOUNT` values for Individual
Life, ranging from 0 to 1,000. These are amounts on Membership records, not an
approved value for either Membership Category amount field.

### Snowflake XREF evidence

```sql
SELECT GOLDEN_RECORD_ID, SOURCE_SYSTEM, SOURCE_RECORD_ID
FROM MDM_DB.GOLD.XREF
WHERE SOURCE_SYSTEM = 'DYNAMICS'
  AND GOLDEN_RECORD_ID = 'MEMBERSHIPCATEGORY:2113';
```

Verified result:

```text
MEMBERSHIPCATEGORY:2113 | DYNAMICS | ee5c5851-4fe8-f111-84e9-70a8a575b39d
```

### Dynamics DEV readback

```text
GET https://nasdatamig.crm11.dynamics.com/api/data/v9.2/msnfp_membershipcategories(ee5c5851-4fe8-f111-84e9-70a8a575b39d)?$select=msnfp_membershipcategoryid,msnfp_name,msnfp_amount,msnfp_amount_membership,msnfp_membershipduration
```

The response confirmed:

- `msnfp_name`: `Individual Life`
- `msnfp_membershipcategoryid`: `ee5c5851-4fe8-f111-84e9-70a8a575b39d`
- `msnfp_amount`, `msnfp_amount_membership`, `msnfp_membershipduration`: `null`

## Code and ADF changes

- Added the fixed pilot request view:
  [VW_D365_MEMBERSHIPCATEGORY_PILOT_REQUESTS_DEV.sql](INTEGRATION_DB/DYNAMICS/VW_D365_MEMBERSHIPCATEGORY_PILOT_REQUESTS_DEV.sql).
  It emits a request only when RE category code `2113` still has the expected
  description. The body contains only `msnfp_name`. It also checks for existing
  writeback state and the expected Dynamics XREF key.
- Modified the existing dispatcher:
  [PL_D365_DISPATCHREQUESTS.json](<ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>).
  It routes `D365_MEMBERSHIPCATEGORY_PILOT` to the new view and selects
  `msnfp_membershipcategoryid` from the POST response so XREF capture can use
  the returned GUID.
- The user ran the view in Snowflake DEV, validated the updated child pipeline
  in ADF DEV, and debug-ran the pilot successfully.
- These are pilot-specific changes. The view is fixed to one category; it is
  not a batch loader.

ADF debug parameters used:

```text
PipelineId       = D365_MEMBERSHIPCATEGORY_PILOT
SourceInstance   = SNOWFLAKE_DEV
EntityId         = MEMBERSHIPCATEGORY
TestRowsPerCombo = 1
```

## Current category comparison

The Snowflake comparison found 26 distinct RE Membership Categories: 11 matched
Dynamics category names in the extract and 15 had no exact match at that time.
Individual Life was one of those 15 and has now been created in DEV. The 14
remaining unmatched names all begin with `z`:

- `zAnnual Individual`
- `zAnnual Couple`
- `zNAS Free Membership`
- `zAnnual Unwaged`
- `zRE 7 Conversion`
- `zAnnual Corporate`
- `zJoint Life`
- `zAnnual Individual Overseas`
- `zAnnual Couple Overseas`
- `zAnnual Corp Overseas`
- `zAnnual Unwaged Couple`
- `zNAS Free Membership2`
- `zNAS Invoiced Membership`
- `zConference`

The earlier name comparison used the Snowflake Dynamics extract. Refresh and
reconcile that extract before treating its matches or missing values as the
current live Dynamics position.

## Business decisions required before a full load

1. For each of the 14 remaining `z` categories, should it be kept under its
   current name, renamed, mapped to another category, or excluded?
2. Are the 11 categories that matched by name in the Dynamics extract valid
   equivalents to the corresponding RE categories, and should they be reused?
3. What do Dynamics **Display Amount** (`msnfp_amount`) and **Amount
   (Membership)** (`msnfp_amount_membership`) represent for a category? What
   are the correct category-level source values? The RE membership `AMOUNT`
   varies within categories and must not be assumed to be the category price.
4. How should each RE category map to Dynamics **Duration**
   (`msnfp_membershipduration`)? The workbook notes that conversion is needed;
   no direct source mapping has been agreed.
5. The workbook marks the two amount fields and Duration as required for
   migration, while Dynamics metadata showed them as optional. Can these fields
   be left blank, or must values be supplied before loading?
6. Should newly created categories be active? How should obsolete or
   discontinued categories be represented?

Other workbook fields without a confirmed source mapping include Tax Amount,
Good Will Date, Renewal Date and Type. Confirm whether any of these need values
for the migration or can remain blank.

## Remaining work

1. Obtain the business decisions above; do not extend the fixed pilot view to
   load the remaining categories as-is.
2. Refresh the Dynamics category extract and reconcile all 26 RE category
   names against live DEV records, including duplicate and inactive matches.
3. Build a generalized request preview and load path for only the approved
   categories, with deterministic source keys, duplicate guards and XREF
   capture.
4. Validate the preview and holds before any wider writeback. Reconcile any
   uncertain POST before retrying.
5. Refresh the Dynamics extract after approved writes and verify that the
   Membership mapping resolves the new category IDs.
6. Only then consider the separate full Membership migration, which has its
   own outstanding mapping and dispatch-safety decisions.

Do not rerun the Individual Life pilot as a way to load other categories.
