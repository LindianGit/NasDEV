# Dynamics Migration Regression Test Suite

## Overview

A comprehensive, production-ready regression test suite for validating the Raisers Edge → Snowflake → MDM → Dynamics migration pipeline. Tests are organized into three tiers and can be run independently or as a complete suite.

**Total Test Coverage:** 13 core tests + parametric entity templates  
**Extensibility:** Template-based design supports all 36 target entities  
**Automation:** All tests log results to `AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG` for CI/CD integration

---

## Test Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│           REGRESSION TEST SUITE                                  │
├──────────────────────┬──────────────────────┬───────────────────┤
│  PIPELINE TESTS      │  ENTITY TESTS        │  DYNAMICS TESTS   │
│  (8 tests)           │  (Parametric)        │  (5 tests)        │
├──────────────────────┼──────────────────────┼───────────────────┤
│ • RE→STG Load        │ • Extract             │ • Payload Ready   │
│ • Data Quality       │ • Referential Int.    │ • Request Queue   │
│ • MDM Std.           │ • MDM Coverage        │ • ADF Health      │
│ • MDM Match          │ • Dedup Ratio         │ • D365 Recon      │
│ • XREF Capture       │ • XREF Recon          │ • Reverse ETL     │
│ • D365 Payload       │ • Payload Quality     │                   │
│ • Mapping            │                       │                   │
│ • Pipeline State     │                       │                   │
└──────────────────────┴──────────────────────┴───────────────────┘
```

---

## File Structure

```
AUDIT_DB/Tests/
├── TEST_REGRESSION_DYNAMICS_MIGRATION.sql    # Core pipeline tests (8 tests)
├── TEST_ENTITY_PARAMETRIC_TEMPLATE.sql       # Entity-level test templates
├── TEST_DYNAMICS_INTEGRATION.sql             # Dynamics ADF & integration tests (5 tests)
└── TEST_SUITE_README.md                      # This file
```

---

## Test Details

### Tier 1: Pipeline Tests (8 tests)

**File:** `TEST_REGRESSION_DYNAMICS_MIGRATION.sql`

#### T1: RE to Staging Completeness
- **Purpose:** Verify all active Raisers Edge records extracted to Snowflake staging
- **Pass Criteria:** Loaded > 0 AND Missing < 10
- **Warn Criteria:** Loaded > 0 AND Missing 10-100
- **Fails:** Loaded = 0 OR Missing ≥ 100

#### T2: Staging Data Quality
- **Purpose:** Validate null/invalid values in extracted data
- **Checks:**
  - No null primary keys (CONSTITUENT_ID)
  - At least one name field populated per record
- **Pass Criteria:** Zero null IDs, zero records without names
- **Warn Criteria:** < 10 null IDs, < 100 nameless records

#### T3: MDM Standardization Coverage
- **Purpose:** Verify all RE records transformed to standardised format
- **Metric:** Standardised record count vs. ODS active count
- **Pass Criteria:** Delta < 5%
- **Warn Criteria:** Delta 5-10%

#### T4: MDM Matching & Golden Records
- **Purpose:** Validate deduplication and golden record creation
- **Metric:** Golden Record count / Standardised Records (dedup ratio)
- **Pass Criteria:** Ratio 60-100% (indicates effective matching)
- **Warn Criteria:** Ratio 50-60%

#### T5: XREF Identity Capture
- **Purpose:** Ensure identity tracking between Raisers Edge and Snowflake
- **Metric:** XREF records coverage vs. golden records
- **Pass Criteria:** Coverage ≥ 95%
- **Warn Criteria:** Coverage ≥ 90%

#### T6: Dynamics Contact Payload Generation
- **Purpose:** Validate payloads ready for Dynamics ingestion
- **Checks:**
  - Payload count matches golden record count (±5%)
  - No records with missing both FIRSTNAME and LASTNAME
- **Pass Criteria:** Match ✓, No null names
- **Warn Criteria:** Match ✓, < 1% null names

#### T7: Mapping Completeness
- **Purpose:** Verify critical fields populated in payloads
- **Metric:** % of records with name + contact data (email/phone)
- **Pass Criteria:** ≥ 85% coverage
- **Warn Criteria:** ≥ 70% coverage

#### T8: Pipeline State
- **Purpose:** Verify last ETL pipeline execution succeeded
- **Metric:** Watermark status, row counts, consecutive failures
- **Pass Criteria:** LAST_RUN_STATUS = 'SUCCESS', Failures = 0, Rows > 0
- **Warn Criteria:** SUCCESS, Failures ≤ 2

**Execution:**
```sql
CALL RUN_FULL_REGRESSION_TEST();
```

---

### Tier 2: Entity-Level Tests (Parametric Templates)

**File:** `TEST_ENTITY_PARAMETRIC_TEMPLATE.sql`

Reusable procedures for testing any entity. Supports all 36 target entities (CONSTITUENT, GIFT, DONATION, ACCOUNT, EVENT, etc.).

#### ET-1: Data Extraction
- **Parameter:** Entity name (e.g., 'CONSTITUENT', 'GIFT')
- **Tests:** STG vs. ODS row count delta
- **Extensibility:** Change entity name → tests the next object

#### ET-2: Referential Integrity
- **Tests:** Orphaned records (in staging, missing from ODS)

#### ET-3: MDM Coverage
- **Tests:** What % of ODS records made it to MDM standardisation

#### ET-4: Deduplication Ratio
- **Tests:** Golden record count vs. standardised (dedup effectiveness)

#### ET-5: XREF Reconciliation
- **Tests:** Identity tracking coverage for the entity

#### ET-6: Payload Quality
- **Tests:** Critical fields populated in entity payloads

**Usage Example:**

```sql
-- Test CONSTITUENT entity
CALL RUN_ENTITY_REGRESSION_TESTS(
    'CONSTITUENT',                  -- entity name
    'RAW.RAISERS_EDGE',            -- source schema
    'RAW.RAISERS_EDGE',            -- ODS schema
    'CONSTITUENT_ID'                -- primary key
);

