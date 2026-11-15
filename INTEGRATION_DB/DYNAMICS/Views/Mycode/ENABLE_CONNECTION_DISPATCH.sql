-- ============================================================================
-- ENABLE_CONNECTION_DISPATCH.sql
-- Purpose:
--   Enable CONNECTION rows to be picked up by PL_D365_Writeback /
--   PL_D365_DispatchRequests.
--
-- What this script does:
--   1) Upserts PIPELINE_METADATA for ENTITY_ID = 'CONNECTION'
--      under PIPELINE_ID = 'D365_WRITEBACK'.
--   2) Verifies metadata exists and is enabled.
--   3) Verifies VW_D365_REQUESTS is emitting CONNECTION rows.
--
-- Notes:
--   - This script assumes the updated VW_D365_REQUESTS view has already been
--     deployed (with CONNECTION_CTE and UNION ALL inclusion).
--   - Set SOURCE_INSTANCE to your environment value if different.
-- ============================================================================

-- 1) UPSERT metadata row so FE_ProcessEntities can include CONNECTION.
MERGE INTO AUDIT_DB.CONFIG.PIPELINE_METADATA AS T
USING (
    SELECT
        'D365_WRITEBACK' AS PIPELINE_ID,
        'SNOWFLAKE_DEV' AS SOURCE_INSTANCE,
        'CONNECTION' AS ENTITY_ID,
        'VIEW' AS SOURCE_TYPE,
        'FULL' AS LOAD_TYPE,
        'https://nasdatamig.crm11.dynamics.com/api/data/v9.2' AS API_BASE_URL,
        'managed_identity' AS AUTH_METHOD,
        PARSE_JSON('{"credentialReference":"cred-mi-prod-df","resource":"https://nasdatamig.crm11.dynamics.com"}') AS AUTH_CONFIG,
        'INTEGRATION_DB' AS TARGET_DATABASE,
        'DYNAMICS' AS TARGET_SCHEMA,
        'CONNECTION' AS TARGET_TABLE,
        30 AS EXECUTION_ORDER,
        TRUE AS ENABLED,
        'Enable Dataverse Connection dispatch via VW_D365_REQUESTS' AS NOTES
) AS S
ON  T.PIPELINE_ID = S.PIPELINE_ID
AND T.SOURCE_INSTANCE = S.SOURCE_INSTANCE
AND T.ENTITY_ID = S.ENTITY_ID
WHEN MATCHED THEN UPDATE SET
    T.SOURCE_TYPE = S.SOURCE_TYPE,
    T.LOAD_TYPE = S.LOAD_TYPE,
    T.API_BASE_URL = S.API_BASE_URL,
    T.AUTH_METHOD = S.AUTH_METHOD,
    T.AUTH_CONFIG = S.AUTH_CONFIG,
    T.TARGET_DATABASE = S.TARGET_DATABASE,
    T.TARGET_SCHEMA = S.TARGET_SCHEMA,
    T.TARGET_TABLE = S.TARGET_TABLE,
    T.EXECUTION_ORDER = S.EXECUTION_ORDER,
    T.ENABLED = S.ENABLED,
    T.NOTES = S.NOTES,
    T.MODIFIED = CURRENT_TIMESTAMP(),
    T.MODIFIED_BY = CURRENT_USER()
WHEN NOT MATCHED THEN INSERT (
    PIPELINE_ID,
    SOURCE_INSTANCE,
    ENTITY_ID,
    SOURCE_TYPE,
    LOAD_TYPE,
    API_BASE_URL,
    AUTH_METHOD,
    AUTH_CONFIG,
    TARGET_DATABASE,
    TARGET_SCHEMA,
    TARGET_TABLE,
    EXECUTION_ORDER,
    ENABLED,
    CREATED,
    CREATED_BY,
    NOTES
) VALUES (
    S.PIPELINE_ID,
    S.SOURCE_INSTANCE,
    S.ENTITY_ID,
    S.SOURCE_TYPE,
    S.LOAD_TYPE,
    S.API_BASE_URL,
    S.AUTH_METHOD,
    S.AUTH_CONFIG,
    S.TARGET_DATABASE,
    S.TARGET_SCHEMA,
    S.TARGET_TABLE,
    S.EXECUTION_ORDER,
    S.ENABLED,
    CURRENT_TIMESTAMP(),
    CURRENT_USER(),
    S.NOTES
);

-- 2) Verify metadata row exists and is enabled.
SELECT
    PIPELINE_ID,
    SOURCE_INSTANCE,
    ENTITY_ID,
    API_BASE_URL,
    AUTH_METHOD,
    ENABLED,
    EXECUTION_ORDER,
    MODIFIED,
    NOTES
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA
WHERE PIPELINE_ID = 'D365_WRITEBACK'
  AND SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
  AND ENTITY_ID = 'CONNECTION';

-- 3) Verify requests are emitted for dispatch.
SELECT
    ENTITY_ID,
    HTTP_METHOD,
    COUNT(*) AS ROWS_READY
FROM INTEGRATION_DB.DYNAMICS.VW_D365_REQUESTS
WHERE PIPELINE_ID = 'D365_WRITEBACK'
  AND SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
  AND ENTITY_ID = 'CONNECTION'
GROUP BY ENTITY_ID, HTTP_METHOD;

-- 4) Inspect sample rows to confirm endpoint/payload.
SELECT
    GOLDEN_RECORD_ID,
    HTTP_METHOD,
    REQUEST_URL,
    PAYLOAD_MD5,
    REQUEST_BODY
FROM INTEGRATION_DB.DYNAMICS.VW_D365_REQUESTS
WHERE PIPELINE_ID = 'D365_WRITEBACK'
  AND SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
  AND ENTITY_ID = 'CONNECTION'
LIMIT 20;

-- 5) Optional rollback: disable CONNECTION dispatch without deleting metadata.
-- UPDATE AUDIT_DB.CONFIG.PIPELINE_METADATA
-- SET ENABLED = FALSE,
--     MODIFIED = CURRENT_TIMESTAMP(),
--     MODIFIED_BY = CURRENT_USER(),
--     NOTES = 'Temporarily disabled CONNECTION dispatch'
-- WHERE PIPELINE_ID = 'D365_WRITEBACK'
--   AND SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
--   AND ENTITY_ID = 'CONNECTION';
