CREATE VIEW INTEGRATION_DB.DYNAMICS.VW_D365_EVENTSUBCATEGORY_PILOT_REQUESTS_DEV AS

-- One DEV pilot only. Check Dynamics for Marathon immediately before running.
-- Reconcile any uncertain POST before retrying; do not overlap writers.
WITH PILOT AS (
    SELECT
        'EVENTSUBCATEGORY:' || MD5('MARATHON') AS GOLDEN_RECORD_ID,
        OBJECT_CONSTRUCT(
            'mhnas_eventsubcategoryid', '3cb39ca4-d310-4aa5-9c44-dca36bf9f161',
            'mhnas_name', 'Marathon',
            'mhnas_Category@odata.bind',
                '/mhnas_eventcategories(43ed1d21-70e7-f111-84e9-70a8a575b5fc)'
        ) AS REQUEST_BODY
    WHERE EXISTS (
        SELECT 1
        FROM RAW.RAISERS_EDGE.VW_ODS_T_EVENTATTRIBUTES
        WHERE CATEGORY = 'Event Type Subcategory'
          AND UPPER(TRIM(VALUE)) = 'MARATHON'
    )
)
SELECT
    'D365_EVENTSUBCATEGORY_PILOT' AS PIPELINE_ID,
    M.SOURCE_INSTANCE,
    'EVENTSUBCATEGORY' AS ENTITY_ID,
    P.GOLDEN_RECORD_ID,
    CAST(NULL AS VARCHAR) AS TARGET_GUID,
    'POST' AS HTTP_METHOD,
    M.API_BASE_URL || '/mhnas_eventsubcategories' AS REQUEST_URL,
    P.REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG,
    MD5(TO_VARCHAR(P.REQUEST_BODY)) AS PAYLOAD_MD5
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
CROSS JOIN PILOT AS P
WHERE M.PIPELINE_ID = 'D365_WRITEBACK'
  AND M.SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
  AND M.ENTITY_ID = 'CAMPAIGN'
  AND M.API_BASE_URL = 'https://nasdatamig.crm11.dynamics.com/api/data/v9.2'
  AND NOT EXISTS (
      SELECT 1
      FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE AS S
      WHERE S.ENTITY_ID = 'EVENTSUBCATEGORY'
        AND S.GOLDEN_RECORD_ID = P.GOLDEN_RECORD_ID
  )
  AND NOT EXISTS (
      SELECT 1
      FROM MDM_DB.GOLD.XREF AS X
      WHERE X.SOURCE_SYSTEM = 'DYNAMICS'
        AND (
            X.GOLDEN_RECORD_ID = P.GOLDEN_RECORD_ID
            OR (
                X.GOLDEN_RECORD_ID LIKE 'EVENTSUBCATEGORY:%'
                AND LOWER(TRIM(X.SOURCE_RECORD_ID)) =
                    '3cb39ca4-d310-4aa5-9c44-dca36bf9f161'
            )
        )
  )
QUALIFY COUNT(*) OVER (PARTITION BY P.GOLDEN_RECORD_ID) = 1;
