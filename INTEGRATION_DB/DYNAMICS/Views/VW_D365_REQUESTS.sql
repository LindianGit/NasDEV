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
--
-- Plain-English summary for non-technical readers:
-- This view is the "outbox" for ADF. If a row appears here, the pipeline will
-- try to send it to Dataverse. If a row does not appear here, ADF will never
-- see it.
--
-- Contact and Account rows come from dynamic payload tables.
-- Connection rows come directly from VW_D365_CONNECTION because Connections are
-- currently create-only in this design (no PATCH path is modelled yet).
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

-- CONNECTION entity hand-off for ADF.
-- Why this CTE exists:
-- 1) FE_ProcessEntities in ADF loops metadata entities.
-- 2) The child dispatch pipeline only sends rows returned by VW_D365_REQUESTS.
-- 3) Therefore, adding CONNECTION here is required before pipeline runs can
--    ever send connection payloads to Dataverse.
--
-- Design notes:
-- - Connections are emitted as POST only (create).
-- - HOLD rows are excluded; only actionable CREATE rows are emitted.
-- - We manufacture a stable string key for state tracking:
--       'CONNECTION:' || RE_RELATIONSHIP_ID
--   This plays the same role GOLDEN_RECORD_ID plays for Contact/Account.
CONNECTION_CTE AS (
    SELECT
        M.PIPELINE_ID,
        M.SOURCE_INSTANCE,
        M.ENTITY_ID,
        'CONNECTION:' || TO_VARCHAR(CN.RE_RELATIONSHIP_ID) AS GOLDEN_RECORD_ID,
        CAST(NULL AS VARCHAR) AS TARGET_GUID,
        'POST' AS HTTP_METHOD,
        M.API_BASE_URL || '/connections' AS REQUEST_URL,
        CN.PAYLOAD AS REQUEST_BODY,
        M.AUTH_METHOD,
        M.AUTH_CONFIG,
        MD5(TO_VARCHAR(CN.PAYLOAD)) AS PAYLOAD_MD5,
        CASE
            WHEN S.GOLDEN_RECORD_ID IS NULL THEN 1
            WHEN S.IS_RETRYABLE THEN 2
            ELSE 3
        END AS PRIORITY
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
    INNER JOIN INTEGRATION_DB.DYNAMICS.VW_D365_CONNECTION AS CN
        ON 1 = 1
    LEFT JOIN AUDIT_DB.MONITORING.D365_WRITEBACK_STATE AS S
        ON
            S.GOLDEN_RECORD_ID =
            'CONNECTION:' || TO_VARCHAR(CN.RE_RELATIONSHIP_ID)
            AND S.ENTITY_ID = 'CONNECTION'
    WHERE
        M.PIPELINE_ID = 'D365_WRITEBACK'
        AND M.ENTITY_ID = 'CONNECTION'
        AND M.ENABLED = TRUE
        AND CN.LOAD_ACTION = 'CREATE'
        AND CN.HOLD_REASON IS NULL
        AND (
            S.GOLDEN_RECORD_ID IS NULL
            OR S.IS_RETRYABLE
            OR S.LAST_PAYLOAD_MD5 IS DISTINCT FROM MD5(TO_VARCHAR(CN.PAYLOAD))
        )
),

-- TEST ONLY: Campaign 34 in NASDataMig with the temporary Operating Entity.
CAMPAIGN_TEST_PAYLOAD AS (
    SELECT
        RE_CAMPAIGN_ID,
        OBJECT_INSERT(
            PAYLOAD,
            'mha_operatingentityid@odata.bind',
            '/mha_operatingentities(04158d1c-afe2-f111-84ea-70a8a575b5fc)',
            TRUE
        ) AS PAYLOAD
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_CAMPAIGN
    WHERE RE_CAMPAIGN_ID = 34
      AND LOAD_ACTION = 'CREATE'
      AND HOLD_REASON IS NULL
),

