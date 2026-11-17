-- ACC preparation for Connection and Campaign writeback.
-- Replace all three values with the confirmed ACC settings before running.
-- The CONTACT row must already exist for this source instance and point to ACC.
-- Existing CONNECTION and CAMPAIGN rows are never changed; new rows are disabled.
SET ACC_SNOWFLAKE_ACCOUNT = 'REPLACE_WITH_ACC_ACCOUNT';
SET ACC_SOURCE_INSTANCE = 'REPLACE_WITH_ACC_SOURCE_INSTANCE';
SET ACC_API_BASE_URL = 'REPLACE_WITH_ACC_DATAVERSE_API_BASE_URL';

EXECUTE IMMEDIATE $$
DECLARE
    actual_account VARCHAR;
    template_count NUMBER;
    conflicting_count NUMBER;
    wrong_account EXCEPTION (-20001, 'Current Snowflake account does not match ACC_SNOWFLAKE_ACCOUNT.');
    invalid_template EXCEPTION (-20002, 'Expected exactly one ACC CONTACT metadata row with the specified API URL.');
    conflicting_metadata EXCEPTION (-20003, 'An existing CONNECTION or CAMPAIGN metadata row has a different API URL or is duplicated.');
BEGIN
    SELECT CURRENT_ACCOUNT() INTO :actual_account;
    IF (actual_account <> $ACC_SNOWFLAKE_ACCOUNT) THEN
        RAISE wrong_account;
    END IF;

    SELECT COUNT(*) INTO :template_count
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA
    WHERE PIPELINE_ID = 'D365_WRITEBACK'
      AND SOURCE_INSTANCE = $ACC_SOURCE_INSTANCE
      AND ENTITY_ID = 'CONTACT'
      AND API_BASE_URL = $ACC_API_BASE_URL;
    IF (template_count <> 1) THEN
        RAISE invalid_template;
    END IF;

    SELECT COUNT(*) INTO :conflicting_count
    FROM (
        SELECT ENTITY_ID
        FROM AUDIT_DB.CONFIG.PIPELINE_METADATA
        WHERE PIPELINE_ID = 'D365_WRITEBACK'
          AND SOURCE_INSTANCE = $ACC_SOURCE_INSTANCE
          AND ENTITY_ID IN ('CONNECTION', 'CAMPAIGN')
        GROUP BY ENTITY_ID
        HAVING COUNT(*) > 1
            OR COUNT_IF(API_BASE_URL IS DISTINCT FROM $ACC_API_BASE_URL) > 0
    );
    IF (conflicting_count > 0) THEN
        RAISE conflicting_metadata;
    END IF;

    INSERT INTO AUDIT_DB.CONFIG.PIPELINE_METADATA (
        PIPELINE_ID, SOURCE_INSTANCE, ENTITY_ID,
        SOURCE_TYPE, LOAD_TYPE, API_BASE_URL, AUTH_METHOD, AUTH_CONFIG,
        TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE,
        EXECUTION_ORDER, ENABLED, NOTES
    )
    SELECT
        M.PIPELINE_ID, M.SOURCE_INSTANCE, E.ENTITY_ID,
        'VIEW', 'FULL', M.API_BASE_URL, M.AUTH_METHOD, M.AUTH_CONFIG,
        'INTEGRATION_DB', 'DYNAMICS', E.ENTITY_ID,
        E.EXECUTION_ORDER, FALSE, 'ACC preparation: disabled until approved'
    FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
    CROSS JOIN (
        SELECT COLUMN1 AS ENTITY_ID, COLUMN2 AS EXECUTION_ORDER
        FROM VALUES ('CONNECTION', 30), ('CAMPAIGN', 40)
    ) AS E
    WHERE M.PIPELINE_ID = 'D365_WRITEBACK'
      AND M.SOURCE_INSTANCE = $ACC_SOURCE_INSTANCE
      AND M.ENTITY_ID = 'CONTACT'
      AND M.API_BASE_URL = $ACC_API_BASE_URL
      AND NOT EXISTS (
          SELECT 1
          FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS EXISTING
          WHERE EXISTING.PIPELINE_ID = M.PIPELINE_ID
            AND EXISTING.SOURCE_INSTANCE = M.SOURCE_INSTANCE
            AND EXISTING.ENTITY_ID = E.ENTITY_ID
      );

    RETURN 'Metadata preparation complete. Review the rows below; existing rows were not changed.';
END;
$$;

-- Review ENABLED and the ACC URL. This script does not disable existing rows.
SELECT SOURCE_INSTANCE, ENTITY_ID, ENABLED, API_BASE_URL, AUTH_METHOD, EXECUTION_ORDER
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA
WHERE PIPELINE_ID = 'D365_WRITEBACK'
  AND SOURCE_INSTANCE = $ACC_SOURCE_INSTANCE
  AND ENTITY_ID IN ('CONTACT', 'CONNECTION', 'CAMPAIGN')
ORDER BY ENTITY_ID;

-- Do not enable Campaign until the DEV-only Campaign test code and Operating
-- Entity GUID are replaced with ACC-approved configuration and ADF is ready.
-- Confirm ACC ADF authentication/resource settings and paused triggers before
-- enabling either entity. XREF procedure support for Campaign is unverified.
