# Test Execution Flowchart

## High-Level Test Suite Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   REGRESSION TEST SUITE                                      │
│               Dynamics Migration Pipeline Validation                         │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌──────────────┐
                              │ Run Tests    │
                              └──────┬───────┘
                                     │
                ┌────────────────────┼────────────────────┐
                │                    │                    │
                v                    v                    v
        ┌─────────────┐      ┌──────────────┐      ┌────────────┐
        │   TIER 1    │      │   TIER 2     │      │  TIER 3    │
        │ Pipeline    │      │   Entity     │      │  Dynamics  │
        │   Tests     │      │   Tests      │      │   Tests    │
        │  (8 tests)  │      │  (Template)  │      │  (5 tests) │
        └─────────────┘      └──────────────┘      └────────────┘
                │                    │                    │
                ├─T1: Load           ├─ET-1: Extract     ├─T9: Payload
                ├─T2: Quality        ├─ET-2: Integrity   ├─T10: Queue
                ├─T3: Std            ├─ET-3: Coverage    ├─T11: Health
                ├─T4: Match          ├─ET-4: Dedup       ├─T12: Recon
                ├─T5: XREF           ├─ET-5: XREF        └─T13: RevETL
                ├─T6: Payload        └─ET-6: Quality
                ├─T7: Mapping
                └─T8: Pipeline

                              ┌──────────────┐
                              │ Log Results  │
                              │  to Audit DB │
                              └──────┬───────┘
                                     │
                              ┌──────────────┐
                              │ Generate     │
                              │ Summary      │
                              └──────┬───────┘
                                     │
                ┌────────────────────┼────────────────────┐
                │                    │                    │
                v                    v                    v
            ┌────────┐           ┌────────┐           ┌────────┐
            │  PASS  │           │  WARN  │           │  FAIL  │
            │   ✓    │           │   ⚠️    │           │   🔴   │
            └────────┘           └────────┘           └────────┘
                │                    │                    │
                v                    v                    v
         Ready for      Monitor &    Investigate &
         Production     Review       Fix Immediately
```

---

## Test Execution Sequence

```
STEP 1: INITIALIZE
  ├─ Load SQL files into Snowflake
  ├─ Create procedures in AUDIT_DB.TEST_RESULTS
  └─ Initialize REGRESSION_TEST_LOG table

STEP 2: EXECUTE TIER 1 - PIPELINE (8 tests, ~15 sec)
  ├─ T1: RE→STG Completeness
  ├─ T2: Staging Quality
  ├─ T3: MDM Standardization
  ├─ T4: MDM Matching
  ├─ T5: XREF Capture
  ├─ T6: D365 Payload
  ├─ T7: Mapping Complete
  └─ T8: Pipeline State

STEP 3: EXECUTE TIER 2 - ENTITIES (configurable, ~10 sec/entity)
  ├─ ET-1: Data Extraction
  ├─ ET-2: Referential Integrity
  ├─ ET-3: MDM Coverage
  ├─ ET-4: Deduplication
  ├─ ET-5: XREF Reconciliation
  └─ ET-6: Payload Quality
       (Repeat for each entity: CONSTITUENT, GIFT, etc.)

STEP 4: EXECUTE TIER 3 - DYNAMICS (5 tests, ~15 sec)
  ├─ T9: ADF Payload Ready
  ├─ T10: Request Queue
  ├─ T11: ADF Health
  ├─ T12: Dynamics Reconciliation
  └─ T13: Reverse ETL

STEP 5: AGGREGATE & LOG
  ├─ Count PASS/FAIL/WARN results
  ├─ Calculate execution time
  └─ Insert summary into REGRESSION_TEST_LOG

STEP 6: ALERT & NOTIFY
  ├─ If FAIL: Trigger alert
  ├─ If WARN: Log for review
  └─ If PASS: Clear to proceed
```

---

## Data Flow Through Pipeline & Tests

```
RAISERS EDGE                SNOWFLAKE STAGING              MDM PROCESSING
─────────────────          ──────────────────────          ──────────────
  Active                                                      Golden
  Records                                                     Records
     │                                                           │
     │                                                           │
     v                                                           v
Constituent ────────────────> STG_T_CONSTITUENT ─────────> Standardised
  1,398 K                       (via ADF)                    Records
                                                                │
  ┌─────────────┐          ┌─────────────┐                ┌─────────────┐
  │ T1: Load?   │          │ T2: Quality?│                │ T3: Std%?   │
  │ ✓ Loaded    │          │ ✓ Valid     │                │ ✓ 99% cover │
  └─────────────┘          └─────────────┘                └─────────────┘
                                                                │
                                                                v
                                                          Match Pairs
                                                                │
                                                                v
                                                          Deduplication
                                                                │
  ┌─────────────┐          ┌─────────────┐                ┌─────────────┐
  │             │          │ T8: Pipe    │                │ T4: Golden? │
  │             │          │ State? ✓    │                │ ✓ 75% ratio │
  └─────────────┘          └─────────────┘                └─────────────┘
                                                                │
                                                                v
                                                          Golden Record
                                                          (Main Entity)
                                                                │
                                                          ┌─────────────┐
                                                          │ T5: XREF?   │
                                                          │ ✓ 95% track │
                                                          └─────────────┘


