CREATE OR REPLACE PROCEDURE MDM_DB.MDM.SP_VALIDATE_MDM()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    LET report                        VARCHAR := '''';
    LET v_active_records              INT := 0;
    LET v_inactive_standardised       INT := 0;
    LET v_inactive_golden             INT := 0;
    LET v_last_standardised_at        VARCHAR := ''N/A'';
    LET v_match_candidates            INT := 0;
    LET v_match_groups                INT := 0;
    LET v_match_group_members         INT := 0;
    LET v_golden_records              INT := 0;
    LET v_xref_links                  INT := 0;
    LET v_gr_with_emails              INT := 0;
    LET v_gr_with_phones              INT := 0;
    LET v_gr_with_addresses           INT := 0;
    LET v_domain_individual           INT := 0;
    LET v_domain_organisation         INT := 0;
    LET v_domain_other                INT := 0;
    LET v_no_contact                  INT := 0;
    LET v_orphan_count                INT := 0;
    LET v_overmatched_groups          INT := 0;
    LET v_largest_group_size          INT := 0;
    LET v_largest_group_id            VARCHAR := ''N/A'';
    LET v_array_mismatches            INT := 0;
    LET v_cross_source_count          INT := 0;
    LET v_dup_emails                  INT := 0;
    LET v_re_dup_xref                 INT := 0;
    LET v_sr_xref_mismatch            INT := 0;
    LET v_xref_inactive_gr            INT := 0;
    LET v_manually_edited             INT := 0;
    LET v_stale_pending               INT := 0;
    LET v_re_total                    INT := 0;
    LET v_re_matched                  INT := 0;
    LET v_hs_total                    INT := 0;
    LET v_hs_matched                  INT := 0;
    LET v_dyn_total                   INT := 0;
    LET v_dyn_matched                 INT := 0;
    LET v_dyn_dup_xref                INT := 0;
    LET v_linking_candidates          INT := 0;
    LET v_strong_candidates           INT := 0;
    LET v_proposals                   INT := 0;
    LET v_approved                    INT := 0;
    LET v_rejected                    INT := 0;
    LET v_method_groups               VARCHAR := '''';
    LET v_config_summary              VARCHAR := '''';
    LET v_split_links                 INT := 0;
    LET v_status_auto                INT := 0;
    LET v_status_pending              INT := 0;
    LET v_status_low                  INT := 0;

    -- Pipeline counts
    SELECT COUNT(*) INTO :v_active_records       FROM MDM_DB.STAGING.STANDARDISED_RECORDS WHERE _IS_ACTIVE = TRUE;
    SELECT COUNT(*) INTO :v_inactive_standardised FROM MDM_DB.STAGING.STANDARDISED_RECORDS WHERE _IS_ACTIVE = FALSE;
    SELECT COALESCE(MAX(_STANDARDISED_AT)::VARCHAR, ''N/A'') INTO :v_last_standardised_at FROM MDM_DB.STAGING.STANDARDISED_RECORDS;
    SELECT COUNT(*) INTO :v_match_candidates      FROM MDM_DB.STAGING.MATCH_CANDIDATES;
    SELECT COUNT(*) INTO :v_linking_candidates    FROM MDM_DB.STAGING.MATCH_CANDIDATES WHERE IS_LINKING;
    SELECT COUNT(*) INTO :v_strong_candidates     FROM MDM_DB.STAGING.MATCH_CANDIDATES WHERE IS_STRONG;
    SELECT COUNT(*) INTO :v_proposals             FROM MDM_DB.STAGING.MATCH_PROPOSALS;
    SELECT COUNT(*) INTO :v_approved              FROM MDM_DB.MDM.STEWARDSHIP_APPROVALS WHERE DECISION = ''APPROVED'';
    SELECT COUNT(*) INTO :v_rejected              FROM MDM_DB.MDM.STEWARDSHIP_APPROVALS WHERE DECISION = ''REJECTED'';
    SELECT COUNT(*) INTO :v_match_groups          FROM MDM_DB.MDM.MATCH_GROUPS;
    SELECT COUNT(*) INTO :v_match_group_members   FROM MDM_DB.MDM.MATCH_GROUP_MEMBERS;
    SELECT COUNT(*) INTO :v_golden_records        FROM MDM_DB.GOLD.GOLDEN_RECORDS WHERE _IS_ACTIVE = TRUE;
    SELECT COUNT(*) INTO :v_inactive_golden       FROM MDM_DB.GOLD.GOLDEN_RECORDS WHERE _IS_ACTIVE = FALSE;
    SELECT COUNT(*) INTO :v_xref_links            FROM MDM_DB.GOLD.XREF;

    report :=
        ''========================================'' || ''\\n'' ||
        ''MDM PIPELINE VALIDATION REPORT''           || ''\\n'' ||
        ''========================================''  || ''\\n'' ||
        ''Run at: '' || CURRENT_TIMESTAMP()::VARCHAR || ''\\n\\n'' ||
        ''--- PIPELINE SUMMARY ---''                 || ''\\n'' ||
        ''Last standardised at: '' || v_last_standardised_at   || ''\\n'' ||
        ''Active records:       '' || v_active_records          || ''\\n'' ||
        ''Inactive records:     '' || v_inactive_standardised   || ''\\n'' ||
        ''Match candidates:     '' || v_match_candidates        || '' ('' || v_linking_candidates || '' linking, '' || v_strong_candidates || '' strong)'' || ''\\n'' ||
        ''Open proposals:       '' || v_proposals               || ''\\n'' ||
        ''Steward decisions:    '' || v_approved || '' approved, '' || v_rejected || '' rejected'' || ''\\n'' ||
        ''Match groups:         '' || v_match_groups            || ''\\n'' ||
        ''Match group members:  '' || v_match_group_members     || ''\\n'' ||
        ''Golden records:       '' || v_golden_records          || ''\\n'' ||
        ''Inactive golden:      '' || v_inactive_golden         || ''\\n'' ||
        ''XREF links:           '' || v_xref_links              || ''\\n'';

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

    SELECT COUNT(*), SUM(CASE WHEN mc.STANDARDISED_ID IS NOT NULL THEN 1 ELSE 0 END)
    INTO :v_dyn_total, :v_dyn_matched
    FROM MDM_DB.STAGING.STANDARDISED_RECORDS sr
    LEFT JOIN MDM_DB.STAGING.MATCH_COMPONENTS mc ON sr.STANDARDISED_ID = mc.STANDARDISED_ID
    WHERE sr._IS_ACTIVE = TRUE AND sr.SOURCE_SYSTEM = ''DYNAMICS'';

    report := report ||
        ''\\n--- SOURCE COVERAGE ---'' || ''\\n'' ||
        ''Raisers Edge: '' || v_re_total || '' total, '' || v_re_matched || '' matched ('' ||
            CASE WHEN v_re_total > 0 THEN ROUND(v_re_matched * 100.0 / v_re_total, 1)::VARCHAR ELSE ''0'' END || ''%)'' || ''\\n'' ||
        ''HubSpot:      '' || v_hs_total || '' total, '' || v_hs_matched || '' matched ('' ||
            CASE WHEN v_hs_total > 0 THEN ROUND(v_hs_matched * 100.0 / v_hs_total, 1)::VARCHAR ELSE ''0'' END || ''%)'' || ''\\n'' ||
        ''Dynamics:     '' || v_dyn_total || '' total, '' || v_dyn_matched || '' matched ('' ||
            CASE WHEN v_dyn_total > 0 THEN ROUND(v_dyn_matched * 100.0 / v_dyn_total, 1)::VARCHAR ELSE ''0'' END || ''%)'' || ''\\n'';

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

    -- Domain breakdown
    SELECT
        COALESCE(SUM(CASE WHEN DOMAIN = ''INDIVIDUAL''   THEN 1 ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN DOMAIN = ''ORGANISATION'' THEN 1 ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN DOMAIN NOT IN (''INDIVIDUAL'', ''ORGANISATION'') OR DOMAIN IS NULL THEN 1 ELSE 0 END), 0)
    INTO :v_domain_individual, :v_domain_organisation, :v_domain_other
    FROM MDM_DB.GOLD.GOLDEN_RECORDS
    WHERE _IS_ACTIVE = TRUE;

    report := report ||
        ''\\n--- DOMAIN BREAKDOWN ---'' || ''\\n'' ||
        ''Individual:    '' || v_domain_individual   || ''\\n'' ||
        ''Organisation:  '' || v_domain_organisation || ''\\n'' ||
        ''Other/Unknown: '' || v_domain_other        || ''\\n'';

    -- Contactability
    SELECT COUNT(*) INTO :v_no_contact
    FROM MDM_DB.GOLD.GOLDEN_RECORDS
    WHERE _IS_ACTIVE = TRUE
      AND EMAIL IS NULL
      AND ALL_PHONES IS NULL
      AND ALL_ADDRESSES IS NULL;

    report := report ||
        ''\\n--- CONTACTABILITY ---'' || ''\\n'' ||
        ''No email, phone, or address: '' || v_no_contact || '' / '' || v_golden_records ||
            '' ('' || CASE WHEN v_golden_records > 0 THEN ROUND(v_no_contact * 100.0 / v_golden_records, 1)::VARCHAR ELSE ''0'' END || ''%)'' || ''\\n'';

    -- Match group status distribution
    SELECT COUNT(*) INTO :v_status_auto    FROM MDM_DB.MDM.MATCH_GROUPS WHERE STATUS = ''Auto-Approved'';
    SELECT COUNT(*) INTO :v_status_pending FROM MDM_DB.MDM.MATCH_GROUPS WHERE STATUS = ''Pending Review'';
    SELECT COUNT(*) INTO :v_status_low     FROM MDM_DB.MDM.MATCH_GROUPS WHERE STATUS = ''Low Confidence'';

    report := report ||
        ''\\n--- MATCH GROUP STATUS ---'' || ''\\n'' ||
        ''Auto-Approved:  '' || v_status_auto    || ''\\n'' ||
        ''Pending Review: '' || v_status_pending || ''\\n'' ||
        ''Low Confidence: '' || v_status_low     || ''\\n'';

    -- Match method distribution. Methods are labels built from the attributes that matched
    -- (for example EMAIL+POSTCODE+ADDRESS) or override names, so list what is in use rather
    -- than a fixed set. Counted per group, using the group''s main linking method.
    SELECT COALESCE(LISTAGG(LINE, ''\\n'') WITHIN GROUP (ORDER BY N DESC), ''(none)'')
    INTO :v_method_groups
    FROM (
        SELECT RPAD(MATCH_METHOD || '':'', 52) || COUNT(*) AS LINE, COUNT(*) AS N
        FROM MDM_DB.MDM.MATCH_GROUPS
        GROUP BY MATCH_METHOD
        ORDER BY COUNT(*) DESC
        LIMIT 15
    );

    report := report ||
        ''\\n--- MATCH METHOD DISTRIBUTION (groups, top 15) ---'' || ''\\n'' ||
        v_method_groups || ''\\n'';

    -- Scoring configuration that produced this run
    SELECT COALESCE(LISTAGG(PARAM || '' = '' || VALUE, ''\\n'') WITHIN GROUP (ORDER BY PARAM), ''(none)'')
    INTO :v_config_summary
    FROM MDM_DB.MDM.MATCH_CONFIG;

    report := report ||
        ''\\n--- MATCH SCORING CONFIG ---'' || ''\\n'' ||
        v_config_summary || ''\\n'';

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

    -- Check 5: Duplicate primary email across active golden records
    SELECT COUNT(*) INTO :v_dup_emails
    FROM (
        SELECT EMAIL
        FROM MDM_DB.GOLD.GOLDEN_RECORDS
        WHERE _IS_ACTIVE = TRUE AND EMAIL IS NOT NULL
        GROUP BY EMAIL
        HAVING COUNT(*) > 1
    );

    report := report ||
        ''5. Duplicate primary email across golden records: '' || v_dup_emails ||
            CASE WHEN v_dup_emails = 0 THEN '' [PASS]'' ELSE '' [FAIL]'' END || ''\\n'';

    -- Check 6: RE constituent ID in XREF more than once
    SELECT COUNT(*) INTO :v_re_dup_xref
    FROM (
        SELECT SOURCE_RECORD_ID
        FROM MDM_DB.GOLD.XREF
        WHERE SOURCE_SYSTEM = ''RAISERS_EDGE''
        GROUP BY SOURCE_RECORD_ID
        HAVING COUNT(*) > 1
    );

    report := report ||
        ''6. RE constituent IDs linked to multiple golden records: '' || v_re_dup_xref ||
            CASE WHEN v_re_dup_xref = 0 THEN '' [PASS]'' ELSE '' [FAIL]'' END || ''\\n'';

    -- Check 7: Active SR with GOLDEN_RECORD_ID but missing XREF entry
    SELECT COUNT(*) INTO :v_sr_xref_mismatch
    FROM MDM_DB.STAGING.STANDARDISED_RECORDS sr
    WHERE sr._IS_ACTIVE = TRUE
      AND sr.GOLDEN_RECORD_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM MDM_DB.GOLD.XREF x
          WHERE x.STANDARDISED_ID = sr.STANDARDISED_ID
      );

    report := report ||
        ''7. SR with golden record but no XREF entry: '' || v_sr_xref_mismatch ||
            CASE WHEN v_sr_xref_mismatch = 0 THEN '' [PASS]'' ELSE '' [FAIL]'' END || ''\\n'';

    -- Check 8: XREF pointing to an inactive golden record
    SELECT COUNT(*) INTO :v_xref_inactive_gr
    FROM MDM_DB.GOLD.XREF x
    INNER JOIN MDM_DB.GOLD.GOLDEN_RECORDS gr ON x.GOLDEN_RECORD_ID = gr.GOLDEN_RECORD_ID
    WHERE gr._IS_ACTIVE = FALSE;

    report := report ||
        ''8. XREF entries pointing to inactive golden records: '' || v_xref_inactive_gr ||
            CASE WHEN v_xref_inactive_gr = 0 THEN '' [PASS]'' ELSE '' [WARN]'' END || ''\\n'';

    -- Check 9: Dynamics SOURCE_RECORD_ID in XREF more than once
    SELECT COUNT(*) INTO :v_dyn_dup_xref
    FROM (
        SELECT SOURCE_RECORD_ID
        FROM MDM_DB.GOLD.XREF
        WHERE SOURCE_SYSTEM = ''DYNAMICS''
        GROUP BY SOURCE_RECORD_ID
        HAVING COUNT(*) > 1
    );

    report := report ||
        ''9. Dynamics SOURCE_RECORD_IDs linked to multiple golden records: '' || v_dyn_dup_xref ||
            CASE WHEN v_dyn_dup_xref = 0 THEN '' [PASS]'' ELSE '' [FAIL]'' END || ''\\n'';

    -- Check 10: every strong edge should have both records in the same match group
    SELECT COUNT(*) INTO :v_split_links
    FROM MDM_DB.STAGING.MATCH_CANDIDATES c
    INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS a ON a.STANDARDISED_ID = c.STANDARDISED_ID_A
    INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS b ON b.STANDARDISED_ID = c.STANDARDISED_ID_B
    WHERE c.IS_STRONG AND a.MATCH_GROUP_ID <> b.MATCH_GROUP_ID;

    report := report ||
        ''10. Strong edges split across groups: '' || v_split_links ||
            CASE WHEN v_split_links = 0 THEN '' [PASS]'' ELSE '' [FAIL]'' END || ''\\n'';

    -- Stewardship health
    SELECT COUNT(*) INTO :v_manually_edited
    FROM MDM_DB.GOLD.GOLDEN_RECORDS
    WHERE _IS_ACTIVE = TRUE AND IS_MANUALLY_EDITED = TRUE;

    SELECT COUNT(*) INTO :v_stale_pending
    FROM MDM_DB.MDM.MATCH_GROUPS
    WHERE STATUS = ''Pending Review''
      AND CREATED_AT < DATEADD(''day'', -30, CURRENT_TIMESTAMP());

    report := report ||
        ''\\n--- STEWARDSHIP HEALTH ---'' || ''\\n'' ||
        ''Manually edited golden records:       '' || v_manually_edited || ''\\n'' ||
        ''Pending Review groups older than 30d: '' || v_stale_pending   ||
            CASE WHEN v_stale_pending = 0 THEN '' [PASS]'' ELSE '' [WARN]'' END || ''\\n'';

    report := report ||
        ''\\n========================================'' || ''\\n'' ||
        ''END OF REPORT''                             || ''\\n'' ||
        ''========================================'';

    RETURN report;
END;
';