# Consent Type DEV handover

## Status at 27 November 2026

**Existing reference data verified; four mappings outstanding.**

The user supplied Snowflake results and live Dynamics DEV API responses.
All 18 matched Consent Types have the same IDs in both systems and are
active in Dynamics (`statecode = 0`). Four additional names produced by
the current rule view have no matching type in either supplied result.

No Consent Types were created, updated or migrated during this review.
No ADF pipeline was run, no dispatcher routes were added and no business
mapping gates were closed. This is reference-data readiness verification,
not a completed migration pilot or approval of the consent rules.

## Workbook scope and ownership

| Item | Value |
|---|---|
| Workbook | [Mapping V6](<./NAS DM Source to Target Mappings Current WIP 1.xlsx>), rows 2925-2943 |
| Dynamics object | `mha_consenttype` |
| Entity set | `mha_consenttypes` |
| Primary ID | `mha_consenttypeid` |
| Y field | Name, `mha_name`, row 2930 |
| Workbook source | CodeDescriptions: Description |
| DEV environment | `https://nasdatamig.crm11.dynamics.com` |

Workbook row 2930 describes deriving type names from preference code
descriptions, including removing a preceding "No" and excluding specified
marker values. Its later note states:

> mhance will load these not Clekt, they will need to be made available
> for migration

Accordingly, missing reference values should be referred to mhance and the
business, not automatically created by this migration implementation.
The workbook also leaves NAS to determine which types to create.

The existing implementation derives its current list from live RE
constituent attributes through the consent-rule view, rather than directly
enumerating all code descriptions. Therefore the 22 returned names are
the current rule-derived list, not proof of exhaustive workbook coverage.

## Existing implementation

| File | Role |
|---|---|
| [Consent Type view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_MHA_CONSENTTYPE.sql) | Derives distinct type names from the rule view and matches Dynamics extract names ignoring case and padding. Returns `EXISTS` or `HOLD`, never `CREATE`. |
| [Consent rule view](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_REF_CONSENT_RULE.sql) | Derives channels, type names and proposed consent values from RE attributes, and resolves type IDs from the Dynamics extract. Rules still require business approval. |
| [Load gates](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_REF_LOAD_GATE.sql) | Existing business/safety gates remain unchanged. |

The Consent Type view selects the oldest Dynamics extract row when
multiple records have the same normalised name. This is an implementation
choice, not approved duplicate resolution. It does not filter that extract
by active state. Live state was separately verified for the 18 matches
during this review.

Reference type availability does not establish a person's consent or
approve transforming a source preference into an opt-in.

## Verified matches

All entries below returned `EXISTS` with no hold reason in Snowflake, and
the same name and ID with `statecode = 0` in the supplied live API response.

| Type | Dynamics ID |
|---|---|
| Autism News | `b2825be3-c160-f111-a825-7ced8d9cafea` |
| Community Fundraising | `b4825be3-c160-f111-a825-7ced8d9cafea` |
| Donations | `b6825be3-c160-f111-a825-7ced8d9cafea` |
| Event Fundraising | `b8825be3-c160-f111-a825-7ced8d9cafea` |
| FPS All Channels | `57a9f24a-c260-f111-a826-7ced8d9b988d` |
| Gift Aid Acquisition | `cc825be3-c160-f111-a825-7ced8d9cafea` |
| Individual Giving Newsletters | `ba825be3-c160-f111-a825-7ced8d9cafea` |
| Legacy Marketing | `bc825be3-c160-f111-a825-7ced8d9cafea` |
| Lottery | `04835be3-c160-f111-a825-7ced8d9cafea` |
| Marketing All Channels | `89b9f744-c260-f111-a826-7ced8d9b988d` |
| Membership | `be825be3-c160-f111-a825-7ced8d9cafea` |
| Merchandise & Publications | `c0825be3-c160-f111-a825-7ced8d9cafea` |
| Philanthropy | `c2825be3-c160-f111-a825-7ced8d9cafea` |
| Political Campaigns | `c4825be3-c160-f111-a825-7ced8d9cafea` |
| Professional News | `c6825be3-c160-f111-a825-7ced8d9cafea` |
| Raffle Tickets | `fc825be3-c160-f111-a825-7ced8d9cafea` |
| Schools & Services | `c8825be3-c160-f111-a825-7ced8d9cafea` |
| Volunteering Opportunities | `ca825be3-c160-f111-a825-7ced8d9cafea` |

