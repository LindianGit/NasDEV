# Next Object to Implement - Strategic Recommendation

## Analysis of Completed Work

✅ **Contact** (Constituent entity)
- Mapping complete (RE T_Constituent → Dynamics Contact)
- Standardised records created
- Golden record generation working
- Dynamics payload created (DT_D365_CONTACT_PAYLOAD)
- XREF capture in place
- Pattern proven end-to-end

✅ **Account** (Organization entity)
- Payload exists (DT_D365_ACCOUNT_PAYLOAD)
- References in place
- Foundation work complete

---

## Available 72 Raisers Edge Entities (Priority Analysis)

### Marked with asterisk (*) = Already in MDM processing (SP_ETL_RAISERS_EDGE)

**Currently Processed by MDM:**
- T_Addresses (8) *
- T_Constituent (21) * ✅ DONE - Contact
- T_ConstituentAddresses (23) *
- T_ConstituentAttributes (26) *
- T_ConstituentSolicitCodes (33) *
- T_ConstituentTypes (34) *
- T_EmailAddresses (36) *
- T_Gifts (47) *
- T_PhoneNumbers (53) *

---

## 🏆 RECOMMENDATION: Start with **GIFT** (Entity #47)

### Why GIFT is the Easiest Next Object

**1. Data & Complexity**
```
GIFT Entity:
├─ Complexity: LOW-MEDIUM (simpler than Contact)
├─ Data Volume: 89,180 rows (manageable)
├─ Dependencies: Contact ONLY (already done ✓)
├─ Fields: < Contact (no address parts, no salutations)
└─ Logic: Straightforward 1:1 mapping
```

**2. Dependencies Met**
- ✅ Requires: Contact (already complete)
- ✅ No complex hierarchies
- ✅ No multi-step transformations
- ✅ Clear Dynamics mapping exists (MSNFP_DONATION entity in D365)

**3. Raisers Edge Already Processes**
- ✅ T_Gifts is marked with `*` in SP_ETL_RAISERS_EDGE
- ✅ Already flowing through staging
- ✅ Already standardising and matching
- ✅ Just needs payload layer built

**4. Quick Win Potential**
- Expected build time: **3-5 days** (vs. 8 days for Contact)
- Reason: Pattern already established from Contact
- Can reuse Contact mapping logic
- Test templates ready from regression suite

**5. Business Value**
- Gifts are core to NAS fundraising data
- Required for donation tracking
- Enables campaign effectiveness analysis
- Critical for year-end reporting (Q1 deadline)

---

## Alternative Considerations

### Why NOT Address (Entity #8 or #23)?
```
Address Entity:
├─ Complexity: MEDIUM (hierarchical - Constituent has many Addresses)
├─ Data Volume: 2M+ rows (large)
├─ Many-to-one relationship (harder than Gift)
└─ Recommendation: #2 after Gift
```

### Why NOT Email (Entity #36) or Phone (Entity #53)?
```
Email/Phone Entities:
├─ Complexity: LOW (simplest)
├─ BUT: Already partially in Contact payload
├─ Would be collection tables (separate DDL needed)
├─ Data structure: Nested arrays vs. flat rows
└─ Recommendation: #3-4 after Address
```

### Why NOT Appeals (Entity #10 or #25)?
```
Appeals:
├─ Complexity: HIGH (multiple types, hierarchies)
├─ Dependencies: Contact + Gifts + Events
├─ Data modeling: Complex
└─ Recommendation: Later, after Address & Gift
```

---

## Implementation Roadmap (Recommended Order)

```
PHASE 1: ✅ Core Entity Pattern (COMPLETE)
  1. Contact (Constituent)         ✅ DONE
  2. Account (Organization)        ✅ DONE

PHASE 2: Simple Financial Tracking (3-4 weeks)
  3. GIFT ← RECOMMENDED NEXT
  4. Address
  5. Email/Phone Collections

PHASE 3: Complex Relationships (4-6 weeks)
  6. Events
  7. Appeals
  8. Pledges

PHASE 4: Supporting Entities (2-3 weeks)
  9. Notes
  10. Attributes
  ... (remaining 20+ entities)
```

---

## GIFT Implementation Blueprint

### 1. Raisers Edge Source
```
T_Gifts (47)  - Row count: 89,180
├─ GiftID (primary key)
├─ ConstituentID (FK → T_Constituent) ✓
├─ Amount
├─ GiftType
├─ GiftDate
├─ Method
├─ Solicitor
└─ ... (20-25 fields total)

Already staging as: STG_T_GIFTS
Already ODSed as: ODS_T_GIFTS
Already standardising via: SP_ETL_RAISERS_EDGE
```

### 2. Dynamics Target
```
msnfp_donation (Dynamics entity)
├─ msnfp_donationid (from GiftID via XREF)
├─ msnfp_accountid (from ConstituentID)
├─ msnfp_amount
├─ msnfp_donationtype
├─ msnfp_donationdate
├─ msnfp_method
└─ ... (mapped fields)
```

### 3. Required Deliverables

**A. MDM Layer (Days 1-1.5)**
- SP_ETL_GIFTS() procedure (standardise gifts from RE)
- STANDARDISED_RECORDS rows for gifts
- Golden record generation
- SP_XREF_CAPTURE_GIFT_ID() for identity tracking

**B. Dynamics Payload (Days 1.5-2)**
- DT_D365_DONATION_PAYLOAD (dynamic table)
- VW_D365_DONATION_REQUESTS (request builder)
- Payload testing with sample data

