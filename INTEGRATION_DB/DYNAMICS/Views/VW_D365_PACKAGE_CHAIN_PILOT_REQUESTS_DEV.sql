CREATE OR REPLACE VIEW INTEGRATION_DB.DYNAMICS.VW_D365_PACKAGE_CHAIN_PILOT_REQUESTS_DEV AS

-- One DEV chain only. Run its entities sequentially and verify each parent
-- in Dynamics before dispatching its child. Reconcile uncertain POSTs.
-- The preview's dispatch flag is informational; this view applies its own guards.
-- The disabled Campaign metadata row is used only as a DEV connection template.
WITH PILOT AS (
    SELECT *
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_PACKAGE_PILOT_PREVIEW_DEV
    WHERE JOIN_ROWS = 1
      AND RE_PACKAGE_ID = 71
      AND RE_APPEAL_ID = 1359
      AND RE_CAMPAIGN_ID = 6
      AND RE_CAMPAIGN_CODE = 'EVENTS'
      AND DRAFT_CAMPAIGN_FIELDS:"name"::VARCHAR = 'Events Fundraising'
      AND DRAFT_CAMPAIGN_FIELDS:"codename"::VARCHAR = 'EVENTS'
      AND DRAFT_APPEAL_FIELDS:"msnfp_identifier"::VARCHAR = 'Stars Shine for Autism 09'
      AND DRAFT_PACKAGE_FIELDS:"msnfp_identifier"::VARCHAR = 'Stars Shine 2009 Donations'
      AND DRAFT_PACKAGE_FIELDS:"mhnas_packagecode"::VARCHAR = 'Stars Shine Donation'
),
PARENT_XREF AS (
    SELECT
        GOLDEN_RECORD_ID,
        COUNT(*) AS XREF_ROWS,
        MIN(LOWER(NULLIF(TRIM(SOURCE_RECORD_ID), ''))) AS D365_ID
    FROM MDM_DB.GOLD.XREF
    WHERE SOURCE_SYSTEM = 'DYNAMICS'
      AND GOLDEN_RECORD_ID IN ('CAMPAIGN:6', 'APPEAL:1359')
    GROUP BY GOLDEN_RECORD_ID
),
REQUESTS AS (
    SELECT
        'CAMPAIGN' AS ENTITY_ID,
        'CAMPAIGN:6' AS GOLDEN_RECORD_ID,
        '/campaigns' AS ENTITY_PATH,
        OBJECT_INSERT(
            OBJECT_DELETE(P.DRAFT_CAMPAIGN_FIELDS, 'expectedrevenue'),
            'mha_operatingentityid@odata.bind',
            '/mha_operatingentities(04158d1c-afe2-f111-84ea-70a8a575b5fc)',
            TRUE
        ) AS REQUEST_BODY
    FROM PILOT P
    WHERE NOT EXISTS (
        SELECT 1 FROM RAW.DYNAMICS.VW_ODS_CAMPAIGNS D
        WHERE TRIM(D.MHA_SOURCEID) = '6'
           OR UPPER(TRIM(D.CODENAME)) = 'EVENTS'
    )

    UNION ALL

    SELECT
        'APPEAL',
        'APPEAL:1359',
        '/msnfp_appeals',
        OBJECT_INSERT(
            P.DRAFT_APPEAL_FIELDS,
            'msnfp_campaignid@odata.bind',
            '/campaigns(' || C.D365_ID || ')',
            TRUE
        )
    FROM PILOT P
    JOIN PARENT_XREF C
        ON C.GOLDEN_RECORD_ID = 'CAMPAIGN:6'
       AND C.XREF_ROWS = 1
       AND REGEXP_LIKE(C.D365_ID, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    WHERE NOT EXISTS (
        SELECT 1 FROM RAW.DYNAMICS.VW_ODS_MSNFP_APPEALS D
        WHERE TRIM(D.MHA_SOURCEID) = '1359'
    )

    UNION ALL

    SELECT
        'PACKAGE',
        'PACKAGE:71',
        '/msnfp_packages',
        OBJECT_INSERT(
            OBJECT_INSERT(
                OBJECT_INSERT(
                    P.DRAFT_PACKAGE_FIELDS,
                    'mha_source',
                    'Raisers Edge',
                    TRUE
                ),
                'msnfp_AppealId@odata.bind',
                '/msnfp_appeals(' || A.D365_ID || ')',
                TRUE
            ),
            'msnfp_CampaignId@odata.bind',
            '/campaigns(' || C.D365_ID || ')',
            TRUE
        )
    FROM PILOT P
    JOIN PARENT_XREF C
        ON C.GOLDEN_RECORD_ID = 'CAMPAIGN:6'
       AND C.XREF_ROWS = 1
       AND REGEXP_LIKE(C.D365_ID, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    JOIN PARENT_XREF A
        ON A.GOLDEN_RECORD_ID = 'APPEAL:1359'
       AND A.XREF_ROWS = 1
       AND REGEXP_LIKE(A.D365_ID, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    WHERE NOT EXISTS (
        SELECT 1 FROM RAW.DYNAMICS.VW_ODS_MSNFP_PACKAGES D
        WHERE TRIM(D.MHA_SOURCEID) = '71'
    )
)
SELECT
    'D365_PACKAGE_CHAIN_PILOT' AS PIPELINE_ID,
    M.SOURCE_INSTANCE,
    R.ENTITY_ID,
    R.GOLDEN_RECORD_ID,
    CAST(NULL AS VARCHAR) AS TARGET_GUID,
    'POST' AS HTTP_METHOD,
    M.API_BASE_URL || R.ENTITY_PATH AS REQUEST_URL,
    R.REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG,
    MD5(TO_VARCHAR(R.REQUEST_BODY)) AS PAYLOAD_MD5
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA M
CROSS JOIN REQUESTS R
WHERE M.PIPELINE_ID = 'D365_WRITEBACK'
  AND M.SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
  AND M.ENTITY_ID = 'CAMPAIGN'
  AND M.API_BASE_URL = 'https://nasdatamig.crm11.dynamics.com/api/data/v9.2'
  AND NOT EXISTS (
      SELECT 1 FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE S
      WHERE S.ENTITY_ID = R.ENTITY_ID
        AND S.GOLDEN_RECORD_ID = R.GOLDEN_RECORD_ID
  )
  AND NOT EXISTS (
      SELECT 1 FROM MDM_DB.GOLD.XREF X
      WHERE X.SOURCE_SYSTEM = 'DYNAMICS'
        AND X.GOLDEN_RECORD_ID = R.GOLDEN_RECORD_ID
  )
QUALIFY COUNT(*) OVER (PARTITION BY R.GOLDEN_RECORD_ID) = 1;