DYNAMICS PAYLOAD              ADF PIPELINE                  DYNAMICS ODS
────────────────────         ──────────────                ──────────────
Payload Extracted                                           Contact
   │                                                          Record
   v                                                           │
Contact                                                        │
 Payload ────────────────────────────────────────────────>  Received
  │                            │                              │
  ├─ First Name                │                              │
  ├─ Last Name                 │  ┌─────────────┐            │
  ├─ Email      [T6: Gen? ✓]   │  │ T9: Ready?  │            │
  ├─ Phone      [T7: Map? ✓]   │  │ ✓ 100%      │            │
  └─ Address                   │  └─────────────┘            │
                               │                              │
                               └────────────────────────>    │
                                         ↓                    │
                              ┌─────────────────┐             │
                              │ T10: Queue? ✓   │             │
                              │ T11: Health? ✓  │             │
                              └─────────────────┘             │
                                                               ↓
                                                        ┌─────────────┐
                                                        │ T12: Recon? │
                                                        │ ✓ Match OK  │
                                                        └─────────────┘
                                                               │
                                                               v
                                                        Reverse ETL
                                                        Back to SF
                                                               │
                                                        ┌─────────────┐
                                                        │ T13: Rev?   │
                                                        │ ✓ Running   │
                                                        └─────────────┘
```

---

## Decision Tree: Test Failure Investigation

```
                    Test Returns FAIL
                           │
                           v
                ┌──────────────────────┐
                │ Check TEST_ID        │
                └──────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        v                  v                  v
    T1, T2, T3,      T6, T7, T9,          T12, T13
    T4, T5, T8        T10, T11
    PIPELINE          PAYLOAD/ADF         DYNAMICS
    TESTS             TESTS               TESTS
        │                  │                  │
        v                  v                  v
    CHECK:              CHECK:            CHECK:
    ├─ STG table       ├─ Payload table   ├─ Dynamics ODS
    ├─ ODS records     ├─ DT_D365_*       ├─ ADF logs
    ├─ MDM tables      ├─ Request queue   ├─ Reconciliation
    ├─ XREF table      ├─ ADF status      └─ Reverse ETL
    └─ Watermark       └─ Error messages      status
        │                  │                  │
        v                  v                  v
    FIX:                FIX:              FIX:
    ├─ Restart ADF      ├─ Rerun SP_ETL   ├─ Check ADF
    ├─ Update WM         │   _DYNAMICS     ├─ Check D365
    ├─ Rerun SP_STD      ├─ Check payload  └─ Enable RevETL
    └─ Verify data       │   logic         
                         └─ Requeue
                             requests
```

---

## Test Execution Commands

### Command 1: Full Suite (All Tests)
```sql
CALL RUN_ALL_REGRESSION_TESTS();
```
**Runtime:** ~45-60 seconds  
**Tests Run:** T1-T8 + T9-T13 = 13 tests  
**Use:** Daily regression, pre-go-live validation

### Command 2: Pipeline Only
```sql
CALL RUN_FULL_REGRESSION_TEST();
```
**Runtime:** ~15-20 seconds  
**Tests Run:** T1-T8 = 8 tests  
**Use:** During ETL development, quick validation

### Command 3: Dynamics Only
```sql
CALL RUN_DYNAMICS_INTEGRATION_TESTS();
```
**Runtime:** ~15-20 seconds  
**Tests Run:** T9-T13 = 5 tests  
**Use:** After ADF pipeline changes, Dynamics integration testing

### Command 4: Entity Testing
```sql
CALL RUN_ENTITY_REGRESSION_TESTS(
    'CONSTITUENT',
    'RAW.RAISERS_EDGE',
    'RAW.RAISERS_EDGE',
    'CONSTITUENT_ID'
);
```
**Runtime:** ~10-15 seconds per entity  
**Tests Run:** ET-1 to ET-6 = 6 tests  
**Use:** Validate individual entity through pipeline

### Command 5: Single Test
```sql
CALL TEST_6_DYNAMICS_PAYLOAD_CONTACT();
```
**Runtime:** ~2-5 seconds  
**Tests Run:** 1 test  
**Use:** Isolated testing, debugging specific failure

---

## Results Interpretation Matrix

| Status | Color | Meaning | Action | Next Step |
|--------|-------|---------|--------|-----------|
| **PASS** | 🟢 | Criteria met | Document | Proceed |
| **WARN** | 🟡 | Marginal pass | Monitor | Review daily |
| **FAIL** | 🔴 | Below threshold | Alert | Investigate now |

### Status Codes by Test

```
T1: RE→STG Completeness
  ├─ PASS: Loaded > 0 AND Missing < 10
  ├─ WARN: Loaded > 0 AND Missing 10-100
  └─ FAIL: Loaded = 0 OR Missing ≥ 100

T2: Staging Quality
  ├─ PASS: No nulls, All names populated
  ├─ WARN: < 10 nulls, < 100 missing names
  └─ FAIL: > 10 nulls OR > 100 missing names