The live response also contained other types. Their presence does not
establish that they are needed for RE migration or approve mapping an
unmatched source name to a similar target name.

## Four unresolved names

| Rule-derived name | Snowflake result | Live response |
|---|---|---|
| Help Mailing | `HOLD / CLIENT_LOADS` | No matching name |
| Membership Payments | `HOLD / CLIENT_LOADS` | No matching name |
| Newsletter | `HOLD / CLIENT_LOADS` | No matching name |
| Unsolicited Mail | `HOLD / CLIENT_LOADS` | No matching name |

For each, NAS/mhance must decide whether to create a type, approve a
specific existing equivalent or exclude it. Do not equate "Newsletter"
with one of the several existing newsletter types without confirmation.
Keep dependent Consent rows held while their type is unresolved.

## Repeatable proof: RE extract -> Snowflake -> Dynamics

### Source-derived rule evidence

This read-only query shows the RE attribute names and values feeding the
current rule-derived type list. It does not return constituent IDs.
Its output was not supplied during this review; it is a follow-up evidence
query, not an already completed validation.

```sql
SELECT DISTINCT
    RE_ATTRIBUTE_NAME,
    RE_VALUE,
    CONSENT_TYPE,
    D365_CONSENT_TYPE_ID,
    MAP_STATUS
FROM INTEGRATION_DB.DYNAMICS.VW_D365_REF_CONSENT_RULE
WHERE NULLIF(TRIM(CONSENT_TYPE), '') IS NOT NULL
ORDER BY CONSENT_TYPE, RE_ATTRIBUTE_NAME, RE_VALUE;
```

### Snowflake matching evidence

The user ran:

```sql
SELECT RE_CONSENT_TYPE, D365_ID, LOAD_ACTION, HOLD_REASON
FROM INTEGRATION_DB.DYNAMICS.VW_D365_MHA_CONSENTTYPE
ORDER BY LOAD_ACTION, RE_CONSENT_TYPE;
```

Supplied result: 18 `EXISTS`, four `HOLD / CLIENT_LOADS`.
These results reference the Snowflake Dynamics extract and may change
after source or target refreshes.

### Live Dynamics evidence

The user retrieved:

```text
https://nasdatamig.crm11.dynamics.com/api/data/v9.2/EntityDefinitions(LogicalName='mha_consenttype')?$select=EntitySetName,PrimaryIdAttribute
```

Returned entity set `mha_consenttypes`, primary ID `mha_consenttypeid`.

```text
https://nasdatamig.crm11.dynamics.com/api/data/v9.2/mha_consenttypes?$select=mha_consenttypeid,mha_name,statecode&$orderby=mha_name
```

The supplied response confirmed the 18 matches and did not include an
`@odata.nextLink`. For future checks, follow any returned next link before
concluding a type is absent.

In Power Apps, select the environment matching the DEV URL, open
Tables -> Consent Type -> Data, and inspect Name and the record ID.
No new test record should be expected from this review.

## Business decisions and next steps

1. Confirm the treatment of the four unresolved names and mhance's
   responsibility for any additions.
Help Mailing
Membership Payments
Newsletter
Unsolicited Mail

--Show unresolved consent types 
SELECT RE_CONSENT_TYPE, LOAD_ACTION, HOLD_REASON
FROM INTEGRATION_DB.DYNAMICS.VW_D365_MHA_CONSENTTYPE
WHERE D365_ID IS NULL
ORDER BY RE_CONSENT_TYPE;

