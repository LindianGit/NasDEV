# Tax Declaration DEV pilot handover

## Status and scope

One Raiser’s Edge (RE) Tax Declaration was migrated as a technical pilot in
Dynamics DEV. This is not a full load or a mapping-complete declaration.
Further work remains DEV-only until the business agrees scope and mappings.

| Name | Value |
|---|---|
| Dynamics display name | Tax Declaration (plural: Tax Declarations) |
| Dynamics logical name | `msnfp_giftaiddeclaration` |
| Dynamics entity set | `msnfp_giftaiddeclarations` |
| RE source table | `T_TaxDeclarations` |
| Snowflake RE extract | `RAW.RAISERS_EDGE.VW_ODS_T_TAXDECLARATIONS` |

The Dynamics names above were confirmed from DEV entity metadata. The
Snowflake view is an extract of RE data; it is not the live RE application.

## What was done

1. Reviewed Tax Declaration in the local WIP mapping workbook, sheet
   **Mapping V6**, rows 1451–1493, and checked the Snowflake source columns.
2. Profiled the source, available Dynamics delivery choices, declaration
   sources, declaration types, date fields and customer-ID resolution.
   The results are a point-in-time DEV assessment, not final load counts.
3. Selected RE declaration `73108`, associated with RE constituent `379376`
   and Dynamics Contact `6c497cd8-1de1-f111-84ea-002248425074`. The Contact
   was verified as active in Dynamics DEV.
4. Checked live Dynamics DEV for an existing declaration with source ID
   `73108` and for declarations linked to this Contact; both searches returned
   no rows at that time.
5. Prepared a fixed one-row preview and request view. The preview checks the
   source and customer resolution and privacy status; the request view has
   writeback-state and XREF guards and is restricted to this DEV candidate.
6. Added the Tax Declaration route, response-ID selection and XREF capture
   branch to the local dispatcher. The user operated ADF DEV and reported a
   successful run; pipeline publication status is not confirmed here.
7. Verified the returned Dynamics ID in Snowflake XREF and read the record
   back from Dynamics DEV.

### Pilot payload

The request contained only:

```json
{
  "mha_sourceid": "73108",
  "mha_sourcesystem": "RE",
  "msnfp_CustomerId_contact@odata.bind": "/contacts(6c497cd8-1de1-f111-84ea-002248425074)"
}
```

In particular, declaration type, dates, source lookup, delivery method,
name and comments were not sent. The source record had an Internet indicator
and NAS Website source, but these were not included in the pilot payload.

The user explicitly chose to continue the DEV technical pilot without a
confirmed declaration type. Dynamics metadata reported the type as
`ApplicationRequired`; the API accepted this particular record without it,
and readback confirmed it was null. This does **not** make a blank type an
approved business rule or establish how other applications or automations
handle it.

### Pilot evidence

| Layer | Result |
|---|---|
| Snowflake source | RE declaration `73108`, constituent `379376` |
| Request preview | One POST, key `TAXDECLARATION:73108` |
| ADF DEV | User reported success |
| Snowflake XREF | `TAXDECLARATION:73108` / `DYNAMICS` / `f4b29a07-8ae9-f111-84e9-70a8a575b39d` |
| Dynamics DEV readback | Same ID; source ID `73108`, source system `RE`, Contact `6c497cd8-1de1-f111-84ea-002248425074`, declaration type null |

No separate writeback audit or HTTP-status result was provided for this
pilot. The XREF and live readback verify this single create and ID capture.

### Read-only proof

```sql
SELECT
    T.ID AS RE_DECLARATION_ID,
    T.CONSTITUENTID AS RE_CONSTITUENT_ID,
    T.DATEDECLARATIONMADE,
    T.DATESTART,
    T.DATEFINISH,
    T.TAXDECLARATIONINDICATORDESCRIPTION,
    T.TAXDECLARATIONSOURCEDESCRIPTION,
    X.SOURCE_RECORD_ID AS DYNAMICS_DECLARATION_ID
FROM RAW.RAISERS_EDGE.VW_ODS_T_TAXDECLARATIONS T
LEFT JOIN MDM_DB.GOLD.XREF X
    ON X.GOLDEN_RECORD_ID = 'TAXDECLARATION:' || TO_VARCHAR(T.ID)
   AND X.SOURCE_SYSTEM = 'DYNAMICS'
WHERE T.ID = 73108;
```

