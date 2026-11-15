-- =====================================================================================
-- REGRESSION TEST SUITE: Dynamics Migration End-to-End
-- =====================================================================================
-- Purpose: Validate the complete Raisers Edge → Snowflake → MDM → Dynamics pipeline
-- Scope: Contact/Account entities with extensible pattern for remaining 34 objects
-- Run frequency: Daily after ETL pipeline completion, or before go-live UAT
-- =====================================================================================

USE DATABASE AUDIT_DB;
CREATE SCHEMA IF NOT EXISTS TEST_RESULTS;
USE SCHEMA TEST_RESULTS;

-- =====================================================================================
-- TEST RESULTS TRACKING TABLE
-- =====================================================================================
CREATE OR REPLACE TABLE TEST_RESULTS.REGRESSION_TEST_LOG (
    TEST_ID VARCHAR NOT NULL,
    TEST_NAME VARCHAR NOT NULL,
    TEST_CATEGORY VARCHAR NOT NULL,
    ENTITY_TYPE VARCHAR NOT NULL,
    STATUS VARCHAR NOT NULL,
    PASSED NUMBER DEFAULT 0,
    FAILED NUMBER DEFAULT 0,
    WARNINGS NUMBER DEFAULT 0,
    ERROR_MESSAGE VARCHAR,
    ROW_COUNT NUMBER DEFAULT 0,
    EXECUTION_TIME_MS NUMBER,
    STARTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    COMPLETED_AT TIMESTAMP_LTZ,
    NOTES VARCHAR,
    CONSTRAINT PK_REGRESSION_LOG PRIMARY KEY (TEST_ID, STARTED_AT)
);

