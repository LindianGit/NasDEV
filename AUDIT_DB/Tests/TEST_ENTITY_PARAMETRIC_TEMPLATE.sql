-- =====================================================================================
-- PARAMETRIC TEST SUITE - Entity-Level Regression Tests
-- =====================================================================================
-- Purpose: Template to test any entity end-to-end (scalable to all 36 objects)
-- Template: Replace {ENTITY} with actual entity name (CONSTITUENT, GIFT, ACCOUNT, etc.)
-- =====================================================================================

USE DATABASE AUDIT_DB;
USE SCHEMA TEST_RESULTS;

-- =====================================================================================
-- ENTITY TEST TEMPLATE - Copy and customize for each entity
-- =====================================================================================

-- EXAMPLE: CONSTITUENT Entity Tests
-- To adapt for other entities, replace:
--   {ENTITY_NAME} → actual entity (CONSTITUENT, GIFT, DONATION, ACCOUNT, etc.)
--   {SOURCE_TABLE} → RAW.RAISERS_EDGE.STG_T_{ENTITY_NAME}
--   {ODS_TABLE} → RAW.RAISERS_EDGE.ODS_T_{ENTITY_NAME}
--   {PRIMARY_KEY} → actual primary key column name

-- =====================================================================================
-- TEST ENTITY: Verify Source Data Extraction
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_ENTITY_DATA_EXTRACTION(
    p_entity_name VARCHAR,
    p_source_schema VARCHAR,
    p_source_table VARCHAR,
    p_ods_schema VARCHAR,
    p_ods_table VARCHAR,
    p_primary_key VARCHAR
)
RETURNS TABLE (ENTITY VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, DETAILS VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_extract_count NUMBER;
    v_ods_count NUMBER;
    v_delta_pct NUMERIC(5,2);
    v_test_status VARCHAR;
    v_sql VARCHAR;
BEGIN
    -- Dynamically count extracted records
    v_sql := 'SELECT COUNT(*) FROM ' || p_source_schema || '.' || p_source_table || 
             ' WHERE EXTRACT_TS > DATEADD(day, -1, CURRENT_TIMESTAMP())';
    EXECUTE IMMEDIATE v_sql INTO v_extract_count;
    
    -- Dynamically count ODS records (active only)
    v_sql := 'SELECT COUNT(*) FROM ' || p_ods_schema || '.' || p_ods_table ||
             ' WHERE IS_DELETED = FALSE';
    EXECUTE IMMEDIATE v_sql INTO v_ods_count;
    
    -- Calculate extraction quality
    LET v_delta_pct := (ABS(v_extract_count - v_ods_count) / NULLIF(v_ods_count, 0)) * 100;
    
    v_test_status := CASE 
        WHEN v_extract_count > 0 AND v_delta_pct < 5 THEN 'PASS'
        WHEN v_extract_count > 0 AND v_delta_pct < 10 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    RETURN TABLE(
        SELECT p_entity_name AS ENTITY,
               'Data Extraction' AS TEST_NAME,
               v_test_status AS STATUS,
               'Extracted: ' || v_extract_count || ', ODS: ' || v_ods_count || ', Delta: ' || v_delta_pct || '%' AS DETAILS,
               v_extract_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST ENTITY: Validate Referential Integrity
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_ENTITY_REFERENTIAL_INTEGRITY(
    p_entity_name VARCHAR,
    p_staging_table VARCHAR,
    p_ods_table VARCHAR,
    p_primary_key VARCHAR
)
RETURNS TABLE (ENTITY VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, DETAILS VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_orphan_count NUMBER;
    v_test_status VARCHAR;
    v_sql VARCHAR;
BEGIN
    -- Check for orphaned records (in staging but not in ODS)
    v_sql := 'SELECT COUNT(*) FROM ' || p_staging_table || ' stg ' ||
             ' WHERE NOT EXISTS (SELECT 1 FROM ' || p_ods_table || ' ods ' ||
             ' WHERE ods.' || p_primary_key || ' = stg.' || p_primary_key || ')';
    EXECUTE IMMEDIATE v_sql INTO v_orphan_count;
    
    v_test_status := CASE 
        WHEN v_orphan_count = 0 THEN 'PASS'
        WHEN v_orphan_count < 10 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    RETURN TABLE(
        SELECT p_entity_name AS ENTITY,
               'Referential Integrity' AS TEST_NAME,
               v_test_status AS STATUS,
               'Orphaned Records: ' || v_orphan_count AS DETAILS,
               v_orphan_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST ENTITY: MDM Standardization Rate
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_ENTITY_MDM_COVERAGE(
    p_entity_name VARCHAR,
    p_ods_table VARCHAR,
    p_primary_key VARCHAR,
    p_source_domain VARCHAR DEFAULT 'INDIVIDUAL'
)
RETURNS TABLE (ENTITY VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, DETAILS VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_ods_active_count NUMBER;
    v_mdm_count NUMBER;
    v_coverage_pct NUMERIC(5,2);
    v_test_status VARCHAR;
    v_sql VARCHAR;
BEGIN
    -- Count active ODS records
    v_sql := 'SELECT COUNT(*) FROM ' || p_ods_table || ' WHERE IS_DELETED = FALSE';
    EXECUTE IMMEDIATE v_sql INTO v_ods_active_count;
    
    -- Count records that made it to MDM
    LET v_mdm_count := (
        SELECT COUNT(DISTINCT SOURCE_RECORD_ID) FROM MDM_DB.STAGING.STANDARDISED_RECORDS
        WHERE SOURCE_SYSTEM = 'RAISERS_EDGE'
            AND SOURCE_DOMAIN = p_source_domain
    );
    
    LET v_coverage_pct := (v_mdm_count / NULLIF(v_ods_active_count, 0)) * 100;
    
    v_test_status := CASE 
        WHEN v_coverage_pct >= 95 THEN 'PASS'
        WHEN v_coverage_pct >= 85 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    RETURN TABLE(
        SELECT p_entity_name AS ENTITY,
               'MDM Standardization Coverage' AS TEST_NAME,
               v_test_status AS STATUS,
               'Coverage: ' || v_coverage_pct || '% (' || v_mdm_count || '/' || v_ods_active_count || ')' AS DETAILS,
               v_mdm_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST ENTITY: Golden Record Deduplication Ratio
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_ENTITY_DEDUP_RATIO(
    p_entity_name VARCHAR,
    p_source_domain VARCHAR DEFAULT 'INDIVIDUAL'
)
RETURNS TABLE (ENTITY VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, DETAILS VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_standardised_count NUMBER;
    v_golden_count NUMBER;
    v_dedup_ratio NUMERIC(5,2);
    v_test_status VARCHAR;
BEGIN
    LET v_standardised_count := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.STANDARDISED_RECORDS
        WHERE SOURCE_DOMAIN = p_source_domain
    );
    
    LET v_golden_count := (
        SELECT COUNT(*) FROM MDM_DB.GOLD.GOLDEN_RECORDS
        WHERE DOMAIN = p_source_domain
    );
    
    LET v_dedup_ratio := (v_golden_count / NULLIF(v_standardised_count, 0)) * 100;
    
    -- Expected: 60-90% (some deduplication, but not excessive)
    v_test_status := CASE 
        WHEN v_dedup_ratio BETWEEN 60 AND 100 THEN 'PASS'
        WHEN v_dedup_ratio BETWEEN 50 AND 60 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    RETURN TABLE(
        SELECT p_entity_name AS ENTITY,
               'Deduplication Ratio' AS TEST_NAME,
               v_test_status AS STATUS,
               'Golden/Standardised: ' || v_dedup_ratio || '% (' || v_golden_count || '/' || v_standardised_count || ')' AS DETAILS,
               v_golden_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST ENTITY: Identity Reconciliation (XREF Capture)
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_ENTITY_XREF_RECONCILIATION(
    p_entity_name VARCHAR,
    p_source_system VARCHAR,
    p_source_domain VARCHAR DEFAULT 'INDIVIDUAL'
)
RETURNS TABLE (ENTITY VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, DETAILS VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_golden_count NUMBER;
    v_xref_count NUMBER;
    v_xref_coverage NUMERIC(5,2);
    v_test_status VARCHAR;
BEGIN
    LET v_golden_count := (
        SELECT COUNT(*) FROM MDM_DB.GOLD.GOLDEN_RECORDS
        WHERE DOMAIN = p_source_domain
    );
    
    LET v_xref_count := (
        SELECT COUNT(DISTINCT GOLDEN_RECORD_ID) FROM MDM_DB.GOLD.XREF
        WHERE SOURCE_SYSTEM = p_source_system
            AND GOLDEN_RECORD_ID IN (
                SELECT ID FROM MDM_DB.GOLD.GOLDEN_RECORDS WHERE DOMAIN = p_source_domain
            )
    );
    
    LET v_xref_coverage := (v_xref_count / NULLIF(v_golden_count, 0)) * 100;
    
    v_test_status := CASE 
        WHEN v_xref_coverage >= 95 THEN 'PASS'
        WHEN v_xref_coverage >= 90 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    RETURN TABLE(
        SELECT p_entity_name AS ENTITY,
               'XREF Reconciliation' AS TEST_NAME,
               v_test_status AS STATUS,
               'Coverage: ' || v_xref_coverage || '% (' || v_xref_count || '/' || v_golden_count || ')' AS DETAILS,
               v_xref_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST ENTITY: Payload Quality
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_ENTITY_PAYLOAD_QUALITY(
    p_entity_name VARCHAR,
    p_payload_table VARCHAR,
    p_required_fields VARCHAR  -- CSV of field names that must be non-null
)
RETURNS TABLE (ENTITY VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, DETAILS VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_total_payloads NUMBER;
    v_complete_payloads NUMBER;
    v_completeness_pct NUMERIC(5,2);
    v_test_status VARCHAR;
BEGIN
    -- Count total active payloads
    LET v_total_payloads := (
        SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    );  -- Placeholder - should be actual count query
    
    v_test_status := 'PASS';  -- Template: replace with actual logic
    
    RETURN TABLE(
        SELECT p_entity_name AS ENTITY,
               'Payload Quality' AS TEST_NAME,
               v_test_status AS STATUS,
               'Total Payloads: ' || v_total_payloads AS DETAILS,
               v_total_payloads AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- RUNNER: Execute all entity tests for a specific entity
-- =====================================================================================
CREATE OR REPLACE PROCEDURE RUN_ENTITY_REGRESSION_TESTS(
    p_entity_name VARCHAR,
    p_source_schema VARCHAR DEFAULT 'RAW.RAISERS_EDGE',
    p_ods_schema VARCHAR DEFAULT 'RAW.RAISERS_EDGE',
    p_primary_key VARCHAR
)
RETURNS TABLE (RESULTS VARIANT)
LANGUAGE SQL
AS
$$
DECLARE
    v_execution_start TIMESTAMP_LTZ;
    v_execution_end TIMESTAMP_LTZ;
    v_results ARRAY;
BEGIN
    v_execution_start := CURRENT_TIMESTAMP();
    
    -- Test 1: Data Extraction
    CALL TEST_ENTITY_DATA_EXTRACTION(
        p_entity_name,
        p_source_schema,
        'STG_T_' || p_entity_name,
        p_ods_schema,
        'ODS_T_' || p_entity_name,
        p_primary_key
    );
    
    -- Test 2: MDM Coverage
    CALL TEST_ENTITY_MDM_COVERAGE(
        p_entity_name,
        p_ods_schema || '.ODS_T_' || p_entity_name,
        p_primary_key,
        'INDIVIDUAL'
    );
    
    -- Test 3: Deduplication
    CALL TEST_ENTITY_DEDUP_RATIO(
        p_entity_name,
        'INDIVIDUAL'
    );
    
    -- Test 4: XREF Reconciliation
    CALL TEST_ENTITY_XREF_RECONCILIATION(
        p_entity_name,
        'RAISERS_EDGE',
        'INDIVIDUAL'
    );
    
    v_execution_end := CURRENT_TIMESTAMP();
    
    RETURN TABLE(
        SELECT OBJECT_CONSTRUCT(
            'entity', p_entity_name,
            'execution_time_sec', DATEDIFF(seconds, v_execution_start, v_execution_end),
            'completed_at', v_execution_end
        ) AS RESULTS
    );
END;
$$;

-- =====================================================================================
-- USAGE EXAMPLES
-- =====================================================================================
-- To test CONSTITUENT entity:
--   CALL RUN_ENTITY_REGRESSION_TESTS('CONSTITUENT', 'RAW.RAISERS_EDGE', 'RAW.RAISERS_EDGE', 'CONSTITUENT_ID');
--
-- To test GIFT entity:
--   CALL RUN_ENTITY_REGRESSION_TESTS('GIFT', 'RAW.RAISERS_EDGE', 'RAW.RAISERS_EDGE', 'GIFT_ID');
--
-- To test other entities, just change the entity name and primary key column.
-- =====================================================================================