-- Test GIFT entity
CALL RUN_ENTITY_REGRESSION_TESTS(
    'GIFT',
    'RAW.RAISERS_EDGE',
    'RAW.RAISERS_EDGE',
    'GIFT_ID'
);

-- Test ACCOUNT entity
CALL RUN_ENTITY_REGRESSION_TESTS(
    'ACCOUNT',
    'RAW.RAISERS_EDGE',
    'RAW.RAISERS_EDGE',
    'ACCOUNT_ID'
);
```

---

### Tier 3: Dynamics Integration Tests (5 tests)

**File:** `TEST_DYNAMICS_INTEGRATION.sql`

Tests the Snowflake → Dynamics boundary, ADF pipeline health, and reverse ETL.

#### T9: ADF Payload Readiness
- **Purpose:** Verify all Contact & Account payloads ready for ADF export
- **Checks:**
  - Contact payloads exist
  - Account payloads exist
  - No missing IDs (cannot map to Dynamics)
- **Pass Criteria:** Both payloads > 0, Missing IDs = 0

#### T10: Request Queue Status
- **Purpose:** Monitor pending/completed/failed requests in VW_D365_REQUESTS
- **Metric:** Pending vs. Failed request ratio
- **Pass Criteria:** Pending > 0, Failed = 0
- **Warn Criteria:** Pending > 0, Failed < 1% of pending

#### T11: ADF Execution Health
- **Purpose:** Verify ADF pipeline ran recently and successfully
- **Metric:** Hours since last run, consecutive failures
- **Pass Criteria:** Last run ≤ 24h ago, No failures
- **Warn Criteria:** Last run ≤ 48h ago, ≤ 1 failure

#### T12: Dynamics Reconciliation
- **Purpose:** Compare Snowflake payloads vs. Dynamics ODS (row counts)
- **Metric:** Delta between Snowflake and Dynamics contacts
- **Status Logic:**
  - **WARN** if Dynamics = 0 (ingestion hasn't started)
  - **PASS** if Delta < 5%
  - **WARN** if Delta 5-10%
  - **FAIL** if Delta > 10%

#### T13: Reverse ETL Health
- **Purpose:** Verify Dynamics → Snowflake feedback loop operational
- **Metric:** Last time Dynamics data pulled back, record count
- **Pass Criteria:** Enabled, Last run ≤ 48h ago, Records > 0
- **Warn Criteria:** Last run ≤ 72h ago

**Execution:**
```sql
CALL RUN_DYNAMICS_INTEGRATION_TESTS();