CAMPAIGN_TEST_CTE AS (
    SELECT
        M.PIPELINE_ID,
        M.SOURCE_INSTANCE,
        M.ENTITY_ID,
        'CAMPAIGN:' || TO_VARCHAR(C.RE_CAMPAIGN_ID) AS GOLDEN_RECORD_ID,
        CAST(NULL AS VARCHAR) AS TARGET_GUID,
        'POST' AS HTTP_METHOD,
        M.API_BASE_URL || '/campaigns' AS REQUEST_URL,
        C.PAYLOAD AS REQUEST_BODY,
        M.AUTH_METHOD,
        M.AUTH_CONFIG,
        MD5(TO_VARCHAR(C.PAYLOAD)) AS PAYLOAD_MD5,
        1 AS PRIORITY
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
    CROSS JOIN CAMPAIGN_TEST_PAYLOAD AS C
    WHERE M.PIPELINE_ID = 'D365_WRITEBACK'
      AND M.SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
      AND M.ENTITY_ID = 'CAMPAIGN'
      AND M.ENABLED = TRUE
      AND M.API_BASE_URL = 'https://nasdatamig.crm11.dynamics.com/api/data/v9.2'
      AND NOT EXISTS (
          SELECT 1
          FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE AS S
          WHERE S.ENTITY_ID = 'CAMPAIGN'
            AND S.GOLDEN_RECORD_ID = 'CAMPAIGN:' || TO_VARCHAR(C.RE_CAMPAIGN_ID)
      )
),

-- TEST ONLY: Designation for RE Fund 717 / MAR00.
DESIGNATION_TEST_CTE AS (
    SELECT
        M.PIPELINE_ID,
        M.SOURCE_INSTANCE,
        M.ENTITY_ID,
        'DESIGNATION:' || TO_VARCHAR(D.RE_FUND_ID) AS GOLDEN_RECORD_ID,
        CAST(NULL AS VARCHAR) AS TARGET_GUID,
        'POST' AS HTTP_METHOD,
        M.API_BASE_URL || '/msnfp_designations' AS REQUEST_URL,
        D.PAYLOAD AS REQUEST_BODY,
        M.AUTH_METHOD,
        M.AUTH_CONFIG,
        MD5(TO_VARCHAR(D.PAYLOAD)) AS PAYLOAD_MD5,
        1 AS PRIORITY
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA M
    CROSS JOIN INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_DESIGNATION D
    WHERE M.PIPELINE_ID = 'D365_WRITEBACK'
      AND M.SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
      AND M.ENTITY_ID = 'DESIGNATION'
      AND M.ENABLED = TRUE
      AND M.API_BASE_URL = 'https://nasdatamig.crm11.dynamics.com/api/data/v9.2'
      AND D.RE_FUND_ID = 717
      AND D.RE_FUND_CODE = 'MAR00'
      AND D.LOAD_ACTION = 'CREATE'
      AND D.HOLD_REASON IS NULL
      AND NOT EXISTS (
          SELECT 1
          FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE S
          WHERE S.ENTITY_ID = 'DESIGNATION'
            AND S.GOLDEN_RECORD_ID = 'DESIGNATION:717'
      )
),

-- Membership stays on HOLD until its mapping and dispatch safeguards are ready.
MEMBERSHIP_CTE AS (
    SELECT
        M.PIPELINE_ID,
        M.SOURCE_INSTANCE,
        M.ENTITY_ID,
        D.GOLDEN_RECORD_ID,
        CAST(NULL AS VARCHAR) AS TARGET_GUID,
        'POST' AS HTTP_METHOD,
        M.API_BASE_URL || '/msnfp_memberships' AS REQUEST_URL,
        D.PAYLOAD AS REQUEST_BODY,
        M.AUTH_METHOD,
        M.AUTH_CONFIG,
        MD5(TO_VARCHAR(D.PAYLOAD)) AS PAYLOAD_MD5,
        1 AS PRIORITY
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA M
    CROSS JOIN INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_MEMBERSHIP D
    WHERE M.PIPELINE_ID = 'D365_WRITEBACK'
      AND M.SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
      AND M.ENTITY_ID = 'MEMBERSHIP'
      AND M.ENABLED = TRUE
      AND M.API_BASE_URL = 'https://nasdatamig.crm11.dynamics.com/api/data/v9.2'
      AND D.LOAD_ACTION = 'CREATE'
      AND D.HOLD_REASON IS NULL
      AND NOT EXISTS (
          SELECT 1
          FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE S
          WHERE S.ENTITY_ID = 'MEMBERSHIP'
            AND S.GOLDEN_RECORD_ID = D.GOLDEN_RECORD_ID
      )
),

