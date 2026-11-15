-- =====================================================================================
-- DYNAMICS INTEGRATION TEST SUITE
-- =====================================================================================
-- Purpose: Validate Snowflake → Dynamics ADF Pipeline and Data Arrival
-- Focus: End-to-end payload creation, ADF execution, and Dynamics ingestion
-- =====================================================================================

USE DATABASE AUDIT_DB;
USE SCHEMA TEST_RESULTS;

-- =====================================================================================
-- TEST 9: ADF Payload Readiness - All Required Fields Present
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_9_ADF_PAYLOAD_READINESS()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_contact_payload_count NUMBER;
    v_account_payload_count NUMBER;
    v_contact_missing_id NUMBER;
    v_account_missing_id NUMBER;
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    -- Contact payloads ready for export
    LET v_contact_payload_count := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.DT_D365_CONTACT_PAYLOAD
        WHERE IS_ACTIVE = TRUE
    );
    
    LET v_contact_missing_id := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.DT_D365_CONTACT_PAYLOAD
        WHERE IS_ACTIVE = TRUE
            AND (CONTACTID IS NULL OR CONTACTID = '')
    );
    
    -- Account payloads ready for export
    LET v_account_payload_count := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.DT_D365_ACCOUNT_PAYLOAD
        WHERE IS_ACTIVE = TRUE
    );
    
    LET v_account_missing_id := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.DT_D365_ACCOUNT_PAYLOAD
        WHERE IS_ACTIVE = TRUE
            AND (ACCOUNTID IS NULL OR ACCOUNTID = '')
    );
    
    v_test_status := CASE 
        WHEN v_contact_payload_count > 0 AND v_account_payload_count > 0
            AND v_contact_missing_id = 0 AND v_account_missing_id = 0 THEN 'PASS'
        WHEN v_contact_payload_count > 0 AND v_account_payload_count > 0
            AND v_contact_missing_id < 10 AND v_account_missing_id < 10 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T9_ADF_READY', 'ADF Payload Readiness', 'ADF_PIPELINE', 'CONTACT/ACCOUNT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Contact: ' || v_contact_payload_count || ' (missing: ' || v_contact_missing_id || '), Account: ' || v_account_payload_count || ' (missing: ' || v_account_missing_id || ')',
            v_contact_payload_count + v_account_payload_count, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'Contact Payloads: ' || v_contact_payload_count || ' | Account Payloads: ' || v_account_payload_count);
    
    RETURN TABLE(
        SELECT 'T9_ADF_READY' AS TEST_ID,
               'ADF Payload Readiness' AS TEST_NAME,
               v_test_status AS STATUS,
               'Contact: ' || v_contact_payload_count || ' (missing IDs: ' || v_contact_missing_id || '), Account: ' || v_account_payload_count || ' (missing IDs: ' || v_account_missing_id || ')' AS NOTES,
               (v_contact_payload_count + v_account_payload_count) AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 10: Request Queue Status - VW_D365_REQUESTS
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_10_REQUEST_QUEUE_STATUS()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_pending_requests NUMBER;
    v_completed_requests NUMBER;
    v_failed_requests NUMBER;
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    -- Count pending/new requests (ready to send to Dynamics)
    LET v_pending_requests := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.VW_D365_REQUESTS
        WHERE REQUEST_STATUS IN ('NEW', 'PENDING', 'QUEUED')
    );
    
    -- Count completed requests (successfully sent to Dynamics)
    LET v_completed_requests := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.VW_D365_REQUESTS
        WHERE REQUEST_STATUS = 'SENT'
    );
    
    -- Count failed requests (errors, retries exceeded)
    LET v_failed_requests := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.VW_D365_REQUESTS
        WHERE REQUEST_STATUS IN ('FAILED', 'ERROR')
    );
    
    -- Expect: pending > 0, failed = 0 or very small
    v_test_status := CASE 
        WHEN v_pending_requests > 0 AND v_failed_requests = 0 THEN 'PASS'
        WHEN v_pending_requests > 0 AND v_failed_requests < v_pending_requests * 0.01 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T10_REQ_QUEUE', 'Request Queue Status', 'ADF_PIPELINE', 'CONTACT/ACCOUNT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Pending: ' || v_pending_requests || ', Completed: ' || v_completed_requests || ', Failed: ' || v_failed_requests,
            v_pending_requests + v_completed_requests + v_failed_requests, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'Pending: ' || v_pending_requests || ' | Completed: ' || v_completed_requests || ' | Failed: ' || v_failed_requests);
    
    RETURN TABLE(
        SELECT 'T10_REQ_QUEUE' AS TEST_ID,
               'Request Queue Status' AS TEST_NAME,
               v_test_status AS STATUS,
               'Pending: ' || v_pending_requests || ', Completed: ' || v_completed_requests || ', Failed: ' || v_failed_requests AS NOTES,
               v_pending_requests AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 11: ADF Pipeline Execution Health
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_11_ADF_EXECUTION_HEALTH()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_last_adf_run TIMESTAMP_LTZ;
    v_time_since_last_run_hours NUMBER;
    v_last_run_success NUMBER;
    v_consecutive_failures NUMBER;
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    -- Get last ADF run details (from PIPELINE_WATERMARK if available)
    SELECT MAX(LAST_RUN_END), 
           MAX(CASE WHEN LAST_RUN_STATUS = 'SUCCESS' THEN 1 ELSE 0 END),
           MAX(CONSECUTIVE_FAILURES)
    INTO v_last_adf_run, v_last_run_success, v_consecutive_failures
    FROM AUDIT_DB.CONFIG.PIPELINE_WATERMARK
    WHERE PIPELINE_ID = 'DYNAMICS' OR PIPELINE_ID LIKE 'ADF_%';
    
    LET v_time_since_last_run_hours := DATEDIFF(hours, COALESCE(v_last_adf_run, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP());
    
    -- Expect: run within last 24 hours, no consecutive failures
    v_test_status := CASE 
        WHEN v_time_since_last_run_hours <= 24 AND COALESCE(v_consecutive_failures, 0) = 0 THEN 'PASS'
        WHEN v_time_since_last_run_hours <= 48 AND COALESCE(v_consecutive_failures, 0) <= 1 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T11_ADF_HEALTH', 'ADF Execution Health', 'ADF_PIPELINE', 'CONTACT/ACCOUNT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Last run: ' || COALESCE(v_time_since_last_run_hours::VARCHAR, 'N/A') || ' hours ago, Failures: ' || COALESCE(v_consecutive_failures::VARCHAR, 'N/A'),
            0, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'Last ADF run: ' || COALESCE(v_last_adf_run::VARCHAR, 'Never') || ' | Consecutive Failures: ' || COALESCE(v_consecutive_failures::VARCHAR, '0'));
    
    RETURN TABLE(
        SELECT 'T11_ADF_HEALTH' AS TEST_ID,
               'ADF Execution Health' AS TEST_NAME,
               v_test_status AS STATUS,
               'Last run: ' || COALESCE(v_time_since_last_run_hours::VARCHAR, 'N/A') || ' hours ago' AS NOTES,
               0 AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 12: Dynamics Data Reconciliation - Snowflake vs Dynamics
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_12_DYNAMICS_RECONCILIATION()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_snowflake_contact_count NUMBER;
    v_dynamics_contact_count NUMBER;
    v_delta NUMERIC(5,2);
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    -- Count contacts in Snowflake payload ready to send
    LET v_snowflake_contact_count := (
        SELECT COUNT(*) FROM MDM_DB.STAGING.DT_D365_CONTACT_PAYLOAD
        WHERE IS_ACTIVE = TRUE
    );
    
    -- Count contacts received in Dynamics ODS (will be populated by reverse ETL)
    LET v_dynamics_contact_count := (
        SELECT COUNT(*) FROM RAW.DYNAMICS.ODS_CONTACTS
        WHERE IS_DELETED = FALSE
    );
    
    LET v_delta := ((v_snowflake_contact_count - v_dynamics_contact_count) / NULLIF(v_snowflake_contact_count, 0)) * 100;
    
    -- Expect: Dynamics should have ~100% of Snowflake contacts (or growing toward it)
    v_test_status := CASE 
        WHEN v_dynamics_contact_count = 0 THEN 'WARN'  -- Dynamics ingestion hasn't happened yet
        WHEN ABS(v_delta) < 5 THEN 'PASS'
        WHEN ABS(v_delta) < 10 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T12_D365_RECON', 'Dynamics Reconciliation', 'DYNAMICS_INGESTION', 'CONTACT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Snowflake: ' || v_snowflake_contact_count || ', Dynamics: ' || v_dynamics_contact_count || ', Delta: ' || v_delta || '%',
            v_dynamics_contact_count, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'Snowflake Contacts: ' || v_snowflake_contact_count || ' | Dynamics Contacts: ' || v_dynamics_contact_count || ' | Delta: ' || v_delta || '%');
    
    RETURN TABLE(
        SELECT 'T12_D365_RECON' AS TEST_ID,
               'Dynamics Reconciliation' AS TEST_NAME,
               v_test_status AS STATUS,
               'Snowflake: ' || v_snowflake_contact_count || ', Dynamics: ' || v_dynamics_contact_count || ', Delta: ' || v_delta || '%' AS NOTES,
               v_dynamics_contact_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- TEST 13: Reverse ETL Health - Dynamics to Snowflake
-- =====================================================================================
CREATE OR REPLACE PROCEDURE TEST_13_REVERSE_ETL_HEALTH()
RETURNS TABLE (TEST_ID VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, NOTES VARCHAR, ROW_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_start_time TIMESTAMP_LTZ;
    v_end_time TIMESTAMP_LTZ;
    v_reverse_etl_enabled BOOLEAN;
    v_last_reverse_etl_run TIMESTAMP_LTZ;
    v_time_since_run_hours NUMBER;
    v_reverse_etl_count NUMBER;
    v_test_status VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    
    -- Check if Reverse ETL is enabled (SP_ETL_DYNAMICS should not be disabled)
    LET v_reverse_etl_enabled := (
        SELECT CASE WHEN COUNT(*) > 0 THEN TRUE ELSE FALSE END
        FROM MDM_DB.STAGING.STANDARDISED_RECORDS
        WHERE SOURCE_SYSTEM = 'DYNAMICS'
    );
    
    -- Get last time Dynamics data was pulled back
    SELECT MAX(EXTRACT_TS)
    INTO v_last_reverse_etl_run
    FROM RAW.DYNAMICS.ODS_CONTACTS
    WHERE IS_DELETED = FALSE;
    
    LET v_time_since_run_hours := DATEDIFF(hours, COALESCE(v_last_reverse_etl_run, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP());
    
    LET v_reverse_etl_count := (
        SELECT COUNT(*) FROM RAW.DYNAMICS.ODS_CONTACTS
        WHERE IS_DELETED = FALSE
    );
    
    -- Expect: Reverse ETL running and pulling data regularly
    v_test_status := CASE 
        WHEN v_reverse_etl_enabled AND v_time_since_run_hours <= 48 AND v_reverse_etl_count > 0 THEN 'PASS'
        WHEN v_time_since_run_hours <= 72 THEN 'WARN'
        ELSE 'FAIL'
    END;
    
    v_end_time := CURRENT_TIMESTAMP();
    
    INSERT INTO REGRESSION_TEST_LOG 
    VALUES ('T13_REV_ETL', 'Reverse ETL Health', 'DYNAMICS_INGESTION', 'CONTACT', v_test_status,
            CASE WHEN v_test_status = 'PASS' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'FAIL' THEN 1 ELSE 0 END,
            CASE WHEN v_test_status = 'WARN' THEN 1 ELSE 0 END,
            'Enabled: ' || v_reverse_etl_enabled || ', Last run: ' || v_time_since_run_hours || ' hours ago, Records: ' || v_reverse_etl_count,
            v_reverse_etl_count, DATEDIFF(ms, v_start_time, v_end_time),
            v_start_time, v_end_time,
            'Reverse ETL: ' || CASE WHEN v_reverse_etl_enabled THEN 'ENABLED' ELSE 'DISABLED' END || ' | Last run: ' || v_time_since_run_hours || ' hrs | Count: ' || v_reverse_etl_count);
    
    RETURN TABLE(
        SELECT 'T13_REV_ETL' AS TEST_ID,
               'Reverse ETL Health' AS TEST_NAME,
               v_test_status AS STATUS,
               'Enabled: ' || v_reverse_etl_enabled || ', Last run: ' || v_time_since_run_hours || ' hours ago' AS NOTES,
               v_reverse_etl_count AS ROW_COUNT
    );
END;
$$;

-- =====================================================================================
-- DYNAMICS INTEGRATION TEST RUNNER
-- =====================================================================================
CREATE OR REPLACE PROCEDURE RUN_DYNAMICS_INTEGRATION_TESTS()
RETURNS TABLE (SUMMARY VARCHAR)
LANGUAGE SQL
AS
$$
BEGIN
    -- Execute Dynamics-specific integration tests
    CALL TEST_9_ADF_PAYLOAD_READINESS();
    CALL TEST_10_REQUEST_QUEUE_STATUS();
    CALL TEST_11_ADF_EXECUTION_HEALTH();
    CALL TEST_12_DYNAMICS_RECONCILIATION();
    CALL TEST_13_REVERSE_ETL_HEALTH();
    
    RETURN TABLE(
        SELECT 'Dynamics Integration Tests Completed' AS SUMMARY
    );
END;
$$;

-- =====================================================================================
-- COMBINED TEST SUITE: All Tests
-- =====================================================================================
CREATE OR REPLACE PROCEDURE RUN_ALL_REGRESSION_TESTS()
RETURNS TABLE (FINAL_SUMMARY VARCHAR)
LANGUAGE SQL
AS
$$
DECLARE
    v_total_tests NUMBER;
    v_total_passed NUMBER;
    v_total_failed NUMBER;
    v_total_warnings NUMBER;
BEGIN
    -- Run pipeline tests
    CALL RUN_FULL_REGRESSION_TEST();
    
    -- Run Dynamics integration tests
    CALL RUN_DYNAMICS_INTEGRATION_TESTS();
    
    -- Aggregate all results
    SELECT COUNT(*), 
           SUM(PASSED), 
           SUM(FAILED), 
           SUM(WARNINGS)
    INTO v_total_tests, v_total_passed, v_total_failed, v_total_warnings
    FROM REGRESSION_TEST_LOG
    WHERE STARTED_AT > DATEADD(hour, -2, CURRENT_TIMESTAMP());
    
    RETURN TABLE(
        SELECT '=== COMPLETE REGRESSION TEST SUITE SUMMARY ===' ||
               ' | Total Tests: ' || v_total_tests ||
               ' | PASSED: ' || v_total_passed ||
               ' | FAILED: ' || v_total_failed ||
               ' | WARNINGS: ' || v_total_warnings AS FINAL_SUMMARY
    );
END;
$$;

-- =====================================================================================
-- QUICK RESULTS QUERIES
-- =====================================================================================
-- View all test results from today:
--   SELECT * FROM REGRESSION_TEST_LOG WHERE DATE(STARTED_AT) = CURRENT_DATE ORDER BY TEST_CATEGORY, TEST_ID;
--
-- View failed tests only:
--   SELECT * FROM REGRESSION_TEST_LOG WHERE STATUS = 'FAIL' ORDER BY STARTED_AT DESC;
--
-- View test summary by category:
--   SELECT TEST_CATEGORY, STATUS, COUNT(*) as count FROM REGRESSION_TEST_LOG WHERE STARTED_AT > CURRENT_DATE GROUP BY TEST_CATEGORY, STATUS;
-- =====================================================================================