-- Or run everything:
CALL RUN_ALL_REGRESSION_TESTS();
```

---

## Running the Tests

### Setup (One-time)

```sql
-- Create test schema and results table
USE DATABASE AUDIT_DB;
CREATE SCHEMA IF NOT EXISTS TEST_RESULTS;

-- Run the test SQL files
EXECUTE IMMEDIATE FROM @~/TEST_REGRESSION_DYNAMICS_MIGRATION.sql;
EXECUTE IMMEDIATE FROM @~/TEST_ENTITY_PARAMETRIC_TEMPLATE.sql;
EXECUTE IMMEDIATE FROM @~/TEST_DYNAMICS_INTEGRATION.sql;
```

### Quick Run: All Tests

```sql
-- Run complete regression suite
CALL RUN_ALL_REGRESSION_TESTS();

-- View results
SELECT * FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG 
WHERE DATE(STARTED_AT) = CURRENT_DATE 
ORDER BY TEST_CATEGORY, TEST_ID;
```

### Targeted Testing

```sql
-- Pipeline tests only
CALL RUN_FULL_REGRESSION_TEST();

-- Dynamics integration only
CALL RUN_DYNAMICS_INTEGRATION_TESTS();

-- Specific entity (e.g., GIFT)
CALL RUN_ENTITY_REGRESSION_TESTS('GIFT', 'RAW.RAISERS_EDGE', 'RAW.RAISERS_EDGE', 'GIFT_ID');

-- Individual test
CALL TEST_1_RE_TO_STG_COMPLETENESS();
CALL TEST_6_DYNAMICS_PAYLOAD_CONTACT();
```

### Monitoring Queries

```sql
-- Recent failures
SELECT TEST_ID, TEST_NAME, STATUS, ERROR_MESSAGE, COMPLETED_AT
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STATUS = 'FAIL'
ORDER BY COMPLETED_AT DESC;

-- Test summary by category
SELECT TEST_CATEGORY, STATUS, COUNT(*) as count, 
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY TEST_CATEGORY), 1) as pct
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STARTED_AT > DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY TEST_CATEGORY, STATUS
ORDER BY TEST_CATEGORY, CASE WHEN STATUS = 'FAIL' THEN 0 WHEN STATUS = 'WARN' THEN 1 ELSE 2 END;

-- Test performance over time
SELECT DATE(STARTED_AT) as test_date, TEST_CATEGORY, STATUS, COUNT(*) as count
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STARTED_AT > DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY DATE(STARTED_AT), TEST_CATEGORY, STATUS
ORDER BY test_date DESC, TEST_CATEGORY;

-- Average execution time by test
SELECT TEST_ID, TEST_NAME, 
       ROUND(AVG(EXECUTION_TIME_MS), 1) as avg_exec_ms,
       ROUND(MAX(EXECUTION_TIME_MS), 1) as max_exec_ms,
       COUNT(*) as execution_count
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
GROUP BY TEST_ID, TEST_NAME
ORDER BY avg_exec_ms DESC;
```

---

## Integration with CI/CD

### Daily Automated Execution

**Snowflake Task (runs daily after ETL pipelines):**

```sql
CREATE OR REPLACE TASK REGRESSION_TEST_DAILY
WAREHOUSE = COMPUTE_WH
SCHEDULE = 'USING CRON 0 2 * * * UTC'  -- 2 AM UTC daily
AS
CALL AUDIT_DB.TEST_RESULTS.RUN_ALL_REGRESSION_TESTS();

ALTER TASK REGRESSION_TEST_DAILY RESUME;
```

### Azure Data Factory Integration

Add a stored procedure step in ADF after the MDM pipeline:

```json
{
  "name": "Run_Regression_Tests",
  "type": "SqlServerStoredProcedure",
  "linkedServiceName": "SnowflakeLinkedService",
  "typeProperties": {
    "storedProcedureName": "[AUDIT_DB].[TEST_RESULTS].[RUN_FULL_REGRESSION_TEST]"
  }
}
```

### Alerts & Notifications

```sql
-- Create alert for failed tests
CREATE OR REPLACE PROCEDURE SEND_TEST_FAILURES_ALERT()
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_failed_count NUMBER;
    v_message VARCHAR;
BEGIN
    SELECT COUNT(*) INTO v_failed_count
    FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
    WHERE STATUS = 'FAIL'
      AND STARTED_AT > DATEADD(hour, -1, CURRENT_TIMESTAMP());
    
    IF v_failed_count > 0 THEN
        v_message := 'ALERT: ' || v_failed_count || ' regression tests failed. Review: AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG';
        -- Send to email/Slack/Teams (implement notification here)
    END IF;
