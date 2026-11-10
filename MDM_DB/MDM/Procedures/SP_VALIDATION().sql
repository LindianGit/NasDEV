CREATE OR REPLACE PROCEDURE MDM_DB.MDM.SP_VALIDATION()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    LET report                        VARCHAR := '''';
    LET v_active_records              INT := 0;
    LET v_match_candidates            INT := 0;
    LET v_match_groups                INT := 0;
    LET v_match_group_members         INT := 0;
    LET v_golden_records              INT := 0;
    LET v_xref_links                  INT := 0;
    LET v_gr_with_emails              INT := 0;
    LET v_gr_with_phones              INT := 0;
    LET v_gr_with_addresses           INT := 0;
    LET v_orphan_count                INT := 0;
    LET v_overmatched_groups          INT := 0;
    LET v_largest_group_size          INT := 0;
    LET v_largest_group_id            VARCHAR := ''N/A'';
    LET v_array_mismatches            INT := 0;
    LET v_cross_source_count          INT := 0;
    LET v_re_total                    INT := 0;
    LET v_re_matched                  INT := 0;
    LET v_hs_total                    INT := 0;
    LET v_hs_matched                  INT := 0;
    LET v_method_exact_email          INT := 0;
    LET v_method_exact_phone          INT := 0;
    LET v_method_exact_name_postcode  INT := 0;
    LET v_method_fuzzy_name_address   INT := 0;
    LET v_method_exact_name           INT := 0;
    LET v_status_auto                 INT := 0;
    LET v_status_pending              INT := 0;
    LET v_status_low                  INT := 0;
    -- Pipeline counts
    SELECT COUNT(*) INTO :v_active_records       FROM MDM_DB.STAGING.STANDARDISED_RECORDS WHERE _IS_ACTIVE = TRUE;
    SELECT COUNT(*) INTO :v_match_candidates      FROM MDM_DB.STAGING.MATCH_CANDIDATES;
    SELECT COUNT(*) INTO :v_match_groups          FROM MDM_DB.MDM.MATCH_GROUPS;
    SELECT COUNT(*) INTO :v_match_group_members   FROM MDM_DB.MDM.MATCH_GROUP_MEMBERS;
    SELECT COUNT(*) INTO :v_golden_records        FROM MDM_DB.GOLD.GOLDEN_RECORDS WHERE _IS_ACTIVE = TRUE;
    SELECT COUNT(*) INTO :v_xref_links            FROM MDM_DB.GOLD.XREF;

    report :=
        ''========================================'' || ''\\n'' ||
        ''MDM PIPELINE VALIDATION REPORT''           || ''\\n'' ||
        ''========================================''  || ''\\n'' ||
        ''Run at: '' || CURRENT_TIMESTAMP()::VARCHAR || ''\\n\\n'' ||
        ''--- PIPELINE SUMMARY ---''                 || ''\\n'' ||
        ''Active records:       '' || v_active_records      || ''\\n'' ||
        ''Match candidates:     '' || v_match_candidates    || ''\\n'' ||
        ''Match groups:         '' || v_match_groups        || ''\\n'' ||
        ''Match group members:  '' || v_match_group_members || ''\\n'' ||
        ''Golden records:       '' || v_golden_records      || ''\\n'' ||
        ''XREF links:           '' || v_xref_links          || ''\\n'';

    -- Source coverage
    SELECT COUNT(*), SUM(CASE WHEN mc.STANDARDISED_ID IS NOT NULL THEN 1 ELSE 0 END)
    INTO :v_re_total, :v_re_matched
    FROM MDM_DB.STAGING.STANDARDISED_RECORDS sr
    LEFT JOIN MDM_DB.STAGING.MATCH_COMPONENTS mc ON sr.STANDARDISED_ID = mc.STANDARDISED_ID
    WHERE sr._IS_ACTIVE = TRUE AND sr.SOURCE_SYSTEM = ''RAISERS_EDGE'';

    SELECT COUNT(*), SUM(CASE WHEN mc.STANDARDISED_ID IS NOT NULL THEN 1 ELSE 0 END)
    INTO :v_hs_total, :v_hs_matched
    FROM MDM_DB.STAGING.STANDARDISED_RECORDS sr
    LEFT JOIN MDM_DB.STAGING.MATCH_COMPONENTS mc ON sr.STANDARDISED_ID = mc.STANDARDISED_ID
    WHERE sr._IS_ACTIVE = TRUE AND sr.SOURCE_SYSTEM = ''HUBSPOT'';

    report := report ||
        ''\\n--- SOURCE COVERAGE ---'' || ''\\n'' ||
        ''Raisers Edge: '' || v_re_total || '' total, '' || v_re_matched || '' matched ('' ||
            CASE WHEN v_re_total > 0 THEN ROUND(v_re_matched * 100.0 / v_re_total, 1)::VARCHAR ELSE ''0'' END || ''%)'' || ''\\n'' ||
        ''HubSpot:      '' || v_hs_total || '' total, '' || v_hs_matched || '' matched ('' ||
            CASE WHEN v_hs_total > 0 THEN ROUND(v_hs_matched * 100.0 / v_hs_total, 1)::VARCHAR ELSE ''0'' END || ''%)'' || ''\\n'';

    -- Golden record array coverage
    SELECT
        SUM(CASE WHEN ALL_EMAILS    IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN ALL_PHONES    IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN ALL_ADDRESSES IS NOT NULL THEN 1 ELSE 0 END)
    INTO :v_gr_with_emails, :v_gr_with_phones, :v_gr_with_addresses
    FROM MDM_DB.GOLD.GOLDEN_RECORDS
    WHERE _IS_ACTIVE = TRUE;

    report := report ||
        ''\\n--- GOLDEN RECORD ARRAY COVERAGE ---'' || ''\\n'' ||
        ''With emails:    '' || v_gr_with_emails    || '' / '' || v_golden_records ||
            '' ('' || CASE WHEN v_golden_records > 0 THEN ROUND(v_gr_with_emails    * 100.0 / v_golden_records, 1)::VARCHAR ELSE ''0'' END || ''%)'' || ''\\n'' ||
        ''With phones:    '' || v_gr_with_phones    || '' / '' || v_golden_records ||
            '' ('' || CASE WHEN v_golden_records > 0 THEN ROUND(v_gr_with_phones    * 100.0 / v_golden_records, 1)::VARCHAR ELSE ''0'' END || ''%)'' || ''\\n'' ||
        ''With addresses: '' || v_gr_with_addresses || '' / '' || v_golden_records ||
            '' ('' || CASE WHEN v_golden_records > 0 THEN ROUND(v_gr_with_addresses * 100.0 / v_golden_records, 1)::VARCHAR ELSE ''0'' END || ''%)'' || ''\\n'';

    -- Match group status distribution
    SELECT COUNT(*) INTO :v_status_auto    FROM MDM_DB.MDM.MATCH_GROUPS WHERE STATUS = ''Auto-Approved'';
    SELECT COUNT(*) INTO :v_status_pending FROM MDM_DB.MDM.MATCH_GROUPS WHERE STATUS = ''Pending Review'';
    SELECT COUNT(*) INTO :v_status_low     FROM MDM_DB.MDM.MATCH_GROUPS WHERE STATUS = ''Low Confidence'';

    report := report ||
        ''\\n--- MATCH GROUP STATUS ---'' || ''\\n'' ||
        ''Auto-Approved:  '' || v_status_auto    || ''\\n'' ||
        ''Pending Review: '' || v_status_pending || ''\\n'' ||
        ''Low Confidence: '' || v_status_low     || ''\\n'';

    -- Match method distribution
    SELECT
        COALESCE(SUM(CASE WHEN MATCH_METHOD = ''EXACT_EMAIL''          THEN 1 ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN MATCH_METHOD = ''EXACT_PHONE''          THEN 1 ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN MATCH_METHOD = ''EXACT_NAME_POSTCODE''  THEN 1 ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN MATCH_METHOD = ''FUZZY_NAME_ADDRESS''   THEN 1 ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN MATCH_METHOD = ''EXACT_NAME''           THEN 1 ELSE 0 END), 0)
    INTO :v_method_exact_email, :v_method_exact_phone, :v_method_exact_name_postcode,
         :v_method_fuzzy_name_address, :v_method_exact_name
    FROM MDM_DB.STAGING.MATCH_CANDIDATES;

    report := report ||
        ''\\n--- MATCH METHOD DISTRIBUTION ---'' || ''\\n'' ||
        ''EXACT_EMAIL:          '' || v_method_exact_email         || ''\\n'' ||
        ''EXACT_PHONE:          '' || v_method_exact_phone         || ''\\n'' ||
        ''EXACT_NAME_POSTCODE:  '' || v_method_exact_name_postcode || ''\\n'' ||
        ''FUZZY_NAME_ADDRESS:   '' || v_method_fuzzy_name_address  || ''\\n'' ||
        ''EXACT_NAME:           '' || v_method_exact_name          || ''\\n'';

    -- Check 1: Orphans
    SELECT COUNT(*) INTO :v_orphan_count
    FROM MDM_DB.STAGING.STANDARDISED_RECORDS
    WHERE _IS_ACTIVE = TRUE AND GOLDEN_RECORD_ID IS NULL;

    report := report ||
        ''\\n--- QUALITY CHECKS ---'' || ''\\n'' ||
        ''1. Orphan records (no golden record): '' || v_orphan_count ||
            CASE WHEN v_orphan_count = 0 THEN '' [PASS]'' ELSE '' [WARN]'' END || ''\\n'';

    -- Check 2: Cross-source matches
    SELECT COUNT(*) INTO :v_cross_source_count
    FROM (
        SELECT mg.MATCH_GROUP_ID
        FROM MDM_DB.MDM.MATCH_GROUPS mg
        INNER JOIN MDM_DB.MDM.MATCH_GROUP_MEMBERS mgm ON mg.MATCH_GROUP_ID = mgm.MATCH_GROUP_ID
        GROUP BY mg.MATCH_GROUP_ID
        HAVING COUNT(DISTINCT mgm.SOURCE_SYSTEM) > 1
    );

    report := report ||
        ''2. Cross-source match groups:         '' || v_cross_source_count || ''\\n'';

    -- Check 3: Over-matching
    SELECT COUNT(*) INTO :v_overmatched_groups
    FROM MDM_DB.MDM.MATCH_GROUPS WHERE RECORD_COUNT >= 10;

    SELECT
        COALESCE(MAX(RECORD_COUNT), 0),
        COALESCE(MAX_BY(MATCH_GROUP_ID, RECORD_COUNT), ''N/A'')
    INTO :v_largest_group_size, :v_largest_group_id
    FROM MDM_DB.MDM.MATCH_GROUPS;

    report := report ||
        ''3. Over-matched groups (10+ members):  '' || v_overmatched_groups ||
            CASE WHEN v_overmatched_groups = 0 THEN '' [PASS]'' ELSE '' [WARN]'' END || ''\\n'' ||
        ''   Largest group: '' || v_largest_group_id || '' ('' || v_largest_group_size || '' members)'' || ''\\n'';

    -- Check 4: Array integrity
    SELECT COUNT(*) INTO :v_array_mismatches
    FROM (
        SELECT sr.STANDARDISED_ID, ARRAY_AGG(e.VALUE:EMAIL::VARCHAR) AS EMAIL_LIST, sr.EMAIL
        FROM MDM_DB.STAGING.STANDARDISED_RECORDS sr,
            LATERAL FLATTEN(INPUT => sr.ALL_EMAILS) e
        WHERE sr._IS_ACTIVE = TRUE AND sr.EMAIL IS NOT NULL AND sr.ALL_EMAILS IS NOT NULL
        GROUP BY sr.STANDARDISED_ID, sr.EMAIL
    ) sub
    WHERE NOT ARRAY_CONTAINS(sub.EMAIL::VARIANT, sub.EMAIL_LIST);

    report := report ||
        ''4. Array integrity mismatches:          '' || v_array_mismatches ||
            CASE WHEN v_array_mismatches = 0 THEN '' [PASS]'' ELSE '' [FAIL]'' END || ''\\n'';

    report := report ||
        ''\\n========================================'' || ''\\n'' ||
        ''END OF REPORT''                             || ''\\n'' ||
        ''========================================'';

    RETURN report;
END;
';