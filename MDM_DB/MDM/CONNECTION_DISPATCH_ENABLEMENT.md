# CONNECTION picked up by DispatchRequests

## Objective
Make `CONNECTION` rows flow into `PL_D365_DispatchRequests` the same way `CONTACT` and `ACCOUNT` already do.

## Plain-English flow
1. `PL_D365_Writeback` reads enabled entities from `AUDIT_DB.CONFIG.PIPELINE_METADATA`.
2. For each entity, it calls `PL_D365_DispatchRequests`.
3. The child pipeline only sends rows returned by `INTEGRATION_DB.DYNAMICS.VW_D365_REQUESTS`.
4. Therefore, for `CONNECTION` to be sent, two things must exist:
   - `CONNECTION` row in metadata (`PIPELINE_METADATA`)
   - `CONNECTION` rows emitted by `VW_D365_REQUESTS`

## What was changed

### 1) Request view now emits CONNECTION requests
Updated [INTEGRATION_DB/DYNAMICS/Views/VW_D365_REQUESTS.sql](INTEGRATION_DB/DYNAMICS/Views/VW_D365_REQUESTS.sql):
- Added `CONNECTION_CTE`
- Added `UNION ALL SELECT * FROM CONNECTION_CTE`
- Uses endpoint `/connections`
- Emits only actionable rows (`LOAD_ACTION='CREATE'` and no hold reason)
- Uses stable key `CONNECTION:<RE_RELATIONSHIP_ID>` for writeback-state tracking

### 2) Dispatch pipeline now reads CONNECTION ID on POST response
Updated [ADF Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.txt](ADF%20Pipeline/Dynamics/PL_D365_DISPATCHREQUESTS.txt):
- POST `?$select=` expression now handles:
  - `CONTACT -> contactid`
  - `ACCOUNT -> accountid`
  - `CONNECTION -> connectionid`
- XREF capture expression reads `connectionid` when entity is `CONNECTION`

### 3) Metadata upsert script provided
Created [INTEGRATION_DB/DYNAMICS/Views/Mycode/ENABLE_CONNECTION_DISPATCH.sql](INTEGRATION_DB/DYNAMICS/Views/Mycode/ENABLE_CONNECTION_DISPATCH.sql):
- Upserts metadata row for:
  - `PIPELINE_ID = D365_WRITEBACK`
  - `SOURCE_INSTANCE = SNOWFLAKE_DEV`
  - `ENTITY_ID = CONNECTION`
  - `ENABLED = TRUE`
- Includes verification queries and optional rollback

## Runbook (minimal)
1. Deploy view changes.
2. Run [INTEGRATION_DB/DYNAMICS/Views/Mycode/ENABLE_CONNECTION_DISPATCH.sql](INTEGRATION_DB/DYNAMICS/Views/Mycode/ENABLE_CONNECTION_DISPATCH.sql).
3. Confirm `VW_D365_REQUESTS` returns `ENTITY_ID='CONNECTION'` rows.
4. Debug `PL_D365_Writeback` with small `TestRowsPerCombo`.
5. In monitor, confirm child `LKP_GetRequests` count > 0 for `CONNECTION`.

## Success criteria
- `FE_ProcessEntities` includes entity `CONNECTION`.
- Child `LKP_GetRequests` returns non-zero rows for `CONNECTION`.
- POSTs execute against Dataverse `/connections` endpoint.
- Response logging rows appear for `ENTITY_ID='CONNECTION'`.