The dates and descriptions in this proof query are source values, **not**
evidence that those fields were migrated.

```text
GET https://nasdatamig.crm11.dynamics.com/api/data/v9.2/msnfp_giftaiddeclarations(f4b29a07-8ae9-f111-84e9-70a8a575b39d)?$select=msnfp_giftaiddeclarationid,mha_sourceid,mha_sourcesystem,_msnfp_customerid_value,_mha_taxdeclarationtypeid_value
```

## Code and execution

- [Pilot preview view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_TAXDECLARATION_PILOT_PREVIEW_DEV.sql)
- [Pilot request view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_TAXDECLARATION_PILOT_REQUESTS_DEV.sql)
- [Local dispatcher](<./ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>)
- [Source-to-target workbook](<./NAS DM Source to Target Mappings Current WIP 1.xlsx>)

The user created the views in Snowflake DEV and operated ADF DEV. The local
dispatcher JSON and expression delimiters passed static checks; those checks
do not establish equivalence with a live ADF version or test other objects.
The live procedure captured an XREF for this one pilot; its general behavior
for a full Tax Declaration load has not been validated.

The request view is hard-coded to one source ID, one Contact and the DEV API
base URL. It is not a batch loader. Its state and XREF checks are not an
atomic concurrency control, and it does not itself query live Dynamics for
duplicates. Do not rerun an uncertain POST or use this view to load further
records; reconcile the live target, XREF and writeback status first.

## Workbook mapping and gaps

Mapping V6 marks the following 14 fields **Y for migration/sync**. That is
not the same as Dataverse API create-required metadata. Source names below
are candidate mappings based on the workbook and Snowflake source columns;
they have not been approved for a full load.

| Row | Dynamics field | Candidate RE / Snowflake source or rule |
|---:|---|---|
| 1462 | End Date (`mha_enddate`) | `DATEFINISH`; blank handling needs agreement |
| 1463 | Name (`mha_name`) | Not identified |
| 1466 | Source ID (`mha_sourceid`) | `ID`; included in pilot |
| 1467 | Source System (`mha_sourcesystem`) | RE value; included in pilot |
| 1468 | Start Date (`mha_startdate`) | `DATESTART` |
| 1469 | Tax Authority (`mha_taxauthorityid`) | Workbook lists a GUID; verify the target and approved rule in DEV |
| 1470 | Tax Declaration Type (`mha_taxdeclarationtypeid`) | Type rule not agreed; `PAYSTAX` and taxpayer status require review |
| 1472 | Comments (`mhnas_comments`) | `COMMENTS`; privacy and inclusion need agreement |
| 1473 | Confirmation Date (`mhnas_confirmationdate`) | `DATECONFIRMATIONSENT` |
| 1475 | Source (`mhnas_taxdeclarationsourceid`) | Source code/description needs an approved Dynamics lookup mapping |
| 1479 | Generated For (`msnfp_customerid`) | `CONSTITUENTID`, resolved to a permitted Dynamics customer; Contact included in pilot |
| 1480 | Declaration Date (`msnfp_declarationdate`) | `DATEDECLARATIONMADE` |
| 1481 | Declaration Delivered (`msnfp_declarationdelivered`) | Declaration indicator needs an approved choice mapping |
| 1482 | Gift Aid Declaration ID (`msnfp_giftaiddeclarationid`) | Workbook says new GUID; Dynamics generated the pilot ID |

Confirm the authoritative workbook and resolve every migration-required
field, including whether to populate it, hold the record or agree an
exception. API acceptance of the pilot is not mapping sign-off.

## Point-in-time profiling

- The source view contained **176,487 rows**, with **176,487 distinct IDs**
  and no missing declaration IDs. **3,625** rows lacked a constituent ID.
- Source indicators were Written **71,693**, Oral **50,532**, Internet
  **54,088** and blank **174**.
- Dynamics DEV delivery choices were Online (`844060000`), Verbal
  (`844060001`) and Mail (`844060002`). Internet → Online and Oral → Verbal
  are candidates; Written → Mail is not necessarily equivalent. None of
  these mappings was included in the pilot or approved for a full load.
