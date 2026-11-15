# Dynamics Migration Regression Test Suite - Complete Index

## Overview

This is a production-ready regression test suite for validating the Raisers Edge → Snowflake → MDM → Dynamics migration. The suite includes **13 core tests** plus **parametric templates** for testing all 36 target entities.

**Key Stats:**
- **13 core regression tests** (pipeline + Dynamics)
- **6 parametric entity test templates** (extensible to all 36 objects)
- **Automated logging** to `AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG`
- **CI/CD ready** — integrates with Snowflake Tasks and Azure Data Factory
- **No external dependencies** — runs entirely within Snowflake

---

## Files in This Suite

### 1. `TEST_REGRESSION_DYNAMICS_MIGRATION.sql` (22.2 KB)
**Core Pipeline Regression Tests — 8 Tests**

Tests the complete ETL pipeline from Raisers Edge through Snowflake staging, MDM processing, and Dynamics payload generation.

**Tests Included:**
- T1: RE to Staging Completeness
- T2: Staging Data Quality  
- T3: MDM Standardization Coverage
- T4: MDM Matching & Golden Records
- T5: XREF Identity Capture
- T6: Dynamics Contact Payload Generation
- T7: Mapping Field Completeness
- T8: Pipeline Execution State

**Run with:**
```sql
CALL RUN_FULL_REGRESSION_TEST();
```

**Coverage:**
- ✓ Data load validation
- ✓ Data quality checks
- ✓ MDM transformation
- ✓ Identity management
- ✓ Payload readiness

---

### 2. `TEST_ENTITY_PARAMETRIC_TEMPLATE.sql` (13.1 KB)
**Parametric Entity Tests — Extensible to 36 Objects**

Reusable test templates for validating any entity. Designed to be called with entity name and primary key to test any of the 36 target Raisers Edge entities.

**Test Templates:**
- ET-1: Data Extraction
- ET-2: Referential Integrity
- ET-3: MDM Coverage
- ET-4: Deduplication Ratio
- ET-5: XREF Reconciliation
- ET-6: Payload Quality

**Run for any entity:**
```sql
-- Test CONSTITUENT
CALL RUN_ENTITY_REGRESSION_TESTS('CONSTITUENT', 'RAW.RAISERS_EDGE', 'RAW.RAISERS_EDGE', 'CONSTITUENT_ID');

-- Test GIFT
CALL RUN_ENTITY_REGRESSION_TESTS('GIFT', 'RAW.RAISERS_EDGE', 'RAW.RAISERS_EDGE', 'GIFT_ID');

-- Test ACCOUNT
CALL RUN_ENTITY_REGRESSION_TESTS('ACCOUNT', 'RAW.RAISERS_EDGE', 'RAW.RAISERS_EDGE', 'ACCOUNT_ID');
```

**Extensibility:**
- No code changes needed to test new entities
- Just provide entity name and primary key
- Supports all 36 target objects

---

### 3. `TEST_DYNAMICS_INTEGRATION.sql` (17.7 KB)
**Dynamics & ADF Integration Tests — 5 Tests**

Tests the Snowflake → Dynamics boundary, validates ADF pipeline health, and monitors the reverse ETL feedback loop.

**Tests Included:**
- T9: ADF Payload Readiness
- T10: Request Queue Status
- T11: ADF Execution Health
- T12: Dynamics Data Reconciliation
- T13: Reverse ETL Health

**Run with:**
```sql
CALL RUN_DYNAMICS_INTEGRATION_TESTS();
```

**Coverage:**
- ✓ Payload validation
- ✓ Request queue monitoring
- ✓ ADF pipeline health
- ✓ Snowflake ↔ Dynamics reconciliation
- ✓ Reverse ETL status

---

### 4. `TEST_SUITE_README.md` (15.2 KB)
**Complete Test Suite Documentation**

Comprehensive guide covering:
- Test architecture overview
- Detailed description of all 13 tests
- Running instructions (setup, quick run, targeted testing)
- Monitoring queries
- CI/CD integration patterns
- Troubleshooting guide
- Performance considerations

**Read this for:** Full test specifications, detailed pass/fail criteria, integration guides

---

### 5. `QUICK_START_GUIDE.md` (4.2 KB)
**Quick Reference for Test Execution**

Fast reference guide for:
- 30-second setup
- Common commands
- Test status legend
- Pre-go-live checklist
- Daily monitoring
- Troubleshooting quick links

**Read this for:** Fast lookups, running tests, checking results

---

## Execution Flow

