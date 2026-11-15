# Quick Start: Running Regression Tests

## 30-Second Setup

```sql
-- 1. Load all test procedures (run these 3 files once)
EXECUTE IMMEDIATE FROM @~/TEST_REGRESSION_DYNAMICS_MIGRATION.sql;
EXECUTE IMMEDIATE FROM @~/TEST_ENTITY_PARAMETRIC_TEMPLATE.sql;
EXECUTE IMMEDIATE FROM @~/TEST_DYNAMICS_INTEGRATION.sql;

-- 2. Run complete test suite
CALL RUN_ALL_REGRESSION_TESTS();

-- 3. View results
SELECT TEST_ID, TEST_NAME, STATUS, NOTES, ROW_COUNT, EXECUTION_TIME_MS
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE DATE(STARTED_AT) = CURRENT_DATE
ORDER BY TEST_ID;
```

## Common Commands

### View Latest Results
```sql
SELECT * FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG 
WHERE STARTED_AT > DATEADD(hour, -24, CURRENT_TIMESTAMP())
ORDER BY STARTED_AT DESC LIMIT 50;
```

### Check for Failures
```sql
SELECT TEST_ID, TEST_NAME, STATUS, ERROR_MESSAGE, COMPLETED_AT
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STATUS IN ('FAIL', 'ERROR')
ORDER BY COMPLETED_AT DESC;
```

### Test Summary (Last 7 Days)
```sql
SELECT 
    TEST_CATEGORY,
    STATUS,
    COUNT(*) as count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY TEST_CATEGORY), 1) as pct
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STARTED_AT > DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY TEST_CATEGORY, STATUS
ORDER BY TEST_CATEGORY;
```

### Run Specific Test Type

```sql
-- Pipeline tests only
CALL RUN_FULL_REGRESSION_TEST();

-- Dynamics integration only
CALL RUN_DYNAMICS_INTEGRATION_TESTS();

-- Single test
CALL TEST_1_RE_TO_STG_COMPLETENESS();
CALL TEST_6_DYNAMICS_PAYLOAD_CONTACT();
CALL TEST_12_DYNAMICS_RECONCILIATION();
```

### Test a Specific Entity

```sql
-- Test CONSTITUENT
CALL RUN_ENTITY_REGRESSION_TESTS('CONSTITUENT', 'RAW.RAISERS_EDGE', 'RAW.RAISERS_EDGE', 'CONSTITUENT_ID');

-- Test GIFT
CALL RUN_ENTITY_REGRESSION_TESTS('GIFT', 'RAW.RAISERS_EDGE', 'RAW.RAISERS_EDGE', 'GIFT_ID');

-- Test ACCOUNT
CALL RUN_ENTITY_REGRESSION_TESTS('ACCOUNT', 'RAW.RAISERS_EDGE', 'RAW.RAISERS_EDGE', 'ACCOUNT_ID');
```

## Test Status Legend

| Status | Meaning | Action |
|--------|---------|--------|
| **PASS** | Test passed all criteria | ✓ No action needed |
| **WARN** | Test passed but with concerns | ⚠️ Review notes, monitor |
| **FAIL** | Test failed criteria | 🔴 Investigate immediately |

## Pre-Go-Live Checklist

Run this before launching Dynamics:

```sql
-- Run all tests
CALL RUN_ALL_REGRESSION_TESTS();

-- Verify all tests passed
SELECT COUNT(*) as fail_count
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STATUS = 'FAIL'
  AND STARTED_AT > DATEADD(hour, -2, CURRENT_TIMESTAMP());
-- Expected result: fail_count = 0

-- View test summary
SELECT TEST_CATEGORY, STATUS, COUNT(*) 
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STARTED_AT > DATEADD(hour, -2, CURRENT_TIMESTAMP())
GROUP BY TEST_CATEGORY, STATUS
ORDER BY TEST_CATEGORY;
```

## Daily Monitoring

```sql
-- This should be run automatically by Snowflake Task
-- To run manually:
CALL RUN_ALL_REGRESSION_TESTS();

-- Then check for any issues:
SELECT * FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STARTED_AT > DATEADD(day, -1, CURRENT_TIMESTAMP())
  AND STATUS != 'PASS'
ORDER BY COMPLETED_AT DESC;
```

## Troubleshooting Quick Links

- **Test fails immediately?** → Check if test schema exists: `SELECT * FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG LIMIT 1;`
- **No Dynamics data?** → Expected before ADF runs; check `T12_DYNAMICS_RECONCILIATION` status
- **XREF empty?** → Run: `CALL MDM_DB.GOLD.SP_XREF_CAPTURE_RE_ID(...)`
- **Pipeline watermarks wrong?** → Update `AUDIT_DB.CONFIG.PIPELINE_WATERMARK` manually

## Performance

- **Full suite runtime:** ~45 seconds
- **Single test:** ~2-5 seconds
- **Log query:** ~500ms (optimized)

## Files

- `TEST_REGRESSION_DYNAMICS_MIGRATION.sql` - 8 pipeline tests
- `TEST_ENTITY_PARAMETRIC_TEMPLATE.sql` - Entity templates (36 objects)
- `TEST_DYNAMICS_INTEGRATION.sql` - 5 Dynamics/ADF tests
- `TEST_SUITE_README.md` - Full documentation
- `QUICK_START_GUIDE.md` - This file