- `PAYSTAX` and taxpayer-status values sometimes disagree. Dynamics DEV has
  active Enduring, Non-Tax Payer and One-Off types. A reliable rule for
  choosing among them has not been agreed.
- The source profile found **38,712** declarations with source `Unknown`,
  **2,499** with a blank source code and **26** with a code but no
  description. Some named sources, including Historical Declaration and IG
  Pure, had no exact match in the returned Dynamics DEV list. Similar names
  must not be assumed equivalent; `Unknown` exists as an active target value
  but its use still requires a decision.
- Blank counts were **18,156** declaration dates, **0** start dates,
  **160,831** end dates and **136,800** confirmation-sent dates. All
  nonblank values passed the session's automatic timestamp parsing; this does
  not approve date interpretation, timezone or missing-value rules.
- The customer diagnostic classified **165,017** rows as having neither
  Contact nor Account ID exposed by the Snowflake golden-ID view, **7,420**
  as having no RE XREF, **3,625** as missing a constituent ID, **423** as
  exposing a Contact and **2** an Account. These are row counts, not counts
  of distinct supporters. Missing exposed IDs do not prove the Dynamics
  records do not exist. The view can select one ID from underlying matches,
  so an exposed ID alone does not establish uniqueness.

## Business questions for a full load

1. Which declarations are in scope: all historical declarations, only
   current declarations, or a date-bounded subset? How should expired,
   cancelled and other historical records be treated?
2. How can we determine whether an RE declaration is **Enduring**,
   **Non-Tax Payer** or **One-Off**? What should happen where `PAYSTAX` and
   taxpayer status disagree or are unknown? What is the correct type for
   pilot declaration `73108`?
3. Do Internet, Oral and Written correspond to Dynamics Online, Verbal and
   Mail? What should happen when the indicator is blank? In particular, does
   every Written declaration mean it was delivered by mail?
4. What do blank declaration dates, end dates and confirmation dates mean?
   May they remain blank, should a value be derived, or should the record be
   held? Confirm how declaration and start dates should be interpreted.
5. How should each RE declaration source map to the Dynamics source list?
   What should happen to `Unknown`, blank values, missing descriptions and
   names with no exact match? Should any new sources be created?
6. Which Tax Authority applies, and is the workbook’s authority reference
   correct for the records in scope?
7. What should happen to declarations without a constituent or without a
   resolvable Dynamics customer? Are Account-linked declarations in scope?
8. Should multiple or overlapping declarations for a supporter all be kept?
   How should an existing Dynamics declaration be matched to an RE record,
   and what should happen when a possible duplicate is found?
9. What should populate Declaration Name and other workbook-required
   fields? Are there approved exceptions for missing values? Should comments
   be migrated, and are there sensitive-data or retention restrictions?
10. Is this a one-time migration or an ongoing sync? How should later
    corrections and deletions be handled? Who approves the mappings,
    exception counts and final reconciliation?

## Work required before a full load

1. Record business decisions, identify the authoritative workbook and update
   the mapping, lookup crosswalks and relevant payload rules. Verify source
   date formats, timezone handling, target constraints and DEV automations.
2. Investigate missing customer IDs and RE XREFs; reconcile to live Dynamics
   and resolve genuine duplicates and privacy holds. Do not create customer
   IDs or use fallback mappings without an approved rule.
3. Reconcile existing Dynamics declarations and the pilot record. Decide
   how the pilot's omitted fields are to be completed without creating a
   duplicate; confirm whether it remains in scope.
4. Build a separate generalised preview and request path with explicit hold
   reasons, source/customer/lookup uniqueness checks, privacy controls,
   target duplicate checks, XREF conflict handling and payload validation.
   Do not simply remove the pilot's fixed-ID filters.
5. Design bounded DEV batches, non-overlapping execution, stable identity,
   uncertain-POST recovery and rerun/update behavior. The existing pilot
   XREF and state guards alone do not guarantee concurrency-safe creation.
6. Re-profile current data, review eligible and held counts, then reconcile
   each approved DEV batch across source, Dynamics, XREF and writeback
   audit. Obtain business acceptance of counts, exceptions and samples
   before considering any environment beyond DEV.