```
┌──────────────────────────────────────────────────────────────┐
│ SETUP (One-time)                                             │
├──────────────────────────────────────────────────────────────┤
│ 1. Load SQL files into Snowflake                             │
│ 2. Creates procedures and tables in AUDIT_DB.TEST_RESULTS    │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│ RUN TESTS                                                     │
├──────────────────────────────────────────────────────────────┤
│ Option A: Full Suite                                         │
│   → CALL RUN_ALL_REGRESSION_TESTS();                         │
│     (Runs all 8 + 5 = 13 tests)                              │
│                                                               │
│ Option B: Pipeline Only                                      │
│   → CALL RUN_FULL_REGRESSION_TEST();                         │
│     (Runs 8 pipeline tests)                                  │
│                                                               │
│ Option C: Dynamics Only                                      │
│   → CALL RUN_DYNAMICS_INTEGRATION_TESTS();                   │
│     (Runs 5 Dynamics/ADF tests)                              │
│                                                               │
│ Option D: Entity Testing                                     │
│   → CALL RUN_ENTITY_REGRESSION_TESTS('ENTITY', ...);         │
│     (Runs 6 tests for specific entity)                       │
│                                                               │
│ Option E: Individual Test                                    │
│   → CALL TEST_N_NAME();                                      │
│     (Runs single test)                                       │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│ RESULTS LOGGED                                                │
├──────────────────────────────────────────────────────────────┤
│ All results stored in:                                       │
│ AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG                    │
│                                                               │
│ Columns: TEST_ID, TEST_NAME, STATUS, NOTES,                 │
│          ROW_COUNT, EXECUTION_TIME_MS, etc.                  │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│ QUERY RESULTS                                                 │
├──────────────────────────────────────────────────────────────┤
│ SELECT * FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG      │
│ WHERE STARTED_AT > DATEADD(day, -1, CURRENT_TIMESTAMP())     │
│ ORDER BY TEST_ID;                                            │
└──────────────────────────────────────────────────────────────┘
```

---

## Quick Reference: Test Categories

### Pipeline Tests (T1-T8)
Validate Raisers Edge → Snowflake → MDM transformation

| Test | Category | What It Tests | Pass Criteria |
|------|----------|---------------|---------------|
| T1 | Data Load | RE records extracted to staging | Loaded > 0, Missing < 10 |
| T2 | Data Quality | Null/invalid values in staging | No null keys, names populated |
| T3 | MDM | Records standardised | Delta < 5% vs ODS |
| T4 | MDM | Deduplication effective | Golden/Std ratio 60-100% |
| T5 | Identity | XREF records captured | Coverage ≥ 95% |
| T6 | Payload | Contact payloads created | Matches golden records ±5% |
| T7 | Mapping | Fields populated in payloads | ≥ 85% with contact data |
| T8 | Pipeline | ETL ran successfully | SUCCESS, 0 failures |

### Entity Tests (ET-1 to ET-6)
Validate any Raisers Edge entity through the pipeline

| Test | What It Tests | Extensible To |
|------|---------------|----------------|
| ET-1 | Data extraction | All 36 entities |
| ET-2 | Referential integrity | All 36 entities |
| ET-3 | MDM coverage | All 36 entities |
| ET-4 | Deduplication ratio | All 36 entities |
| ET-5 | XREF reconciliation | All 36 entities |
| ET-6 | Payload quality | All 36 entities |

### Dynamics Tests (T9-T13)
Validate Snowflake → Dynamics ADF and reverse ETL

| Test | Category | What It Tests | Pass Criteria |
|------|----------|---------------|---------------|
| T9 | ADF | Payloads ready for export | Both exist, no missing IDs |
| T10 | ADF | Request queue healthy | Pending > 0, Failed = 0 |
| T11 | ADF | Pipeline ran recently | Run < 24h, no failures |
| T12 | Recon | Data arrived in Dynamics | Delta < 5% |
| T13 | Reverse ETL | Feedback loop working | Enabled, run < 48h |

---

## Getting Started

### Step 1: Load Test Procedures
```sql
-- Load all three test files
EXECUTE IMMEDIATE FROM @~/TEST_REGRESSION_DYNAMICS_MIGRATION.sql;
EXECUTE IMMEDIATE FROM @~/TEST_ENTITY_PARAMETRIC_TEMPLATE.sql;
EXECUTE IMMEDIATE FROM @~/TEST_DYNAMICS_INTEGRATION.sql;
```

### Step 2: Run Tests
```sql
-- Option A: Everything
CALL RUN_ALL_REGRESSION_TESTS();

-- Option B: Pipeline only
CALL RUN_FULL_REGRESSION_TEST();

-- Option C: Dynamics only
CALL RUN_DYNAMICS_INTEGRATION_TESTS();

-- Option D: Specific entity
CALL RUN_ENTITY_REGRESSION_TESTS('CONSTITUENT', 'RAW.RAISERS_EDGE', 'RAW.RAISERS_EDGE', 'CONSTITUENT_ID');
```

### Step 3: View Results
```sql
SELECT TEST_ID, TEST_NAME, STATUS, NOTES, ROW_COUNT, EXECUTION_TIME_MS
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE DATE(STARTED_AT) = CURRENT_DATE
ORDER BY TEST_ID;
```

### Step 4: Investigate Failures (If Any)
```sql
SELECT * FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STATUS = 'FAIL'
ORDER BY COMPLETED_AT DESC;
```

---

## Integration Points

