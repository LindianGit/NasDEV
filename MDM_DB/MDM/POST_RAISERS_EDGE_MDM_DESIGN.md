# MDM Processing Without Raisers Edge

## Purpose

This note outlines the work to assess and design if Raisers Edge is retired as an ongoing MDM source. The objective is to preserve the required identity resolution, golden-record, cross-reference, and data-quality outcomes using the post-Raisers Edge source systems.

This is a design/work assessment, not an implementation specification or approval to change production. Confirm all assumptions with NAS, the Dynamics partner, the agreed field mapping, and live environment evidence.

## Current-state evidence from the supplied exports

- The exported `SP_STANDARDISE_RECORDS()` procedure calls `SP_ETL_RAISERS_EDGE()` and `SP_ETL_HUBSPOT()`. Its `SP_ETL_DYNAMICS()` call is commented out and described as disabled pending resolution of a known issue.
- `SP_ETL_DYNAMICS()` exists in the exported code and maps Dynamics contacts and accounts into `MDM_DB.STAGING.STANDARDISED_RECORDS`, but its presence does not prove that the procedure is enabled, tested, or deployed.
- `SP_BUILD_MATCH_GROUPS()` contains HubSpot-to-Raisers Edge links using `PROPERTY_CONSTITUENT_ID` to resolve `RE-` standardised IDs. These identity links depend on Raisers Edge records being available in the standardised-record set.
- `SP_GENERATE_GOLDEN_RECORDS()` builds golden records from active standardised records, carries forward IDs where possible, and maintains XREF links. Changes to source IDs or matching can therefore affect existing golden IDs and cross-references.
- `SP_VALIDATE_MDM()` contains Raisers Edge-specific counts and matching measures which may need to change when Raisers Edge is no longer an active source.

These are observations about exported SQL, not confirmation of current deployed behavior.

## Work required

### 1. Agree post-Raisers Edge source and field ownership

Decide which systems will supply MDM after Raisers Edge retirement. Confirm whether HubSpot and Dynamics will both be MDM sources, which system is authoritative for each field, and where Raisers Edge-only attributes will be retained or migrated.

Produce a field-level source-of-truth and survivorship matrix covering at least:

- Identity and organisation fields.
- Contact details and addresses.
- Consent and communication preferences.
- Fundraising and legacy attributes.
- Source identifiers, Dynamics identifiers, and golden-record identifiers.
- Effective dates, deletion/inactivation semantics, and conflict handling.

Do not assume that equivalent fields in HubSpot and Dynamics have identical meaning, quality, or update behavior.

### 2. Replace or retire source ingestion safely

If Dynamics is to become an MDM source, enable and validate the existing Dynamics ETL path only after resolving its known issue and confirming mappings. If another source or feed is intended, design and implement that feed instead.

For each retained source, verify:

- Stable source-record keys and standardised-ID format.
- Inserts, changed-record updates, unchanged-record handling, and reactivation.
- Deletions, soft deletes, and records missing from a source snapshot.
- Incremental-load watermarking, late-arriving changes, and replay/idempotency.
- Contact and organisation handling, including related email, phone, and address arrays.
- Source-specific fields, code translations, and null/blank semantics.
- Run counts, rejected records, and restart/recovery behavior.

Do not simply remove the Raisers Edge call while leaving source-specific retirement logic unreviewed. In particular, verify that an empty or retired source cannot cause valid standardised records to be marked inactive.

### 3. Replace Raisers Edge-dependent identity links

The current matching procedure uses HubSpot's `PROPERTY_CONSTITUENT_ID` to link HubSpot records to `RE-` records. When those records are no longer loaded, that match method will no longer provide a usable link.

Agree and implement a durable replacement, for example:

- A common, governed person/organisation identifier shared between retained platforms.
- A controlled crosswalk from legacy IDs to HubSpot and Dynamics IDs, retained after source retirement.
- A verified HubSpot-to-Dynamics identifier link, if the integration contract supports it.

Define ownership, uniqueness, lifecycle, merge/split handling, and recovery for the identifier or crosswalk. Test the replacement links alongside the existing email, phone, name/postcode, and organisation matching rules. Reassess false-positive and false-negative rates without the Raisers Edge anchor.

### 4. Preserve golden-record and XREF continuity

Before cutover, establish how current `GOLDEN_RECORD_ID` values and XREF links will be retained when Raisers Edge identifiers disappear from active staging.