T3: MDM Standardization
  ├─ PASS: Delta < 5%
  ├─ WARN: Delta 5-10%
  └─ FAIL: Delta > 10%

T4: MDM Matching
  ├─ PASS: Dedup ratio 60-100%
  ├─ WARN: Dedup ratio 50-60%
  └─ FAIL: Dedup ratio < 50%

T5: XREF Capture
  ├─ PASS: Coverage ≥ 95%
  ├─ WARN: Coverage 90-95%
  └─ FAIL: Coverage < 90%

T6: Payload Generation
  ├─ PASS: Payload = Golden ±5%, No nulls
  ├─ WARN: Payload = Golden ±5%, < 1% nulls
  └─ FAIL: Payload ≠ Golden OR > 1% nulls

T7: Mapping Completeness
  ├─ PASS: ≥ 85% with critical data
  ├─ WARN: ≥ 70% with critical data
  └─ FAIL: < 70%

T8: Pipeline State
  ├─ PASS: SUCCESS, 0 failures, Rows > 0
  ├─ WARN: SUCCESS, ≤ 2 failures
  └─ FAIL: FAILED OR ≥ 3 failures

T9: ADF Ready
  ├─ PASS: Both payloads, No missing IDs
  ├─ WARN: Both payloads, < 10 missing IDs
  └─ FAIL: Missing payload OR > 10 missing IDs

T10: Request Queue
  ├─ PASS: Pending > 0, Failed = 0
  ├─ WARN: Pending > 0, Failed < 1%
  └─ FAIL: Failed ≥ 1%

T11: ADF Health
  ├─ PASS: Last run ≤ 24h, 0 failures
  ├─ WARN: Last run ≤ 48h, ≤ 1 failure
  └─ FAIL: Run > 48h OR ≥ 2 failures

T12: Dynamics Recon
  ├─ PASS: Delta < 5% (or Dynamics=0 initially)
  ├─ WARN: Delta 5-10%
  └─ FAIL: Delta > 10%

T13: Reverse ETL
  ├─ PASS: Enabled, Last run ≤ 48h
  ├─ WARN: Last run ≤ 72h
  └─ FAIL: Disabled OR Run > 72h
```

---

## Monitoring Dashboard Query

Track test results over time:

```sql
SELECT 
    DATE(STARTED_AT) as test_date,
    TEST_CATEGORY,
    STATUS,
    COUNT(*) as count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY DATE(STARTED_AT), TEST_CATEGORY), 1) as pct
FROM AUDIT_DB.TEST_RESULTS.REGRESSION_TEST_LOG
WHERE STARTED_AT > DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY DATE(STARTED_AT), TEST_CATEGORY, STATUS
ORDER BY test_date DESC, TEST_CATEGORY;
```

Expected 7-day trend for healthy pipeline:
```
Date       Category          PASS    WARN    FAIL
2026-11-15 Pipeline          8       0       0  ✓
2026-11-15 Entity (Sample)   6       0       0  ✓
2026-11-15 Dynamics          5       0       0  ✓
2026-11-14 Pipeline          8       0       0  ✓
2026-11-14 Entity (Sample)   6       0       0  ✓
2026-11-14 Dynamics          5       0       0  ✓
... (continue daily)
```

---

## Pre-Go-Live Checklist

```
☐ All SQL files loaded into Snowflake
☐ AUDIT_DB.TEST_RESULTS schema created
☐ REGRESSION_TEST_LOG table populated

☐ Full test suite runs without errors
☐ No FAIL status in results
☐ All PASS or acceptable WARN status
☐ Execution time < 60 seconds

☐ Entity tests run for Contact/Account
☐ Entity test results reviewed and approved
☐ Plan documented for testing remaining 34 entities

☐ Dynamics payloads verified in Snowflake
☐ ADF pipeline tested and successful
☐ Data arrived in Dynamics ODS
☐ Reverse ETL receiving data

☐ Daily scheduled task configured
☐ Alert notifications set up for failures
☐ Dashboard queries documented

☐ Go-live approval obtained
```

---

## Quick Reference: Common Issues

```
ISSUE: Test returns FAIL for T1 (RE→STG Completeness)
  → Check: ADF pipeline status in PIPELINE_WATERMARK
  → Fix: Restart ADF "Fetch Data Incrementally" pipeline

ISSUE: Test returns FAIL for T5 (XREF Capture)
  → Check: SP_XREF_CAPTURE procedures empty?
  → Fix: Run SP_XREF_CAPTURE_RE_ID manually

ISSUE: Test returns FAIL for T12 (Dynamics Reconciliation)
  → Check: Has ADF run since go-live?
  → Fix: Run ADF PL_RE_Writeback pipeline to Dynamics landing zone

ISSUE: Test returns FAIL for T13 (Reverse ETL)
  → Check: Line 12 SP_ETL_DYNAMICS() disabled?
  → Fix: Uncomment line 12 and run procedure
```

---

**Start Here:** `QUICK_START_GUIDE.md` (2 min read)  
**Full Details:** `TEST_SUITE_README.md` (10 min read)  
**Run Tests:** See "Test Execution Commands" above
