create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REQUESTS(
	PIPELINE_ID,
	SOURCE_INSTANCE,
	ENTITY_ID,
	GOLDEN_RECORD_ID,
	TARGET_GUID,
	HTTP_METHOD,
	REQUEST_URL,
	REQUEST_BODY,
	AUTH_METHOD,
	AUTH_CONFIG,
	PAYLOAD_MD5
) as

-- Reads the materialised Dynamic Tables joined to D365_WRITEBACK_STATE
-- instead of re-diffing VW_D365_CONTACT/VW_D365_ACCOUNT live on every call.
-- Design history (including a rejected version of this WHERE clause that
-- caused near-certain duplicate dispatches): see
-- nas-snowflake/docs/integration/d365-payload-materialisation.md.
--
-- NEEDS_DISPATCH gates whether there's a live reason to send at all
-- (always TRUE for POST; a field-diff against RAW.DYNAMICS ODS for PATCH).
-- It is ANDed with, never used to override, the state rules below -- ODS
-- lags our own writes, so letting it override would re-dispatch most
-- successful records on the next run. Emit when never sent, or the last
-- attempt was retryable, or PAYLOAD_MD5 has changed since. PRIORITY orders
-- never-sent, retryable, then changed; QUALIFY caps each entity at 2000
-- rows independently.
WITH CONTACT_CTE AS (
    SELECT
        M.PIPELINE_ID,
        M.SOURCE_INSTANCE,
        M.ENTITY_ID,
        C.GOLDEN_RECORD_ID,
        C.TARGET_GUID,
        C.HTTP_METHOD,
        CASE C.HTTP_METHOD
            WHEN 'POST' THEN M.API_BASE_URL || '/contacts'
            WHEN
                'PATCH'
                THEN M.API_BASE_URL || '/contacts(' || C.TARGET_GUID || ')'
        END AS REQUEST_URL,
        C.PAYLOAD AS REQUEST_BODY,
        M.AUTH_METHOD,
        M.AUTH_CONFIG,
        C.PAYLOAD_MD5,
        CASE
            WHEN S.GOLDEN_RECORD_ID IS NULL THEN 1
            WHEN S.IS_RETRYABLE THEN 2
            ELSE 3
        END AS PRIORITY
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
    CROSS JOIN INTEGRATION_DB.DYNAMICS.DT_D365_CONTACT_PAYLOAD AS C
    LEFT JOIN AUDIT_DB.MONITORING.D365_WRITEBACK_STATE AS S
        ON C.GOLDEN_RECORD_ID = S.GOLDEN_RECORD_ID AND S.ENTITY_ID = 'CONTACT'
    WHERE
        M.PIPELINE_ID = 'D365_WRITEBACK'
        AND M.ENTITY_ID = 'CONTACT'
        AND M.ENABLED = TRUE
        AND C.NEEDS_DISPATCH
        AND (
            S.GOLDEN_RECORD_ID IS NULL
            OR S.IS_RETRYABLE
            OR S.LAST_PAYLOAD_MD5 IS DISTINCT FROM C.PAYLOAD_MD5
        )
),

ACCOUNT_CTE AS (
    SELECT
        M.PIPELINE_ID,
        M.SOURCE_INSTANCE,
        M.ENTITY_ID,
        A.GOLDEN_RECORD_ID,
        A.TARGET_GUID,
        A.HTTP_METHOD,
        CASE A.HTTP_METHOD
            WHEN 'POST' THEN M.API_BASE_URL || '/accounts'
            WHEN
                'PATCH'
                THEN M.API_BASE_URL || '/accounts(' || A.TARGET_GUID || ')'
        END AS REQUEST_URL,
        A.PAYLOAD AS REQUEST_BODY,
        M.AUTH_METHOD,
        M.AUTH_CONFIG,
        A.PAYLOAD_MD5,
        CASE
            WHEN S.GOLDEN_RECORD_ID IS NULL THEN 1
            WHEN S.IS_RETRYABLE THEN 2
            ELSE 3
        END AS PRIORITY
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
    CROSS JOIN INTEGRATION_DB.DYNAMICS.DT_D365_ACCOUNT_PAYLOAD AS A
    LEFT JOIN AUDIT_DB.MONITORING.D365_WRITEBACK_STATE AS S
        ON A.GOLDEN_RECORD_ID = S.GOLDEN_RECORD_ID AND S.ENTITY_ID = 'ACCOUNT'
    WHERE
        M.PIPELINE_ID = 'D365_WRITEBACK'
        AND M.ENTITY_ID = 'ACCOUNT'
        AND M.ENABLED = TRUE
        AND A.NEEDS_DISPATCH
        AND (
            S.GOLDEN_RECORD_ID IS NULL
            OR S.IS_RETRYABLE
            OR S.LAST_PAYLOAD_MD5 IS DISTINCT FROM A.PAYLOAD_MD5
        )
),

COMBINED_CTE AS (
    SELECT * FROM CONTACT_CTE
    UNION ALL
    SELECT * FROM ACCOUNT_CTE
)

SELECT
    PIPELINE_ID,
    SOURCE_INSTANCE,
    ENTITY_ID,
    GOLDEN_RECORD_ID,
    TARGET_GUID,
    HTTP_METHOD,
    REQUEST_URL,
    REQUEST_BODY,
    AUTH_METHOD,
    AUTH_CONFIG,
    PAYLOAD_MD5
FROM COMBINED_CTE
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY ENTITY_ID ORDER BY PRIORITY, GOLDEN_RECORD_ID
    ) <= 2000;