END;
$$;
```

---

## Test Maintenance & Updates

### Adding New Tests

1. Create a new procedure in the appropriate file (pipeline, entity, or dynamics)
2. Follow naming convention: `TEST_N_DESCRIPTION` (N = incrementing number)
3. Always insert results into `REGRESSION_TEST_LOG` for historical tracking
4. Add to the appropriate `RUN_*_TESTS()` master procedure

### Updating Entity Tests

To test a new entity (e.g., PLEDGE):

```sql
CALL RUN_ENTITY_REGRESSION_TESTS(
    'PLEDGE',
    'RAW.RAISERS_EDGE',
    'RAW.RAISERS_EDGE',
    'PLEDGE_ID'
);
```

No code changes needed—just provide the entity name and primary key.

### Adjusting Thresholds

Modify `PASS`/`WARN`/`FAIL` thresholds in test procedures:

```sql
-- Example: Change data quality threshold
-- Current: v_test_status := CASE WHEN v_null_ids = 0 ...
-- New:     v_test_status := CASE WHEN v_null_ids < 50 ...  -- More lenient
```

---

## Expected Test Results

### Production-Ready Baseline

For a healthy production state, expect:

| Test | Status | Notes |
|------|--------|-------|
| T1: RE to Staging | PASS | 100% of active records loaded |
| T2: Data Quality | PASS | No null keys or missing names |
| T3: MDM Standardization | PASS | < 5% delta |
| T4: MDM Matching | PASS | 60-100% dedup ratio |
| T5: XREF Capture | PASS | ≥ 95% coverage |
| T6: Payload Generation | PASS | 100% payload creation |
| T7: Mapping Completeness | PASS | ≥ 85% critical fields |
| T8: Pipeline State | PASS | SUCCESS, 0 failures |
| T9: ADF Ready | PASS | Both payloads, no missing IDs |
| T10: Request Queue | PASS | Pending > 0, Failed = 0 |
| T11: ADF Health | PASS | Run < 24h ago |
| T12: D365 Reconciliation | PASS | Delta < 5% |
| T13: Reverse ETL | PASS | Enabled, running < 48h |

### Pre-Go-Live Validation

Before launching Dynamics in production:

```sql
-- Run full suite
CALL RUN_ALL_REGRESSION_TESTS();

-- Verify no FAIL status
SELECT COUNT(*) as failed_count
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STATUS = 'FAIL'
  AND STARTED_AT > DATEADD(hour, -2, CURRENT_TIMESTAMP());

-- Expected: failed_count = 0
```

---

## Troubleshooting

### Test Returns FAIL

1. **Check test notes:** `ERROR_MESSAGE` and `NOTES` columns provide details
2. **Review specific query:** Run the underlying test query manually
3. **Check dependencies:** Verify prerequisite data loads completed
4. **Compare to baseline:** Run historical trend analysis

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|-----------|
| T1 FAIL | Staging load incomplete | Check ADF pipeline status, PIPELINE_WATERMARK |
| T5 FAIL | XREF procedures empty | Run SP_XREF_CAPTURE procedures manually |
| T11 FAIL | ADF pipeline disabled | Check ADF run history, enable triggers |
| T12 FAIL | Dynamics ingestion lag | Allow 24-48h for first load, check ADF status |
| T13 FAIL | Reverse ETL disabled | Uncomment SP_ETL_DYNAMICS() and enable scheduling |

---

## Performance Considerations

- **Test Suite Runtime:** ~30-60 seconds (8 core + 5 dynamics tests)
- **Log Retention:** Results stored indefinitely in `REGRESSION_TEST_LOG`
- **Archival:** Purge logs older than 90 days if storage is concern

```sql
-- Archive old test results
DELETE FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STARTED_AT < DATEADD(month, -3, CURRENT_TIMESTAMP());
```

---

## Next Steps

1. **Execute Setup:** Load all three SQL files into Snowflake
2. **Baseline:** Run tests and document baseline metrics
3. **Schedule:** Set up daily automated runs via Snowflake Tasks
4. **Monitor:** Track results dashboard and alerts
5. **Scale:** Extend entity tests to cover all 36 target objects
6. **Go-Live:** Use as final pre-production validation gate