2. Approve the required reference list and source-to-type mappings,
   including exclusions and any retired values. Existing name matches
   demonstrate technical resolution, not semantic business approval.
3. If types change, refresh the Dynamics extract and rerun the match and
   live-state checks. Check duplicate names instead of relying on the
   view's oldest-record choice as a business rule.
4. Proceed to assess a Consent DEV pilot using a verified existing type.
   First confirm target metadata, actual source meaning, identity,
   duplicates, privacy and automation safeguards. Do not infer permission
   to contact someone from absent or unclear source values.

No Consent record has been created as part of this Consent Type review.
Full Consent migration remains separate work.

### Subsequent Consent pilot preparation

Update: the user subsequently reported ADF run success. Final Dynamics
readback, tracking and audit results remain outstanding; see the
[Consent DEV handover](./CONSENT_DEV_HANDOVER.md) for the current status
and proof queries. The preparation notes below describe the pre-run setup.

The user approved preparing a fixed DEV opt-out and local dispatcher route,
using existing Donations type `b6825be3-c160-f111-a825-7ced8d9cafea`.
No additional Consent Type creation is needed. The supplied source history
for anchor attribute `2273445` contains one explicit No Donations row per
channel, all dated 23 August 2012, plus four No Political Campaigns rows.
The live Contact `1bcce781-9ee0-f111-84ea-002248425074` was active and a live
search returned no Donations consents for it. These are point-in-time checks.

The proposed payload sets all four channels explicitly to Out (`862940001`),
omits dates/comments/declared-by fields with the user's approval, and uses
planned ID `9d1fdf0d-00cd-40a0-a40d-8e06e6053af8`. Tracking uses
`CONSENT_TEST:2273445` outside shared XREF. Political Campaigns is not loaded
by this pilot. The user confirmed DEV automation safety.

Prepared files, requiring Snowflake compilation and role-isolated checks:

- [Tracking setup and grants](./AUDIT_DB/Config/CONSENT_PILOT_TRACKING_DEV.sql)
- [Fixed opt-out preview](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_CONSENT_PILOT_PREVIEW_DEV.sql)
- [DEV request](./INTEGRATION_DB/DYNAMICS/Views/VW_D365_CONSENT_PILOT_REQUESTS_DEV.sql)
- [Approved local dispatcher route](<./ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.json>)

The preview holds on changes to the eight reviewed preference rows, privacy,
Party identity or type resolution. Live duplicates, Contact/type state,
string constraints, capture and audit access must be checked before dispatch.
The planned ID aids reconciliation; it does not replace those checks or make
the guards atomic. No Consent write or capture is yet verified.

Suggested status wording:

> Consent Type reference-data readiness has been checked in DEV. Eighteen
> rule-derived types resolve to matching active Dynamics records. Four
> unmatched names remain with NAS/mhance for a mapping or loading decision.
> No new Consent Types were created; existing verified types are available
> for a suitably approved Consent pilot.

They’re unresolved because:

Our existing rules derive these names from RE preference values.
No matching Consent Type name was found in the Snowflake Dynamics extract or the live Dynamics response.
We have no approved decision to create them, map them to another type or exclude them.
So “unresolved” means the target mapping is missing, not that they are technically impossible to migrate. The view holds them as CLIENT_LOADS because the workbook assigns loading to mhance.

14:07
4s
•
 
but if 1. No matching Consent Type name was found in the Snowflake Dynamics extract or the live Dynamics response. why shouldn't we just create

14:12
We can create them if they are genuinely required new types. Their absence alone doesn’t establish that: they might need mapping to an existing type, renaming or excluding.

The reason to check first is to avoid creating competing categories—for example, a generic Newsletter alongside existing specific newsletter types. The workbook also assigns creation to mhance.

So this is a reference-data ownership and mapping decision, not a technical blocker. With agreement on the four names and DEV creation, we can proceed.