Specify and test:

- Whether existing golden IDs remain stable for the same real-world people and organisations.
- How existing Raisers Edge XREF rows are retained as historical cross-references rather than treated as active source records.
- How merges, splits, duplicate resolution, source re-keying, and deleted/inactive records are handled.
- How Dynamics IDs returned by the partner/API are linked to the correct golden record.
- Whether downstream consumers can continue to resolve old Raisers Edge IDs during and after transition.
- How manual stewardship decisions and manually edited golden records are preserved.

Use representative non-production data to prove continuity before any production cutover.

### 5. Update survivorship and MDM validation

Review the survivorship implementation and the `SURVIVORSHIP_RULES` configuration against the agreed post-Raisers Edge field-ownership matrix. Make sure fields that currently depend on Raisers Edge are intentionally migrated, retained, or allowed to become unavailable; do not silently lose values during the transition.

Update validation measures to reflect the retained sources. This includes source totals and matched totals, match-method counts that refer to Raisers Edge identifiers, cross-source match rates, orphan checks, duplicate XREF checks, and golden-record completeness. Keep historical Raisers Edge data identifiable for reporting even if it is no longer an active feed.

`SP_VALIDATE_MDM()` is a separate procedure in the supplied code and is not part of the three-task chain. Define when and how its report will be run and reviewed.

### 6. Rehearse, compare, and cut over

Run the proposed source combination in DEV and TEST/UAT before production. Compare against an agreed pre-retirement baseline, including:

- Active standardised-record counts by source and person/organisation domain.
- Golden-record counts and stable-ID retention.
- Match candidates, match groups, confidence/status distribution, and steward review volumes.
- Field completeness, especially fields historically supplied only by Raisers Edge.
- XREF coverage, unresolved identifiers, duplicate links, and orphan records.
- Adds, updates, inactivations, rejected records, and reconciliation totals.
- Downstream payload/API outcomes and Dynamics identifier capture.

Agree measurable acceptance thresholds, owners, rollback conditions, and a parallel-run period. Retire the Raisers Edge feed only after the new source path and historical-ID strategy have passed those checks.

## Task chain impact

The three-task orchestration can likely remain:

1. `TK_STANDARDISE_RECORDS` calls `SP_STANDARDISE_RECORDS()`.
2. `TK_BUILD_MATCH_GROUPS` calls `SP_BUILD_MATCH_GROUPS()`.
3. `TK_GENERATE_GOLDEN_RECORDS` calls `SP_GENERATE_GOLDEN_RECORDS()`.

The task chain itself does not make the MDM independent of Raisers Edge. Its source procedures, identity links, survivorship, XREF continuity, and validation rules must all be updated and tested. A successful task run alone does not demonstrate equivalent MDM results.

## Decisions and dependencies

Resolve these before estimating or implementing the transition:

1. Which platforms remain active MDM sources after Raisers Edge retirement?
2. What is the authoritative source for each field and identifier?
3. Will Dynamics data be loaded into MDM, and when will the currently disabled Dynamics ETL be safe to enable?
4. What is the durable post-Raisers Edge identity/crosswalk strategy?
5. How long must legacy Raisers Edge IDs remain resolvable?
6. Which Raisers Edge-only data must be migrated or retained, and who owns it?
7. What are the reconciliation thresholds, parallel-run duration, acceptance authority, and rollback criteria?
8. Which activities belong to NAS, the Dynamics partner, and any incumbent partner?

## Related code references

Paths are relative to the NAS DEV export:

- Orchestration wrapper: `MDM_DB/Staging/Procedures/SP_STANDARDISE_RECORDS().sql`
- Raisers Edge ETL: `MDM_DB/Staging/Procedures/SP_ETL_RAISERS_EDGE().sql`
- HubSpot ETL: `MDM_DB/Staging/Procedures/SP_ETL_HUBSPOT().sql`
- Dynamics ETL: `MDM_DB/Staging/Procedures/SP_ETL_DYNAMICS().sql`
- Match generation: `MDM_DB/MDM/Procedures/SP_BUILD_MATCH_GROUPS().sql`
- Golden records and XREF maintenance: `MDM_DB/GOLD/Procedures/SP_GENERATE_GOLDEN_RECORDS().sql`
- Validation: `MDM_DB/MDM/Procedures/SP_VALIDATE_MDM().sql`
- Task walkthrough: `../../MDM_PROCESSING_WALKTHROUGH.md`