-- Temporary DEV test: Appeal 98 only.
APPEAL_TEST_PAYLOAD AS (
    SELECT
        A.RE_APPEAL_ID,
        OBJECT_INSERT(
            A.PAYLOAD,
            'msnfp_appealid',
            '215e59f7-c636-4b82-bd0e-4c3ee12dd8e3',
            TRUE
        ) AS TEST_PAYLOAD
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_APPEAL A
    WHERE A.RE_APPEAL_ID = 98
      AND A.RE_CAMPAIGN_ID IS NULL
      AND A.D365_ID IS NULL
      AND A.MSNFP_IDENTIFIER = 'Membership Subscription'
      AND A.LOAD_ACTION = 'HOLD'
      AND A.HOLD_REASON =
          'CAMPAIGN_NOT_PROVIDED,EXISTING_RECORD_CHECK_PENDING,BUSINESS_MAPPINGS_PENDING,DISPATCH_SAFETY_PENDING'
),

APPEAL_TEST_CTE AS (
    SELECT
        M.PIPELINE_ID,
        M.SOURCE_INSTANCE,
        M.ENTITY_ID,
        'APPEAL:' || TO_VARCHAR(A.RE_APPEAL_ID) AS GOLDEN_RECORD_ID,
        CAST(NULL AS VARCHAR) AS TARGET_GUID,
        'POST' AS HTTP_METHOD,
        M.API_BASE_URL || '/msnfp_appeals' AS REQUEST_URL,
        A.TEST_PAYLOAD AS REQUEST_BODY,
        M.AUTH_METHOD,
        M.AUTH_CONFIG,
        MD5(TO_VARCHAR(A.TEST_PAYLOAD)) AS PAYLOAD_MD5,
        1 AS PRIORITY
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA M
    CROSS JOIN APPEAL_TEST_PAYLOAD A
    WHERE M.PIPELINE_ID = 'D365_WRITEBACK'
      AND M.SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
      AND M.ENTITY_ID = 'APPEAL'
      AND M.ENABLED = TRUE
      AND M.API_BASE_URL = 'https://nasdatamig.crm11.dynamics.com/api/data/v9.2'
      AND NOT EXISTS (
          SELECT 1
          FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE S
          WHERE S.ENTITY_ID = 'APPEAL'
            AND S.GOLDEN_RECORD_ID = 'APPEAL:' || TO_VARCHAR(A.RE_APPEAL_ID)
      )
      AND NOT EXISTS (
          SELECT 1
          FROM MDM_DB.GOLD.XREF X
          WHERE X.GOLDEN_RECORD_ID = 'APPEAL:' || TO_VARCHAR(A.RE_APPEAL_ID)
            AND X.SOURCE_SYSTEM = 'DYNAMICS'
      )
),

COMBINED_CTE AS (
    SELECT * FROM CONTACT_CTE
    UNION ALL
    SELECT * FROM ACCOUNT_CTE
    UNION ALL
    SELECT * FROM CONNECTION_CTE
    UNION ALL
    SELECT * FROM CAMPAIGN_TEST_CTE
    UNION ALL
    SELECT * FROM DESIGNATION_TEST_CTE
    UNION ALL
    SELECT * FROM MEMBERSHIP_CTE
    UNION ALL
    SELECT * FROM APPEAL_TEST_CTE
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