# MDM Task Processing Walkthrough

## What starts the run

The PROD task definition schedules `MDM_DB.STAGING.TK_STANDARDISE_RECORDS` daily at 06:00 UTC. That task calls `MDM_DB.STAGING.SP_STANDARDISE_RECORDS()`. The next two tasks are dependency-triggered:

```text
TK_STANDARDISE_RECORDS
  -> SP_STANDARDISE_RECORDS
       -> SP_ETL_RAISERS_EDGE
       -> SP_ETL_HUBSPOT
       -> SP_ETL_DYNAMICS is disabled/commented out
  -> TK_BUILD_MATCH_GROUPS
       -> SP_BUILD_MATCH_GROUPS
            -> SP_BUILD_MATCH_COMPONENTS
  -> TK_GENERATE_GOLDEN_RECORDS
       -> SP_GENERATE_GOLDEN_RECORDS
```

The TEST task files show the same task order with the TEST warehouse. DEV, TEST, and PROD files establish the configured SQL chain; task history is separate evidence that the chain has executed.

## Step 1: Standardise source records

`SP_STANDARDISE_RECORDS()` calls the source ETL procedures sequentially:

1. `SP_ETL_RAISERS_EDGE()`
2. `SP_ETL_HUBSPOT()`

It returns a summary string containing each procedure's return text. The Dynamics call is present only as a commented-out line and the result is set to a "skipped (disabled...)" message. Therefore, a successful run of this wrapper does **not** mean Dynamics ingestion ran.

Both active source procedures use `MDM_DB.STAGING.STANDARDISED_RECORDS` as the common record store. They build source-prefixed IDs, map source fields into a shared person/organisation structure, and use source hashes and `MERGE` logic to insert new records or update changed records.

### Raisers Edge procedure

`SP_ETL_RAISERS_EDGE()` reads the Raisers Edge ODS views in `RAW.RAISERS_EDGE` and:

- Creates `RE-<constituent id>` standardised IDs; maps individuals and organisations and core identity/contact/address fields.
- Selects eligible email/phone/address data and normalises values such as names, email addresses, and addresses.
- Marks existing Raisers Edge records inactive when the source record is no longer present as a non-deceased constituent.
- Builds arrays of all emails, phones, and addresses, retaining source IDs and attributes such as type, primary/active flags, and address metadata.
- Enriches standardised records with the four-year rule, constituent attributes, constituent-type flags, and solicit codes; performs identity-field backfill and name/address normalisation.
- Returns row counts for merge, soft-delete, arrays, four-year-rule, attribute/code/solicit, backfill, and normalisation work.

### HubSpot procedure

`SP_ETL_HUBSPOT()` processes contacts and companies separately:

- Creates `HS-<object id>` contact IDs and `HSC-<object id>` company IDs; maps available identity, contact, address, legacy, and constituent-flag fields.
- Excludes deleted records and contacts explicitly marked `Add to RE = No`.
- Uses the source hash to update changed rows, marks no-longer-eligible existing records inactive, and builds arrays of available emails, phones, and addresses.
- Backfills fields added to the standardised model and normalises names and addresses.
- Returns separate row-count summaries for contacts and companies, plus normalisation.

The procedure code also defines `SP_ETL_DYNAMICS()`, but the wrapper does not call it in the exported TEST/PROD code.

## Step 2: Generate match candidates and groups

`TK_BUILD_MATCH_GROUPS` runs after the standardisation task and calls `MDM_DB.MDM.SP_BUILD_MATCH_GROUPS()`.

The procedure clears and rebuilds the match-candidate, component, match-group, and match-group-member tables. It considers active standardised records and excludes certain placeholder/test surnames. It creates candidate pairs using signals including:

- Exact email and exact mobile/landline phone.
- Exact name plus postcode, or fuzzy first/last name and address at a shared postcode.
- Exact HubSpot-to-Raisers Edge constituent ID links for individuals and organisations.
- Exact/normalised organisation name, with or without postcode.
- Exact email plus first and last name.

Frequency caps are used for some shared identifiers/names to avoid overly common values creating large false-match sets.

The procedure seeds match components from eligible candidate edges and calls `SP_BUILD_MATCH_COMPONENTS()`. That helper iteratively propagates the lowest label across connected records until no labels change or 20 iterations are reached. Bare exact-email and exact-landline edges do not join components; fuzzy name/address edges below 90 are also excluded from component linking.

It then writes match groups and their members. Group status is based on average candidate score: 95 or higher is `Auto-Approved`; 85 or higher is `Pending Review`; lower scores are `Low Confidence`, except groups containing specified identity-grade links are kept at least `Pending Review`. The procedure returns counts for candidates, components, groups, and members.

## Step 3: Generate golden records and cross-references

`TK_GENERATE_GOLDEN_RECORDS` runs after match-group building and calls `MDM_DB.GOLD.SP_GENERATE_GOLDEN_RECORDS()`.

The procedure:

1. Fuses active records in `Auto-Approved`, `Approved`, or `Pending Review` groups. Records outside those groups—including low-confidence matches—are treated as individual/singleton golden records.
2. Chooses a representative record by latest `LAST_UPDATED` (with a deterministic ID tie-break), and also ranks by completeness so missing values in the representative can be filled from the most complete member.
3. Carries forward an existing golden ID where possible; otherwise creates an ID from the golden-record sequence.
4. Merges the resulting fields into `MDM_DB.GOLD.GOLDEN_RECORDS`, including combined source-system, email, phone, and address information.
5. Deactivates obsolete golden records and superseded IDs after cluster changes.
6. Inserts/updates `MDM_DB.GOLD.XREF` links from golden records to active source records, prunes stale links, and backfills golden IDs onto `STANDARDISED_RECORDS`.
7. Returns counts for golden records, deactivations, merge losers, XREF changes/pruning, and backfill.

## What this chain does not show

- `SP_ETL_DYNAMICS()` is not called by `SP_STANDARDISE_RECORDS()` in the supplied TEST/PROD definitions.
- `SP_VALIDATE_MDM()` is not part of this task chain; it must be run separately if a validation report is required.
- The task definitions and successful task history show scheduling/execution, not record-level correctness. Review procedure return summaries, table counts, data-quality checks, and source-to-target reconciliation.
- This is the Snowflake MDM chain. It does not document the ADF pipeline or prove that ADF/API processing ran.
- The exported `SP_XREF_CAPTURE*` procedures are separate from this chain; `SP_GENERATE_GOLDEN_RECORDS()` itself performs the XREF merge and cleanup described above.

## Relevant exported definitions

- Tasks: `MDM_DB\Staging\Tasks\`
- Standardisation wrapper and source ETL: `MDM_DB\Staging\Procedures\SP_STANDARDISE_RECORDS().sql`, `SP_ETL_RAISERS_EDGE().sql`, `SP_ETL_HUBSPOT().sql`, and `SP_ETL_DYNAMICS().sql`
- Match grouping: `MDM_DB\MDM\Procedures\SP_BUILD_MATCH_GROUPS().sql` and `MDM_DB\Staging\Procedures\SP_BUILD_MATCH_COMPONENTS().sql`
- Golden records: `MDM_DB\GOLD\Procedures\SP_GENERATE_GOLDEN_RECORDS().sql`
- Separate validation procedure: `MDM_DB\MDM\Procedures\SP_VALIDATE_MDM().sql`