**C. ADF Integration (Days 2-3)**
- PL_RE_WriteBack extension for gifts
- Request dispatch to Dynamics
- Error handling and retries

**D. Validation (Days 3-5)**
- Regression tests for Gift entity (using templates)
- Reconciliation: RE → Snowflake → Dynamics
- Data quality validation

---

## Quick Start: GIFT Implementation

### Step 1: Verify Current State (1 hour)
```sql
-- Check gift data flow
SELECT COUNT(*) as constituent_count FROM RAW.RAISERS_EDGE.ODS_T_GIFTS;
SELECT COUNT(*) as gift_count FROM MDM_DB.STAGING.STANDARDISED_RECORDS 
  WHERE SOURCE_DOMAIN = 'GIFT';
SELECT COUNT(*) as golden_gifts FROM MDM_DB.GOLD.GOLDEN_RECORDS 
  WHERE DOMAIN = 'GIFT';
```

### Step 2: Test Entity Template (1 hour)
```sql
-- Use parametric entity tests
CALL RUN_ENTITY_REGRESSION_TESTS(
    'GIFT',
    'RAW.RAISERS_EDGE',
    'RAW.RAISERS_EDGE',
    'GIFT_ID'
);
```

### Step 3: Build Payload (2-3 days)
- Reference Contact payload (DT_D365_CONTACT_PAYLOAD) as pattern
- Map Gift fields to msnfp_donation schema
- Create DT_D365_DONATION_PAYLOAD dynamic table

### Step 4: Validate & Deploy (1-2 days)
- Run full regression suite
- UAT with NAS team
- Deploy to production

---

## Effort Estimate

| Phase | Task | Duration |
|-------|------|----------|
| 1 | Verify RE→Snowflake flow | 1 day |
| 2 | Build Dynamics payload | 2 days |
| 3 | ADF integration | 1.5 days |
| 4 | Testing & validation | 1-2 days |
| 5 | UAT & sign-off | 0.5-1 day |
| **TOTAL** | **Gift Entity Complete** | **5-6 days** |

**vs. Contact:** 8 days (25% faster due to pattern reuse)

---

## Success Criteria for GIFT

✅ All 89,180 gifts extracted and staged  
✅ 100% coverage in standardised records (no delta > 5%)  
✅ Golden records generated with deduplication  
✅ XREF tracking 95%+ coverage  
✅ Dynamics payload created with critical fields  
✅ ADF pushes payloads to Dynamics landing zone  
✅ Data arrives in Dynamics msnfp_donation entity  
✅ Reconciliation: RE count ≈ Dynamics count (±5%)  
✅ All regression tests PASS  
✅ Ready for next entity (Address)

---

## Files to Create/Modify

```
New Files:
├─ SP_ETL_GIFTS() procedure
├─ DT_D365_DONATION_PAYLOAD dynamic table
├─ VW_D365_DONATION_REQUESTS view
└─ PL_RE_WriteBack extension for gifts

Modified Files:
├─ SP_STANDARDISE_RECORDS() - add gift logic
├─ SP_GENERATE_GOLDEN_RECORDS() - add gift domain
├─ SP_XREF_CAPTURE() - add gift ID tracking
└─ TEST_ENTITY_PARAMETRIC_TEMPLATE.sql - run for GIFT
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Dependency on Contact | Contact is ✅ DONE; no blocker |
| Gift type codes | Map from T_CodeDescriptions (staging ready) |
| Amount precision | Verify Snowflake DECIMAL vs. Dynamics double |
| Date handling | Use same logic as Contact (proven) |
| Volume (89K) | Small enough for quick iteration |

---

## Next After GIFT?

After GIFT is complete and validated (5-6 days):

**ADDRESS** (Entity #8 / #23)
- Reason: Contact has many addresses (supports relationship testing)
- Complexity: Medium (hierarchical, ~2M rows)
- Timeline: ~6-8 days
- Value: Completes contact data enrichment

**Then: EMAIL/PHONE** (Entities #36 / #53)
- Reason: Collection types (prepares for complex hierarchies)
- Complexity: Low-Medium
- Timeline: ~4-5 days each

---

## Recommendation Summary

| Criterion | Rating | Reason |
|-----------|--------|--------|
| **Ease** | ⭐⭐⭐⭐⭐ | Simpler than Contact, pattern established |
| **Speed** | ⭐⭐⭐⭐⭐ | 5-6 days vs. 8 days for Contact |
| **Business Value** | ⭐⭐⭐⭐⭐ | Core fundraising data, Q1 deadline critical |
| **Dependencies** | ⭐⭐⭐⭐⭐ | Only Contact (done ✓), no blockers |
| **Risk** | ⭐⭐⭐⭐⭐ | Low; proven pattern, manageable volume |

---

## Action Items

**This Week:**
1. ✓ Review this recommendation with team
2. ✓ Verify Gift data flow in current Snowflake
3. ✓ Review Dynamics msnfp_donation schema
4. ✓ Kick off GIFT entity implementation

**Next Week:**
5. Build and test payload layer
6. Integrate with ADF
7. Run regression suite

**Week 3:**
8. UAT with NAS
9. Production deployment
10. Move to ADDRESS entity

---

**Recommendation:** Start with **GIFT** immediately.  
**Timeline:** 5-6 days to production.  
**Next:** ADDRESS follows same pattern.  
**By Q1:** All core entities (36) can be completed at 1 entity/week pace.
