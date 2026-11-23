-- Preparation only. Both rows are inserted disabled; existing rows are unchanged.
DECLARE
    V_TEMPLATE_COUNT NUMBER;
    V_CONFLICTS NUMBER;
    INVALID_TEMPLATE EXCEPTION (-20001, 'Expected exactly one DEV Campaign metadata template.');
    INVALID_GIFT_METADATA EXCEPTION (-20002, 'Gift metadata is duplicated or points to a different API URL.');
BEGIN
    SELECT COUNT(*) INTO :V_TEMPLATE_COUNT
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA
    WHERE PIPELINE_ID = 'D365_WRITEBACK'
      AND SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
      AND ENTITY_ID = 'CAMPAIGN'
      AND API_BASE_URL = 'https://nasdatamig.crm11.dynamics.com/api/data/v9.2';

    IF (V_TEMPLATE_COUNT <> 1) THEN
        RAISE INVALID_TEMPLATE;
    END IF;

    SELECT COUNT(*) INTO :V_CONFLICTS
    FROM (
        SELECT ENTITY_ID
        FROM AUDIT_DB.CONFIG.PIPELINE_METADATA
        WHERE PIPELINE_ID = 'D365_GIFT_WRITEBACK'
          AND SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
          AND ENTITY_ID IN ('TRANSACTION', 'DESIGNATEDCREDIT')
        GROUP BY ENTITY_ID
        HAVING COUNT(*) > 1
            OR COUNT_IF(
                API_BASE_URL IS DISTINCT FROM
                    'https://nasdatamig.crm11.dynamics.com/api/data/v9.2'
            ) > 0
    );

    IF (V_CONFLICTS > 0) THEN
        RAISE INVALID_GIFT_METADATA;
    END IF;

    INSERT INTO AUDIT_DB.CONFIG.PIPELINE_METADATA (
        PIPELINE_ID, SOURCE_INSTANCE, ENTITY_ID,
        SOURCE_TYPE, LOAD_TYPE, API_BASE_URL, AUTH_METHOD, AUTH_CONFIG,
        TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE,
        EXECUTION_ORDER, ENABLED, NOTES
    )
    SELECT
        'D365_GIFT_WRITEBACK',
        M.SOURCE_INSTANCE,
        E.ENTITY_ID,
        'VIEW',
        'FULL',
        M.API_BASE_URL,
        M.AUTH_METHOD,
        M.AUTH_CONFIG,
        'INTEGRATION_DB',
        'DYNAMICS',
        E.ENTITY_ID,
        E.EXECUTION_ORDER,
        FALSE,
        'Disabled pending Gift mapping, identity reconciliation and dispatch validation.'
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
    CROSS JOIN (
        SELECT COLUMN1 AS ENTITY_ID, COLUMN2 AS EXECUTION_ORDER
        FROM VALUES ('TRANSACTION', 10), ('DESIGNATEDCREDIT', 20)
    ) AS E
    WHERE M.PIPELINE_ID = 'D365_WRITEBACK'
      AND M.SOURCE_INSTANCE = 'SNOWFLAKE_DEV'
      AND M.ENTITY_ID = 'CAMPAIGN'
      AND M.API_BASE_URL = 'https://nasdatamig.crm11.dynamics.com/api/data/v9.2'
      AND NOT EXISTS (
          SELECT 1
          FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS EXISTING
          WHERE EXISTING.PIPELINE_ID = 'D365_GIFT_WRITEBACK'
            AND EXISTING.SOURCE_INSTANCE = M.SOURCE_INSTANCE
            AND EXISTING.ENTITY_ID = E.ENTITY_ID
      );

    RETURN 'Gift metadata prepared. Existing rows were not changed.';
END;