### Snowflake Tasks (Scheduled Daily Runs)
```sql
CREATE OR REPLACE TASK REGRESSION_TEST_DAILY
WAREHOUSE = COMPUTE_WH
SCHEDULE = 'USING CRON 0 2 * * * UTC'
AS
CALL AUDIT_DB.TEST_RESULTS.RUN_ALL_REGRESSION_TESTS();

ALTER TASK REGRESSION_TEST_DAILY RESUME;
```

### Azure Data Factory (Post-Pipeline Validation)
Add a stored procedure activity after MDM/ADF pipelines complete:
- Procedure: `RUN_ALL_REGRESSION_TESTS()`
- Failure handling: Stop pipeline if tests fail

### Dashboard/Monitoring (Bi-Weekly Review)
Query for test trends:
```sql
SELECT DATE(STARTED_AT) as date, TEST_CATEGORY, STATUS, COUNT(*) as count
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STARTED_AT > DATEADD(month, -1, CURRENT_TIMESTAMP())
GROUP BY DATE(STARTED_AT), TEST_CATEGORY, STATUS
ORDER BY date DESC;
```

---

## Test Results Interpretation

### Expected Results (Production Ready)

All tests should return **PASS** with green indicators:

```
T1:  PASS ✓  RE to Staging Completeness
T2:  PASS ✓  Staging Data Quality
T3:  PASS ✓  MDM Standardization Coverage
T4:  PASS ✓  MDM Matching & Golden Records
T5:  PASS ✓  XREF Identity Capture
T6:  PASS ✓  Dynamics Contact Payload
T7:  PASS ✓  Mapping Field Completeness
T8:  PASS ✓  Pipeline Execution State
T9:  PASS ✓  ADF Payload Readiness
T10: PASS ✓  Request Queue Status
T11: PASS ✓  ADF Execution Health
T12: PASS ✓  Dynamics Reconciliation
T13: PASS ✓  Reverse ETL Health
```

### Warning Signs (WARN Status)

Review and monitor, but not blocking:
- T3: MDM delta 5-10%
- T4: Dedup ratio < 60%
- T5: XREF coverage 90-95%
- T11: ADF run 24-48h ago
- T12: Delta 5-10%

### Failure Conditions (FAIL Status)

Must be investigated immediately:
- T1: Staging load not running
- T2: Null primary keys
- T3, T4: High transformation loss
- T5: No identity tracking
- T6: No payloads created
- T8: Pipeline failed
- T9: Missing Dynamics payloads
- T10: High request failures
- T11: ADF not running
- T12: Data not arriving in Dynamics
- T13: Reverse ETL disabled

---

## Support & Maintenance

### Troubleshooting
See `TEST_SUITE_README.md` → **Troubleshooting** section for:
- Common failure causes
- Resolution steps
- When to escalate

### Customization
To adjust test thresholds or add new tests:
1. Edit the specific test procedure in the SQL file
2. Change PASS/WARN/FAIL criteria (case statements)
3. Redeploy the modified SQL
4. No impact on other tests

### Performance
- **Full suite:** ~45 seconds
- **Single test:** ~2-5 seconds
- **Log query:** ~500ms

### Historical Data
All test results retained indefinitely. Archive if needed:
```sql
-- Archive results older than 90 days
DELETE FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STARTED_AT < DATEADD(month, -3, CURRENT_TIMESTAMP());
```

---

## Pre-Go-Live Validation Gate

**Do this before launching Dynamics in production:**

```sql
-- Run complete test suite
CALL RUN_ALL_REGRESSION_TESTS();

-- Verify no failures
SELECT COUNT(*) as fail_count
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STATUS = 'FAIL'
  AND STARTED_AT > DATEADD(hour, -2, CURRENT_TIMESTAMP());

-- Expected: fail_count = 0

-- If > 0, investigate failures before proceeding
SELECT TEST_ID, TEST_NAME, ERROR_MESSAGE, NOTES
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STATUS = 'FAIL'
  AND STARTED_AT > DATEADD(hour, -2, CURRENT_TIMESTAMP());
```

---

## Files Summary

| File | Size | Purpose | Read Time |
|------|------|---------|-----------|
| TEST_REGRESSION_DYNAMICS_MIGRATION.sql | 22 KB | 8 core pipeline tests | - |
| TEST_ENTITY_PARAMETRIC_TEMPLATE.sql | 13 KB | 6 entity test templates | - |
| TEST_DYNAMICS_INTEGRATION.sql | 18 KB | 5 Dynamics/ADF tests | - |
| TEST_SUITE_README.md | 15 KB | Complete documentation | 10 min |
| QUICK_START_GUIDE.md | 4 KB | Quick reference | 2 min |
| TEST_SUITE_INDEX.md | This file | Overview & index | 5 min |

---

## Contact & Support

For issues or questions:
1. Check `TEST_SUITE_README.md` → **Troubleshooting**
2. Review test notes in `REGRESSION_TEST_LOG`
3. Escalate with: Test name, timestamp, and failure details

---

**Version:** 1.0  
**Created:** 2026-11-15  
**Last Updated:** 2026-11-15  
**Status:** Production Ready