-- =====================================================================================
-- TEST 1: DATA COMPLETENESS - Raisers Edge to Snowflake Staging
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_1_RE_TO_STG_COMPLETENESS()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_rows_loaded NUMBER;
    v_rows_missing NUMBER;
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    LET v_rows_loaded := (
        SELECT COUNT(*) FROM RAW.RAISERS_EDGE.STG_T_CONSTITUENT
        WHERE EXTRACT_TS > DATEADD(day, -1, CURRENT_TIMESTAMP())
    );
    
    LET v_rows_missing := (
        SELECT COUNT(*) FROM RAW.RAISERS_EDGE.ODS_T_CONSTITUENT
        WHERE IS_DELETED = FALSE
            AND CONSTITUENT_ID NOT IN (
                SELECT CONSTITUENT_ID FROM RAW.RAISERS_EDGE.STG_T_CONSTITUENT
                WHERE EXTRACT_TS > DATEADD(day, -1, CURRENT_TIMESTAMP())
            )
    );
    
    v_test_status := CASE 
        WHEN v_rows_loaded > 0 AND v_rows_missing < 10 THEN 'PASS'
        WHEN v_rows_loaded > 0 AND v_rows_missing BETWEEN 10 AND 100 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T1_RE_STG', 'RE to Staging Completeness', 'DATA_LOAD', 'CONTACT', v_test_status, 
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END, 
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            NULL, v_rows_loaded, DATEDIFF(ms, v_start_time, v_end_time), 
            v_start_time, v_end_time, 
            'Loaded: ' || v_rows_loaded || ', Missing: ' || v_rows_missing);
    
    RETURN TABLE(
        SELECT 'T1_RE_STG' AS TEST_ID,
               'RE to Staging Completeness' AS TEST_NAME,
               v_test_status AS STATUS,
               'Loaded: ' || v_rows_loaded || ', Missing: ' || v_rows_missing AS NOTES,
               v_rows_loaded AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 2: DATA QUALITY - Null/Invalid Values in Staging
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_2_STG_DATA_QUALITY()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_null_ids NUMBER;
    v_null_names NUMBER;
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    LET v_null_ids := (
        SELECT COUNT(*) FROM RAW.RAISERS_EDGE.STG_T_CONSTITUENT
        WHERE EXTRACT_TS > DATEADD(day, -1, CURRENT_TIMESTAMP())
            AND (CONSTITUENT_ID IS NULL OR CONSTITUENT_ID = '')
    );
    
    LET v_null_names := (
        SELECT COUNT(*) FROM RAW.RAISERS_EDGE.STG_T_CONSTITUENT
        WHERE EXTRACT_TS > DATEADD(day, -1, CURRENT_TIMESTAMP())
            AND COALESCE(FIRST_NAME, LAST_NAME, GENERICNAME, '') = ''
    );
    
    v_test_status := CASE 
        WHEN v_null_ids = 0 AND v_null_names = 0 THEN 'PASS'
        WHEN v_null_ids < 10 AND v_null_names < 100 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T2_STG_QA', 'Staging Data Quality Checks', 'DATA_QUALITY', 'CONTACT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Null IDs: ' || v_null_ids || ', Null Names: ' || v_null_names,
            v_null_ids + v_null_names, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time, 
            'Null IDs: ' || v_null_ids || ', Null Names: ' || v_null_names);
    
    RETURN TABLE(
        SELECT 'T2_STG_QA' AS TEST_ID,
               'Staging Data Quality Checks' AS TEST_NAME,
               v_test_status AS STATUS,
               'Null IDs: ' || v_null_ids || ', Null Names: ' || v_null_names AS NOTES,
               (v_null_ids + v_null_names) AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 3: MDM STANDARDIZATION - Records Transform to Standardised Format
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_3_MDM_STANDARDIZATION()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_re_count NUMBER;
    v_std_count NUMBER;
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    LET v_re_count := (
        SELECT COUNT(*) FROM RAW.RAISERS_EDGE.ODS_T_CONSTITUENT
        WHERE IS_DELETED = FALSE
    );
    
    LET v_std_count := (
        SELECT COUNT(DISTINCT SOURCE_RECORD_ID) FROM MDM_DB.STAGING.STANDARDISED_RECORDS
        WHERE SOURCE_SYSTEM = 'RAISERS_EDGE'
            AND SOURCE_RECORD_ID IN (
                SELECT CONSTITUENT_ID FROM RAW.RAISERS_EDGE.ODS_T_CONSTITUENT
                WHERE IS_DELETED = FALSE
            )
    );
    
    v_test_status := CASE 
        WHEN ABS(v_re_count - v_std_count) / NULLIF(v_re_count, 0) < 0.05 THEN 'PASS'
        WHEN ABS(v_re_count - v_std_count) / NULLIF(v_re_count, 0) < 0.10 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T3_MDM_STD', 'MDM Standardization Coverage', 'MDM_PROCESSING', 'CONTACT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'RE: ' || v_re_count || ', Standardised: ' || v_std_count,
            v_std_count, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'RE: ' || v_re_count || ', Standardised: ' || v_std_count || ', Delta: ' || (v_re_count - v_std_count));
    
    RETURN TABLE(
        SELECT 'T3_MDM_STD' AS TEST_ID,
               'MDM Standardization Coverage' AS TEST_NAME,
               v_test_status AS STATUS,
               'RE: ' || v_re_count || ', Standardised: ' || v_std_count AS NOTES,
               v_std_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 4: MDM MATCHING - Golden Records Created
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_4_MDM_MATCHING()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_std_count NUMBER;
    v_golden_count NUMBER;
    v_match_ratio NUMERIC(5,2);
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    LET v_std_count := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.STANDARDISED_RECORDS
        WHERE SOURCE_SYSTEM = 'RAISERS_EDGE'
    );
    
    LET v_golden_count := (
        SELECT COUNT(*) FROM MDM_DB.GOLD.GOLDEN_RECORDS
        WHERE DOMAIN = 'INDIVIDUAL'
    );
    
    LET v_match_ratio := (v_golden_count / NULLIF(v_std_count, 0)) * 100;
    
    v_test_status := CASE 
        WHEN v_match_ratio BETWEEN 60 AND 100 THEN 'PASS'
        WHEN v_match_ratio BETWEEN 50 AND 60 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T4_MDM_MATCH', 'MDM Matching & Golden Records', 'MDM_PROCESSING', 'CONTACT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Standardised: ' || v_std_count || ', Golden: ' || v_golden_count || ', Ratio: ' || v_match_ratio || '%',
            v_golden_count, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'Standardised: ' || v_std_count || ', Golden: ' || v_golden_count || ', Ratio: ' || v_match_ratio || '%');
    
    RETURN TABLE(
        SELECT 'T4_MDM_MATCH' AS TEST_ID,
               'MDM Matching & Golden Records' AS TEST_NAME,
               v_test_status AS STATUS,
               'Standardised: ' || v_std_count || ', Golden: ' || v_golden_count || ', Ratio: ' || v_match_ratio || '%' AS NOTES,
               v_golden_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 5: XREF CAPTURE - Identity Tracking Across Systems
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_5_XREF_CAPTURE()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_golden_count NUMBER;
    v_xref_count NUMBER;
    v_xref_coverage NUMERIC(5,2);
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    LET v_golden_count := (
        SELECT COUNT(*) FROM MDM_DB.GOLD.GOLDEN_RECORDS
        WHERE DOMAIN = 'INDIVIDUAL'
    );
    
    LET v_xref_count := (
        SELECT COUNT(DISTINCT GOLDEN_RECORD_ID) FROM MDM_DB.GOLD.XREF
        WHERE SOURCE_SYSTEM = 'RAISERS_EDGE'
    );
    
    LET v_xref_coverage := (v_xref_count / NULLIF(v_golden_count, 0)) * 100;
    
    v_test_status := CASE 
        WHEN v_xref_coverage >= 95 THEN 'PASS'
        WHEN v_xref_coverage >= 90 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T5_XREF', 'XREF Identity Capture', 'IDENTITY_MGMT', 'CONTACT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Coverage: ' || v_xref_coverage || '% (' || v_xref_count || '/' || v_golden_count || ')',
            v_xref_count, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'Coverage: ' || v_xref_coverage || '% (' || v_xref_count || '/' || v_golden_count || ')');
    
    RETURN TABLE(
        SELECT 'T5_XREF' AS TEST_ID,
               'XREF Identity Capture' AS TEST_NAME,
               v_test_status AS STATUS,
               'Coverage: ' || v_xref_coverage || '% (' || v_xref_count || '/' || v_golden_count || ')' AS NOTES,
               v_xref_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 6: DYNAMICS PAYLOAD GENERATION - Contact Payloads Created
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_6_DYNAMICS_PAYLOAD_CONTACT()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_golden_count NUMBER;
    v_payload_count NUMBER;
    v_null_payload_count NUMBER;
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    LET v_golden_count := (
        SELECT COUNT(*) FROM MDM_DB.GOLD.GOLDEN_RECORDS
        WHERE DOMAIN = 'INDIVIDUAL'
    );
    
    LET v_payload_count := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.DT_D365_CONTACT_PAYLOAD
        WHERE IS_ACTIVE = TRUE
    );
    
    LET v_null_payload_count := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.DT_D365_CONTACT_PAYLOAD
        WHERE IS_ACTIVE = TRUE
            AND (FIRSTNAME IS NULL AND LASTNAME IS NULL)
    );
    
    v_test_status := CASE 
        WHEN v_payload_count > 0 AND v_null_payload_count = 0 AND ABS(v_payload_count - v_golden_count) < v_golden_count * 0.05 THEN 'PASS'
        WHEN v_payload_count > 0 AND v_null_payload_count < v_payload_count * 0.01 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T6_D365_PAYLOAD', 'Dynamics Contact Payload Generation', 'PAYLOAD', 'CONTACT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Payloads: ' || v_payload_count || ', Null: ' || v_null_payload_count || ', Golden: ' || v_golden_count,
            v_payload_count, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'Payloads: ' || v_payload_count || ', Null names: ' || v_null_payload_count || ', Golden: ' || v_golden_count);
    
    RETURN TABLE(
        SELECT 'T6_D365_PAYLOAD' AS TEST_ID,
               'Dynamics Contact Payload Generation' AS TEST_NAME,
               v_test_status AS STATUS,
               'Payloads: ' || v_payload_count || ', Null names: ' || v_null_payload_count || ', Golden: ' || v_golden_count AS NOTES,
               v_payload_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 7: MAPPING COMPLETENESS - Fields Populated vs Mapping Spec
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_7_MAPPING_COMPLETENESS()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_total_payload_rows NUMBER;
    v_rows_with_data NUMBER;
    v_data_coverage NUMERIC(5,2);
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    LET v_total_payload_rows := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.DT_D365_CONTACT_PAYLOAD
        WHERE IS_ACTIVE = TRUE
    );
    
    LET v_rows_with_data := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.DT_D365_CONTACT_PAYLOAD
        WHERE IS_ACTIVE = TRUE
            AND (FIRSTNAME IS NOT NULL OR LASTNAME IS NOT NULL)
            AND (EMAILADDRESS1 IS NOT NULL OR TELEPHONE1 IS NOT NULL OR MOBILEPHONE IS NOT NULL)
    );
    
    LET v_data_coverage := (v_rows_with_data / NULLIF(v_total_payload_rows, 0)) * 100;
    
    v_test_status := CASE 
        WHEN v_data_coverage >= 85 THEN 'PASS'
        WHEN v_data_coverage >= 70 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T7_MAP_COMP', 'Mapping Field Completeness', 'MAPPING', 'CONTACT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Coverage: ' || v_data_coverage || '% (' || v_rows_with_data || '/' || v_total_payload_rows || ')',
            v_rows_with_data, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'Coverage: ' || v_data_coverage || '% (' || v_rows_with_data || '/' || v_total_payload_rows || ')');
    
    RETURN TABLE(
        SELECT 'T7_MAP_COMP' AS TEST_ID,
               'Mapping Field Completeness' AS TEST_NAME,
               v_test_status AS STATUS,
               'Coverage: ' || v_data_coverage || '% (' || v_rows_with_data || '/' || v_total_payload_rows || ')' AS NOTES,
               v_rows_with_data AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 8: PIPELINE EXECUTION STATE - Watermark & Reconciliation
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_8_PIPELINE_STATE()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_last_run_status VARCHAR;
    v_last_run_rows NUMBER;
    v_consecutive_failures NUMBER;
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    SELECT LAST_RUN_STATUS, LAST_RUN_ROWS, CONSECUTIVE_FAILURES
    INTO v_last_run_status, v_last_run_rows, v_consecutive_failures
    FROM AUDIT_DB.CONFIG.PIPELINE_WATERMARK
    WHERE PIPELINE_ID = 'RAISERS_EDGE'
        AND ENTITY_ID = 'T_CONSTITUENT'
        AND LAST_RUN_END IS NOT NULL
    ORDER BY LAST_RUN_END DESC
    LIMIT 1;
    
    v_test_status := CASE 
        WHEN v_last_run_status = 'SUCCESS' AND v_consecutive_failures = 0 AND v_last_run_rows > 0 THEN 'PASS'
        WHEN v_last_run_status = 'SUCCESS' AND v_consecutive_failures BETWEEN 0 AND 2 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T8_PIPELINE', 'Pipeline Execution State', 'PIPELINE_STATE', 'CONTACT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Last run: ' || v_last_run_status || ', Rows: ' || COALESCE(v_last_run_rows::VARCHAR, 'N/A') || ', Failures: ' || v_consecutive_failures,
            COALESCE(v_last_run_rows, 0), DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'Last run: ' || v_last_run_status || ', Rows: ' || COALESCE(v_last_run_rows::VARCHAR, 'N/A') || ', Consecutive Failures: ' || v_consecutive_failures);
    
    RETURN TABLE(
        SELECT 'T8_PIPELINE' AS TEST_ID,
               'Pipeline Execution State' AS TEST_NAME,
               v_test_status AS STATUS,
               'Last run: ' || v_last_run_status || ', Rows: ' || COALESCE(v_last_run_rows::VARCHAR, 'N/A') || ', Failures: ' || v_consecutive_failures AS NOTES,
               COALESCE(v_last_run_rows, 0) AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- MASTER REGRESSION TEST EXECUTOR
-- =====================================================================================
CREATE OR REPLACE PROCEDURE RUN_FULL_REGRESSION_TEST()
RETURNS TABLE (TEST_SUMMARY VARCHAR)
LANGUAGE SQL
AS
$$
DECLARE
    v_total_tests NUMBER := 0;
    v_passed NUMBER := 0;
    v_failed NUMBER := 0;
    v_warned NUMBER := 0;
    v_execution_start TIMESTAMP_LTZ;
    v_execution_end TIMESTAMP_LTZ;
BEGIN
    v_execution_start := CURRENT_TIMESTAMP();
    
    -- Execute all tests
    CALL TEST_1_RE_TO_STG_COMPLETENESS();
    CALL TEST_2_STG_DATA_QUALITY();
    CALL TEST_3_MDM_STANDARDIZATION();
    CALL TEST_4_MDM_MATCHING();
    CALL TEST_5_XREF_CAPTURE();
    CALL TEST_6_DYNAMICS_PAYLOAD_CONTACT();
    CALL TEST_7_MAPPING_COMPLETENESS();
    CALL TEST_8_PIPELINE_STATE();
    
    v_execution_end := CURRENT_TIMESTAMP();
    
    -- Aggregate results
    SELECT COUNT(*), SUM(PASSED), SUM(FAILED), SUM(WARNINGS)
    INTO v_total_tests, v_passed, v_failed, v_warned
    FROM REGRESSION_TEST_LOG
    WHERE STARTED_AT >= v_execution_start;
    
    RETURN TABLE(
        SELECT '=== REGRESSION TEST SUMMARY ===' ||
               ' | Total: ' || v_total_tests ||
               ' | Passed: ' || v_passed ||
               ' | Failed: ' || v_failed ||
               ' | Warnings: ' || v_warned ||
               ' | Execution Time: ' || DATEDIFF(seconds, v_execution_start, v_execution_end) || 's' AS TEST_SUMMARY
    );
END;
$$;

-- View recent test results:
-- SELECT * FROM REGRESSION_TEST_LOG WHERE STARTED_AT > CURRENT_DATE ORDER BY STARTED_AT DESC;
