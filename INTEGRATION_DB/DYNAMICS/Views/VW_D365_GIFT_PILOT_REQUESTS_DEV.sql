CREATE OR REPLACE VIEW INTEGRATION_DB.DYNAMICS.VW_D365_GIFT_PILOT_REQUESTS_DEV AS

-- One DEV pilot only. Run the Transaction and line separately and inspect
-- each result before proceeding; failed or uncertain creates need reconciliation.
WITH GIFT_PILOT_PAYLOAD AS (
    SELECT
        'TRANSACTION' AS ENTITY_ID,
        'TRANSACTION:50628' AS GOLDEN_RECORD_ID,
        'msnfp_transactions' AS ENTITY_SET,
        OBJECT_CONSTRUCT(
            'mha_sourceid', '50628',
            'msnfp_amount', C.GIFT_AMOUNT,
            'msnfp_bookdate', T.DRAFT_PAYLOAD:"msnfp_bookdate",
            'msnfp_depositdate', T.DRAFT_PAYLOAD:"msnfp_depositdate",
            'msnfp_posteddate', T.DRAFT_PAYLOAD:"msnfp_posteddate",
            'msnfp_CustomerId_' || C.DONOR_TYPE || '@odata.bind',
                '/' || C.DONOR_TYPE || 's(' || C.DONOR_D365_ID || ')',
            'msnfp_OriginatingCampaignId@odata.bind',
                C.DRAFT_ATTRIBUTION:"msnfp_OriginatingCampaignId@odata.bind",
            'msnfp_AppealId@odata.bind',
                C.DRAFT_ATTRIBUTION:"msnfp_AppealId@odata.bind",
            'transactioncurrencyid@odata.bind',
                '/transactioncurrencies(ef715fd1-e6fc-ec11-82e5-0022481b7c7b)',
            'mha_giftaidapplicable', FALSE,
            'mha_giftaideligible', FALSE
        ) AS REQUEST_BODY
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_GIFT_PILOT_CANDIDATES_DEV AS C
    INNER JOIN INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_TRANSACTION AS T
        ON C.RE_GIFT_ID = T.RE_GIFT_ID
    WHERE C.RE_GIFT_ID = 50628
      AND C.RE_SPLIT_ID = 213112
      AND C.GIFT_AMOUNT = 700
      AND C.SPLIT_AMOUNT = 700
      AND C.DONOR_TYPE = 'account'
      AND LOWER(C.DONOR_D365_ID) = '84d957c2-f7e0-f111-84ea-70a8a575b5fc'
      AND LOWER(C.DESIGNATION_D365_ID) = '82442015-f407-f111-8406-7ced8d9be7ce'
      AND LOWER(C.CAMPAIGN_D365_ID) = 'b34ca41f-d787-4e31-adaf-1fd960180ed5'
      AND LOWER(C.APPEAL_D365_ID) = '686fa601-b982-4b5c-85ba-75723f35ad4b'
      AND C.PACKAGE_D365_ID IS NULL
      AND TO_VARCHAR(T.DRAFT_PAYLOAD:"msnfp_bookdate") = '1999-06-01'
      AND TO_VARCHAR(T.DRAFT_PAYLOAD:"msnfp_posteddate") = '1999-06-01'

    UNION ALL

    SELECT
        'DESIGNATEDCREDIT',
        'DESIGNATEDCREDIT:213112',
        'msnfp_designatedcredits',
        OBJECT_CONSTRUCT(
            'msnfp_dataentryreference', '213112',
            'msnfp_amount', L.RE_SPLIT_AMOUNT,
            'msnfp_transactionid@odata.bind',
                '/msnfp_transactions(' || I.D365_GUID || ')',
            'msnfp_designatiedcredit_designationId@odata.bind',
                '/msnfp_designations(' || L.DESIGNATION_D365_ID || ')',
            'transactioncurrencyid@odata.bind',
                '/transactioncurrencies(ef715fd1-e6fc-ec11-82e5-0022481b7c7b)',
            'mha_giftaidapplicable', FALSE,
            'mha_giftaideligible', FALSE
        )
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_DESIGNATEDCREDIT AS L
    INNER JOIN MDM_DB.GOLD.GIFT_D365_IDENTITY AS I
        ON I.ENTITY_ID = 'TRANSACTION'
       AND I.SOURCE_RECORD_ID = '50628'
       AND I.SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
       AND LOWER(I.D365_GUID) = LOWER(L.TRANSACTION_D365_ID)
    WHERE L.RE_GIFT_ID = 50628
      AND L.RE_SPLIT_ID = 213112
      AND L.PARENT_ROWS = 1
      AND L.PARENT_TARGET = 'TRANSACTION'
      AND L.RE_SPLIT_AMOUNT = 700
      AND LOWER(L.DESIGNATION_D365_ID) = '82442015-f407-f111-8406-7ced8d9be7ce'
)

SELECT
    'D365_GIFT_PILOT' AS PIPELINE_ID,
    M.SOURCE_INSTANCE,
    P.ENTITY_ID,
    P.GOLDEN_RECORD_ID,
    CAST(NULL AS VARCHAR) AS TARGET_GUID,
    'POST' AS HTTP_METHOD,
    M.API_BASE_URL || '/' || P.ENTITY_SET AS REQUEST_URL,
    P.REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG,
    MD5(TO_VARCHAR(P.REQUEST_BODY)) AS PAYLOAD_MD5
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
CROSS JOIN GIFT_PILOT_PAYLOAD AS P
WHERE M.PIPELINE_ID = 'D365_WRITEBACK'
  AND M.SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
  AND M.ENTITY_ID = 'CAMPAIGN'
  AND M.API_BASE_URL = 'https://nasdatamig.crm11.dynamics.com/api/data/v9.2'
  AND NOT EXISTS (
      SELECT 1 FROM AUDIT_DB.MONITORING.D365_WRITEBACK_STATE AS S
      WHERE S.ENTITY_ID = P.ENTITY_ID
        AND S.GOLDEN_RECORD_ID = P.GOLDEN_RECORD_ID
  )
  AND NOT EXISTS (
      SELECT 1 FROM MDM_DB.GOLD.XREF AS X
      WHERE X.SOURCE_SYSTEM = 'DYNAMICS'
        AND X.GOLDEN_RECORD_ID = P.GOLDEN_RECORD_ID
  )
  AND NOT EXISTS (
      SELECT 1 FROM MDM_DB.GOLD.GIFT_D365_IDENTITY AS I
      WHERE I.ENTITY_ID = P.ENTITY_ID
        AND I.SOURCE_RECORD_ID = SPLIT_PART(P.GOLDEN_RECORD_ID, ':', 2)
  )
QUALIFY COUNT(*) OVER (PARTITION BY P.ENTITY_ID, P.GOLDEN_RECORD_ID) = 1;
