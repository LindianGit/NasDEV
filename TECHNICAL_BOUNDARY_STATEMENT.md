# Technical boundary: NAS integration work and Dynamics-side activities

Status: **DRAFT, not yet confirmed** with Alexander or the Dynamics partner (Emma Hunt).
Contract scope item 3. Prepared 3 Nov 2026 by Lindian.

Sources: talks (Nas_Talks.txt, line 55), SPEC_2_DYNAMICS_MIGRATION_SNOWFLAKE_BUILD.md (section 1), RAISERS_EDGE_REMOVAL_SPEC.md (lines 29, 113, 176), CURRENT_STATE_DIAGRAM.txt.

## Principle

NAS pushes data to a landing zone and API that the Dynamics partner provides. NAS is responsible for getting correct, ready-to-send data to that landing zone. The Dynamics partner is responsible for what the landing zone accepts and everything that happens inside Dynamics.

## Boundary

| NAS side (integration) | Dynamics partner side |
|---|---|
| **Snowflake data layers:** Raisers Edge load into Snowflake (ADF to `STG_T_*`, then `ODS_T_*`) and the Dynamics-to-Snowflake pull | **Landing zone:** the endpoint NAS pushes to, its availability and its environments (including any test environment) |
| **MDM:** standardise, match, golden records and cross-reference of source IDs | **API:** contract, authentication, rate and size limits |
| **Mapping to Dynamics fields:** applying the agreed workbook, business rules and lookup values | **Field names and keys:** the target schema, required fields and option-set values it accepts |
| **Payload build:** `VW_D365_CONTACT`, `VW_D365_ACCOUNT` and the payload tables. Requests are POST or PATCH, with batch limits and load gates | **Validation:** what it accepts or rejects, duplicate rules and error responses |
| **Push (ADF):** moving ready-to-send payloads to the API, with retries and monitoring | **Anything inside Dynamics:** configuration, plug-ins, workflows, security and user access |
| **ID capture:** storing the Dynamics ID returned for each record (`XREF`, `D365_WRITEBACK_STATE`) and the legacy Raisers Edge ID | **Dynamics documentation** for the data model, and fixes for any landing-zone defects |
| **Data quality and reconciliation** of what NAS sends, and handling of failed records on the NAS side | **Cut-over inside Dynamics:** go-live, user acceptance and Dynamics-side data checks |

## Hand-off point

Snowflake exposes ready-to-send rows per Dynamics entity (request type, key, JSON body) and accepts back a result per row (success, failure, returned Dynamics ID). The code already works this way (`VW_D365_REQUESTS`, 2,000 rows per entity per run).

## Status of each statement

| Item | Status |
|---|---|
| NAS pushes to a partner-provided landing zone | Confirmed in the talks (Ben/Alex) |
| Partner owns the landing zone and API | Confirmed in the talks; written agreement not seen |
| Payload build, ID capture and MDM are NAS side | Assumed from the specs |
| Who builds and runs the ADF push (NAS, incumbent partner or another party) | **Unknown** |
| What the landing zone accepts (formats, limits, keys, error responses) | **Unknown** |
| Who owns the legacy Raisers Edge ID field and failed-record handling | **Unknown** |
| Whether a Dynamics test environment exists, and when | **Unknown** |

## Questions to close

1. Alexander: do you agree with this split, and who builds and runs the ADF push?
2. Emma Hunt: what does the landing zone accept (formats, limits, keys, error responses, authentication)?
3. Emma Hunt: which field holds the legacy Raisers Edge ID, and who maintains it?
4. Who handles records the landing zone rejects, and how are they reported back?
5. Is there a Dynamics test environment for dress rehearsals, and when?
6. Is the mapping workbook the agreed source of truth, and who updates it?
