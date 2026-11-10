CREATE OR REPLACE PROCEDURE MDM_DB.GOLD.SP_GENERATE_GOLDEN_RECORDS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
-- Field-level survivorship uses recency-only ranking (MOST_RECENT / RECENCY_RANK).
-- STRATEGY MOST_RECENT   -> latest LAST_UPDATED (RECENCY_RANK).
-- STRATEGY MOST_COMPLETE -> fewest null/empty key fields (COMPLETENESS_RANK).
-- Equal LAST_UPDATED is broken deterministically by STANDARDISED_ID ASC (source-neutral).
-- SOURCE_PRIORITY_RANK is removed; no source has preference over any other.
-- Changes to the seed must land in the same DLSync deploy as changes to this SP.
BEGIN
    LET rows_golden        INT := 0;
    LET rows_deactivated   INT := 0;
    LET rows_merge_losers  INT := 0;
    LET rows_xref          INT := 0;
    LET rows_xref_pruned   INT := 0;
    LET rows_split_pruned  INT := 0;
    LET rows_backfill      INT := 0;
    MERGE INTO MDM_DB.GOLD.GOLDEN_RECORDS tgt
    USING (
        WITH strong_group_ids AS (
            -- Only Auto-Approved, Approved, and Pending Review groups are fused.
            -- Low Confidence groups are excluded; their members fall through to the singleton branch.
            SELECT MATCH_GROUP_ID FROM MDM_DB.MDM.MATCH_GROUPS
            WHERE STATUS IN (''Auto-Approved'', ''Approved'', ''Pending Review'')
        ),
        singleton_ids AS (
            -- Records not assigned to any strong-status group become individual golden records.
            -- This includes true singletons and members of Low Confidence groups.
            SELECT sr.STANDARDISED_ID
            FROM MDM_DB.STAGING.STANDARDISED_RECORDS sr
            WHERE sr._IS_ACTIVE = TRUE
              AND sr.STANDARDISED_ID NOT IN (
                  SELECT mc.STANDARDISED_ID FROM MDM_DB.STAGING.MATCH_COMPONENTS mc
                  WHERE mc.MATCH_GROUP_ID IN (SELECT MATCH_GROUP_ID FROM strong_group_ids)
              )
        ),
        matched_source_systems AS (
            SELECT mgm.MATCH_GROUP_ID,
                ARRAY_UNIQUE_AGG(sr.SOURCE_SYSTEM)  AS SOURCE_SYSTEMS,
                COUNT(*)                             AS SOURCE_RECORD_COUNT,
                BOOLOR_AGG(sr.FOUR_YEAR_RULE)        AS FOUR_YEAR
            FROM MDM_DB.MDM.MATCH_GROUP_MEMBERS mgm
            INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
                ON mgm.STANDARDISED_ID = sr.STANDARDISED_ID AND sr._IS_ACTIVE = TRUE
            GROUP BY mgm.MATCH_GROUP_ID
        ),
        all_group_emails AS (
            SELECT mc.MATCH_GROUP_ID, ARRAY_UNIQUE_AGG(e.VALUE) AS ALL_EMAILS
            FROM MDM_DB.STAGING.MATCH_COMPONENTS mc
            INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
                ON mc.STANDARDISED_ID = sr.STANDARDISED_ID AND sr._IS_ACTIVE = TRUE,
                LATERAL FLATTEN(INPUT => sr.ALL_EMAILS, OUTER => TRUE) e
            WHERE sr.ALL_EMAILS IS NOT NULL
            GROUP BY mc.MATCH_GROUP_ID
        ),
        all_group_phones AS (
            SELECT mc.MATCH_GROUP_ID, ARRAY_UNIQUE_AGG(p.VALUE) AS ALL_PHONES
            FROM MDM_DB.STAGING.MATCH_COMPONENTS mc
            INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
                ON mc.STANDARDISED_ID = sr.STANDARDISED_ID AND sr._IS_ACTIVE = TRUE,
                LATERAL FLATTEN(INPUT => sr.ALL_PHONES, OUTER => TRUE) p
            WHERE sr.ALL_PHONES IS NOT NULL
            GROUP BY mc.MATCH_GROUP_ID
        ),
        all_group_addresses AS (
            SELECT mc.MATCH_GROUP_ID, ARRAY_UNIQUE_AGG(a.VALUE) AS ALL_ADDRESSES
            FROM MDM_DB.STAGING.MATCH_COMPONENTS mc
            INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
                ON mc.STANDARDISED_ID = sr.STANDARDISED_ID AND sr._IS_ACTIVE = TRUE,
                LATERAL FLATTEN(INPUT => sr.ALL_ADDRESSES, OUTER => TRUE) a
            WHERE sr.ALL_ADDRESSES IS NOT NULL
            GROUP BY mc.MATCH_GROUP_ID
        ),
        members AS (
            SELECT
                mc.MATCH_GROUP_ID,
                sr.STANDARDISED_ID,
                sr.SOURCE_SYSTEM,
                sr.SOURCE_DOMAIN,
                sr.FULL_NAME,       sr.FIRST_NAME,    sr.LAST_NAME,
                sr.EMAIL,           sr.PHONE,
                sr.ADDRESS_LINE1,   sr.CITY,          sr.POSTCODE,    sr.COUNTRY,   sr.COUNTRY_ISO2,
                sr.MIDDLE_NAME,     sr.TITLE,         sr.TITLE_2,     sr.SUFFIX,    sr.SUFFIX_2,
                sr.GENDER,          sr.DATE_OF_BIRTH, sr.DECEASED,    sr.IS_MEMORIAL, sr.DATE_DECEASED,
                sr.LOOKUP_ID,
                sr.ADDRESS_LINE2,   sr.ADDRESS_LINE3, sr.ADDRESS_LINE4, sr.COUNTY,
                sr.HOME_PHONE,      sr.MOBILE_PHONE,  sr.WORK_PHONE,  sr.TELEPHONE,
                sr.LICENCED_USER_TYPE,   sr.PROFESSIONAL_WORK_SECTOR, sr.JOB_TITLE,
                sr.LEGACY_INTENDER, sr.LEGACY_PLEDGER, sr.LEGACY_CONSIDERER, sr.LEGACY_ENQUIRER,
                sr.IS_MAJOR_DONOR,  sr.IS_POLITICIAN, sr.IS_CELEBRITY,
                sr.IN_MEMORY_DONATION_HONOUREE, sr.IN_MEMORY_NEXT_OF_KIN,
                sr.BENEVOLENT_FAMILY, sr.IS_CORPORATE, sr.NAS_BRANCH_CONTACT, sr.PR_CASE_STUDY,
                sr.STATUTORY_AUTHORITY, sr.SPECIAL_EVENTER, sr.TRUSTS, sr.LEGACY_SUPPORTER,
                sr.SOLICIT_CODES,
                sr.FOUR_YEAR_RULE,
                sr.LAST_UPDATED,
                mg.MATCH_SCORE AS CONFIDENCE_SCORE
            FROM MDM_DB.MDM.MATCH_GROUP_MEMBERS mgm
            INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS mc
                ON mgm.MATCH_GROUP_ID = mc.MATCH_GROUP_ID AND mgm.STANDARDISED_ID = mc.STANDARDISED_ID
            INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
                ON mc.STANDARDISED_ID = sr.STANDARDISED_ID AND sr._IS_ACTIVE = TRUE
            INNER JOIN MDM_DB.MDM.MATCH_GROUPS mg ON mc.MATCH_GROUP_ID = mg.MATCH_GROUP_ID
            WHERE mg.STATUS IN (''Auto-Approved'', ''Approved'', ''Pending Review'')
            UNION ALL
            SELECT
                ''SG-'' || sr.STANDARDISED_ID AS MATCH_GROUP_ID,
                sr.STANDARDISED_ID,
                sr.SOURCE_SYSTEM,
                sr.SOURCE_DOMAIN,
                sr.FULL_NAME,       sr.FIRST_NAME,    sr.LAST_NAME,
                sr.EMAIL,           sr.PHONE,
                sr.ADDRESS_LINE1,   sr.CITY,          sr.POSTCODE,    sr.COUNTRY,   sr.COUNTRY_ISO2,
                sr.MIDDLE_NAME,     sr.TITLE,         sr.TITLE_2,     sr.SUFFIX,    sr.SUFFIX_2,
                sr.GENDER,          sr.DATE_OF_BIRTH, sr.DECEASED,    sr.IS_MEMORIAL, sr.DATE_DECEASED,
                sr.LOOKUP_ID,
                sr.ADDRESS_LINE2,   sr.ADDRESS_LINE3, sr.ADDRESS_LINE4, sr.COUNTY,
                sr.HOME_PHONE,      sr.MOBILE_PHONE,  sr.WORK_PHONE,  sr.TELEPHONE,
                sr.LICENCED_USER_TYPE,   sr.PROFESSIONAL_WORK_SECTOR, sr.JOB_TITLE,
                sr.LEGACY_INTENDER, sr.LEGACY_PLEDGER, sr.LEGACY_CONSIDERER, sr.LEGACY_ENQUIRER,
                sr.IS_MAJOR_DONOR,  sr.IS_POLITICIAN, sr.IS_CELEBRITY,
                sr.IN_MEMORY_DONATION_HONOUREE, sr.IN_MEMORY_NEXT_OF_KIN,
                sr.BENEVOLENT_FAMILY, sr.IS_CORPORATE, sr.NAS_BRANCH_CONTACT, sr.PR_CASE_STUDY,
                sr.STATUTORY_AUTHORITY, sr.SPECIAL_EVENTER, sr.TRUSTS, sr.LEGACY_SUPPORTER,
                sr.SOLICIT_CODES,
                sr.FOUR_YEAR_RULE,
                sr.LAST_UPDATED,
                100.0 AS CONFIDENCE_SCORE
            FROM MDM_DB.STAGING.STANDARDISED_RECORDS sr
            WHERE sr.STANDARDISED_ID IN (SELECT STANDARDISED_ID FROM singleton_ids)
        ),
        ranked AS (
            SELECT m.*,
                ROW_NUMBER() OVER (
                    PARTITION BY m.MATCH_GROUP_ID
                    ORDER BY m.LAST_UPDATED DESC NULLS LAST, m.STANDARDISED_ID ASC
                ) AS RECENCY_RANK,
                ROW_NUMBER() OVER (
                    PARTITION BY m.MATCH_GROUP_ID
                    ORDER BY (
                        CASE WHEN m.FULL_NAME     IS NULL OR m.FULL_NAME     = '''' THEN 1 ELSE 0 END +
                        CASE WHEN m.EMAIL         IS NULL OR m.EMAIL         = '''' THEN 1 ELSE 0 END +
                        CASE WHEN m.PHONE         IS NULL OR m.PHONE         = '''' THEN 1 ELSE 0 END +
                        CASE WHEN m.ADDRESS_LINE1 IS NULL OR m.ADDRESS_LINE1 = '''' THEN 1 ELSE 0 END +
                        CASE WHEN m.POSTCODE      IS NULL OR m.POSTCODE      = '''' THEN 1 ELSE 0 END
                    ) ASC,
                    m.LAST_UPDATED DESC NULLS LAST,
                    m.STANDARDISED_ID ASC
                ) AS COMPLETENESS_RANK
            FROM members m
        ),
        br AS (SELECT * FROM ranked WHERE RECENCY_RANK      = 1),
        bc AS (SELECT * FROM ranked WHERE COMPLETENESS_RANK = 1),
        cluster_existing_gr AS (
            -- For each current cluster, find golden records already associated with its members
            -- via XREF.  Used for carry-forward: the oldest such record wins (deterministic merge).
            SELECT mc.MATCH_GROUP_ID, gr.GOLDEN_RECORD_ID, gr.CREATED_AT
            FROM MDM_DB.STAGING.MATCH_COMPONENTS mc
            INNER JOIN MDM_DB.GOLD.XREF x ON mc.STANDARDISED_ID = x.STANDARDISED_ID
            INNER JOIN MDM_DB.GOLD.GOLDEN_RECORDS gr ON x.GOLDEN_RECORD_ID = gr.GOLDEN_RECORD_ID
            WHERE mc.MATCH_GROUP_ID IN (SELECT MATCH_GROUP_ID FROM strong_group_ids)
            UNION ALL
            SELECT ''SG-'' || si.STANDARDISED_ID AS MATCH_GROUP_ID, gr.GOLDEN_RECORD_ID, gr.CREATED_AT
            FROM singleton_ids si
            INNER JOIN MDM_DB.GOLD.XREF x ON si.STANDARDISED_ID = x.STANDARDISED_ID
            INNER JOIN MDM_DB.GOLD.GOLDEN_RECORDS gr ON x.GOLDEN_RECORD_ID = gr.GOLDEN_RECORD_ID
        ),
        cluster_survivor AS (
            -- One row per cluster: the golden record with the oldest CREATED_AT survives a merge.
            -- GOLDEN_RECORD_ID breaks CREATED_AT ties so the survivor is deterministic across runs.
            SELECT MATCH_GROUP_ID, GOLDEN_RECORD_ID, CREATED_AT
            FROM cluster_existing_gr
            QUALIFY ROW_NUMBER() OVER (PARTITION BY MATCH_GROUP_ID ORDER BY CREATED_AT ASC NULLS LAST, GOLDEN_RECORD_ID ASC) = 1
        ),
        gr_primary_owner AS (
            -- Each existing GR may be carried forward by exactly one match group.
            -- The group whose XREF link was created earliest wins; others mint a new sequence ID.
            SELECT MATCH_GROUP_ID, GOLDEN_RECORD_ID
            FROM cluster_survivor
            QUALIFY ROW_NUMBER() OVER (PARTITION BY GOLDEN_RECORD_ID ORDER BY CREATED_AT ASC NULLS LAST, MATCH_GROUP_ID ASC) = 1
        ),
        resolved_golden_ids AS (
            -- Carry forward an existing golden ID if one exists; otherwise mint a new sequence ID.
            -- NEXTVAL is consumed per row but only the COALESCE result is used.
            SELECT
                br.MATCH_GROUP_ID,
                COALESCE(
                    gpo.GOLDEN_RECORD_ID,
                    ''GR-'' || MDM_DB.GOLD.SEQ_GOLDEN_RECORD_ID.NEXTVAL
                ) AS GOLDEN_RECORD_ID
            FROM br
            LEFT JOIN gr_primary_owner gpo ON br.MATCH_GROUP_ID = gpo.MATCH_GROUP_ID
        )
        SELECT
            rgi.GOLDEN_RECORD_ID                                                                              AS GOLDEN_RECORD_ID,
            br.SOURCE_DOMAIN                                                                                  AS DOMAIN,
            COALESCE(NULLIF(br.FULL_NAME, ''''),       NULLIF(bc.FULL_NAME, ''''))       AS FULL_NAME,
            COALESCE(NULLIF(br.FIRST_NAME, ''''),      NULLIF(bc.FIRST_NAME, ''''))      AS FIRST_NAME,
            COALESCE(NULLIF(br.LAST_NAME, ''''),       NULLIF(bc.LAST_NAME, ''''))       AS LAST_NAME,
            COALESCE(NULLIF(br.EMAIL, ''''),           NULLIF(bc.EMAIL, ''''))           AS EMAIL,
            COALESCE(NULLIF(br.PHONE, ''''),           NULLIF(bc.PHONE, ''''))           AS PHONE,
            COALESCE(NULLIF(br.ADDRESS_LINE1, ''''),   NULLIF(bc.ADDRESS_LINE1, ''''))   AS ADDRESS_LINE1,
            COALESCE(NULLIF(br.CITY, ''''),            NULLIF(bc.CITY, ''''))            AS CITY,
            COALESCE(NULLIF(br.POSTCODE, ''''),        NULLIF(bc.POSTCODE, ''''))        AS POSTCODE,
            COALESCE(NULLIF(br.COUNTRY, ''''),         NULLIF(bc.COUNTRY, ''''))         AS COUNTRY,
            COALESCE(NULLIF(br.COUNTRY_ISO2, ''''),    NULLIF(bc.COUNTRY_ISO2, ''''))    AS COUNTRY_ISO2,
            COALESCE(age.ALL_EMAILS,    surv_sr.ALL_EMAILS)                          AS ALL_EMAILS,
            COALESCE(agp.ALL_PHONES,    surv_sr.ALL_PHONES)                          AS ALL_PHONES,
            COALESCE(aga.ALL_ADDRESSES, surv_sr.ALL_ADDRESSES)                       AS ALL_ADDRESSES,
            COALESCE(mss.SOURCE_SYSTEMS, ARRAY_CONSTRUCT(ss.SOURCE_SYSTEM))          AS SOURCE_SYSTEMS,
            COALESCE(mss.SOURCE_RECORD_COUNT, 1)                                     AS SOURCE_RECORD_COUNT,
            br.CONFIDENCE_SCORE,
            br.MATCH_GROUP_ID,
            br.LAST_UPDATED,
            COALESCE(mss.FOUR_YEAR, br.FOUR_YEAR_RULE)                               AS FOUR_YEAR,
            COALESCE(NULLIF(br.MIDDLE_NAME, ''''),     NULLIF(bc.MIDDLE_NAME, ''''))     AS MIDDLE_NAME,
            COALESCE(NULLIF(br.TITLE, ''''),           NULLIF(bc.TITLE, ''''))           AS TITLE,
            COALESCE(NULLIF(br.TITLE_2, ''''),         NULLIF(bc.TITLE_2, ''''))         AS TITLE_2,
            COALESCE(NULLIF(br.SUFFIX, ''''),          NULLIF(bc.SUFFIX, ''''))          AS SUFFIX,
            COALESCE(NULLIF(br.SUFFIX_2, ''''),        NULLIF(bc.SUFFIX_2, ''''))        AS SUFFIX_2,
            COALESCE(NULLIF(br.GENDER, ''''),          NULLIF(bc.GENDER, ''''))          AS GENDER,
            COALESCE(NULLIF(br.DATE_OF_BIRTH, ''''),   NULLIF(bc.DATE_OF_BIRTH, ''''))   AS DATE_OF_BIRTH,
            COALESCE(br.DECEASED,                    bc.DECEASED)                    AS DECEASED,
            COALESCE(br.IS_MEMORIAL,                 bc.IS_MEMORIAL)                 AS IS_MEMORIAL,
            COALESCE(NULLIF(br.DATE_DECEASED, ''''),   NULLIF(bc.DATE_DECEASED, ''''))   AS DATE_DECEASED,
            COALESCE(NULLIF(br.LOOKUP_ID, ''''),       NULLIF(bc.LOOKUP_ID, ''''))       AS LOOKUP_ID,
            COALESCE(NULLIF(br.ADDRESS_LINE2, ''''),   NULLIF(bc.ADDRESS_LINE2, ''''))   AS ADDRESS_LINE2,
            COALESCE(NULLIF(br.ADDRESS_LINE3, ''''),   NULLIF(bc.ADDRESS_LINE3, ''''))   AS ADDRESS_LINE3,
            COALESCE(NULLIF(br.ADDRESS_LINE4, ''''),   NULLIF(bc.ADDRESS_LINE4, ''''))   AS ADDRESS_LINE4,
            COALESCE(NULLIF(br.COUNTY, ''''),          NULLIF(bc.COUNTY, ''''))          AS COUNTY,
            COALESCE(NULLIF(br.HOME_PHONE, ''''),      NULLIF(bc.HOME_PHONE, ''''))      AS HOME_PHONE,
            COALESCE(NULLIF(br.MOBILE_PHONE, ''''),    NULLIF(bc.MOBILE_PHONE, ''''))    AS MOBILE_PHONE,
            COALESCE(NULLIF(br.WORK_PHONE, ''''),      NULLIF(bc.WORK_PHONE, ''''))      AS WORK_PHONE,
            COALESCE(NULLIF(br.TELEPHONE, ''''),       NULLIF(bc.TELEPHONE, ''''))       AS TELEPHONE,
            COALESCE(NULLIF(br.LICENCED_USER_TYPE, ''''),        NULLIF(bc.LICENCED_USER_TYPE, ''''))        AS LICENCED_USER_TYPE,
            COALESCE(NULLIF(br.PROFESSIONAL_WORK_SECTOR, ''''), NULLIF(bc.PROFESSIONAL_WORK_SECTOR, '''')) AS PROFESSIONAL_WORK_SECTOR,
            COALESCE(NULLIF(br.JOB_TITLE, ''''),       NULLIF(bc.JOB_TITLE, ''''))       AS JOB_TITLE,
            COALESCE(NULLIF(br.LEGACY_INTENDER, ''''), NULLIF(bc.LEGACY_INTENDER, '''')) AS LEGACY_INTENDER,
            COALESCE(NULLIF(br.LEGACY_PLEDGER, ''''),  NULLIF(bc.LEGACY_PLEDGER, ''''))  AS LEGACY_PLEDGER,
            COALESCE(NULLIF(br.LEGACY_CONSIDERER, ''''), NULLIF(bc.LEGACY_CONSIDERER, '''')) AS LEGACY_CONSIDERER,
            COALESCE(NULLIF(br.LEGACY_ENQUIRER, ''''), NULLIF(bc.LEGACY_ENQUIRER, '''')) AS LEGACY_ENQUIRER,
            COALESCE(br.IS_MAJOR_DONOR,              bc.IS_MAJOR_DONOR)              AS IS_MAJOR_DONOR,
            COALESCE(br.IS_POLITICIAN,               bc.IS_POLITICIAN)               AS IS_POLITICIAN,
            COALESCE(br.IS_CELEBRITY,                bc.IS_CELEBRITY)                AS IS_CELEBRITY,
            COALESCE(br.IN_MEMORY_DONATION_HONOUREE, bc.IN_MEMORY_DONATION_HONOUREE) AS IN_MEMORY_DONATION_HONOUREE,
            COALESCE(br.IN_MEMORY_NEXT_OF_KIN,       bc.IN_MEMORY_NEXT_OF_KIN)       AS IN_MEMORY_NEXT_OF_KIN,
            COALESCE(br.BENEVOLENT_FAMILY,           bc.BENEVOLENT_FAMILY)           AS BENEVOLENT_FAMILY,
            COALESCE(br.IS_CORPORATE,                bc.IS_CORPORATE)                AS IS_CORPORATE,
            COALESCE(br.NAS_BRANCH_CONTACT,          bc.NAS_BRANCH_CONTACT)          AS NAS_BRANCH_CONTACT,
            COALESCE(br.PR_CASE_STUDY,               bc.PR_CASE_STUDY)               AS PR_CASE_STUDY,
            COALESCE(br.STATUTORY_AUTHORITY,         bc.STATUTORY_AUTHORITY)         AS STATUTORY_AUTHORITY,
            COALESCE(br.SPECIAL_EVENTER,             bc.SPECIAL_EVENTER)             AS SPECIAL_EVENTER,
            COALESCE(br.TRUSTS,                      bc.TRUSTS)                      AS TRUSTS,
            COALESCE(br.LEGACY_SUPPORTER,            bc.LEGACY_SUPPORTER)            AS LEGACY_SUPPORTER,
            COALESCE(NULLIF(br.SOLICIT_CODES, ''''),   NULLIF(bc.SOLICIT_CODES, ''''))   AS SOLICIT_CODES
        FROM br
        JOIN bc  ON bc.MATCH_GROUP_ID  = br.MATCH_GROUP_ID
        JOIN resolved_golden_ids rgi ON rgi.MATCH_GROUP_ID = br.MATCH_GROUP_ID
        LEFT JOIN matched_source_systems mss ON br.MATCH_GROUP_ID = mss.MATCH_GROUP_ID
        LEFT JOIN all_group_emails    age ON br.MATCH_GROUP_ID = age.MATCH_GROUP_ID
        LEFT JOIN all_group_phones    agp ON br.MATCH_GROUP_ID = agp.MATCH_GROUP_ID
        LEFT JOIN all_group_addresses aga ON br.MATCH_GROUP_ID = aga.MATCH_GROUP_ID
        LEFT JOIN MDM_DB.STAGING.STANDARDISED_RECORDS surv_sr
            ON br.STANDARDISED_ID = surv_sr.STANDARDISED_ID
            AND surv_sr._IS_ACTIVE = TRUE
            AND age.MATCH_GROUP_ID IS NULL
        LEFT JOIN (
            SELECT STANDARDISED_ID, SOURCE_SYSTEM
            FROM MDM_DB.STAGING.STANDARDISED_RECORDS
            WHERE _IS_ACTIVE = TRUE
        ) ss ON br.STANDARDISED_ID = ss.STANDARDISED_ID AND mss.MATCH_GROUP_ID IS NULL
    ) src
    ON tgt.GOLDEN_RECORD_ID = src.GOLDEN_RECORD_ID
    WHEN MATCHED AND tgt.IS_MANUALLY_EDITED = FALSE THEN UPDATE SET
        tgt.DOMAIN                      = src.DOMAIN,
        tgt.FULL_NAME                   = src.FULL_NAME,
        tgt.FIRST_NAME                  = src.FIRST_NAME,
        tgt.LAST_NAME                   = src.LAST_NAME,
        tgt.EMAIL                       = src.EMAIL,
        tgt.PHONE                       = src.PHONE,
        tgt.ADDRESS_LINE1               = src.ADDRESS_LINE1,
        tgt.CITY                        = src.CITY,
        tgt.POSTCODE                    = src.POSTCODE,
        tgt.COUNTRY                     = src.COUNTRY,
        tgt.COUNTRY_ISO2                = src.COUNTRY_ISO2,
        tgt.ALL_EMAILS                  = src.ALL_EMAILS,
        tgt.ALL_PHONES                  = src.ALL_PHONES,
        tgt.ALL_ADDRESSES               = src.ALL_ADDRESSES,
        tgt.SOURCE_SYSTEMS              = src.SOURCE_SYSTEMS,
        tgt.SOURCE_RECORD_COUNT         = src.SOURCE_RECORD_COUNT,
        tgt.CONFIDENCE_SCORE            = src.CONFIDENCE_SCORE,
        tgt.MATCH_GROUP_ID              = src.MATCH_GROUP_ID,
        tgt.LAST_UPDATED                = CURRENT_TIMESTAMP(),
        tgt._IS_ACTIVE                  = TRUE,
        tgt.FOUR_YEAR                   = src.FOUR_YEAR,
        tgt.MIDDLE_NAME                 = src.MIDDLE_NAME,
        tgt.TITLE                       = src.TITLE,
        tgt.TITLE_2                     = src.TITLE_2,
        tgt.SUFFIX                      = src.SUFFIX,
        tgt.SUFFIX_2                    = src.SUFFIX_2,
        tgt.GENDER                      = src.GENDER,
        tgt.DATE_OF_BIRTH               = src.DATE_OF_BIRTH,
        tgt.DECEASED                    = src.DECEASED,
        tgt.IS_MEMORIAL                 = src.IS_MEMORIAL,
        tgt.DATE_DECEASED               = src.DATE_DECEASED,
        tgt.LOOKUP_ID                   = src.LOOKUP_ID,
        tgt.ADDRESS_LINE2               = src.ADDRESS_LINE2,
        tgt.ADDRESS_LINE3               = src.ADDRESS_LINE3,
        tgt.ADDRESS_LINE4               = src.ADDRESS_LINE4,
        tgt.COUNTY                      = src.COUNTY,
        tgt.HOME_PHONE                  = src.HOME_PHONE,
        tgt.MOBILE_PHONE                = src.MOBILE_PHONE,
        tgt.WORK_PHONE                  = src.WORK_PHONE,
        tgt.TELEPHONE                   = src.TELEPHONE,
        tgt.LICENCED_USER_TYPE          = src.LICENCED_USER_TYPE,
        tgt.PROFESSIONAL_WORK_SECTOR    = src.PROFESSIONAL_WORK_SECTOR,
        tgt.JOB_TITLE                   = src.JOB_TITLE,
        tgt.LEGACY_INTENDER             = src.LEGACY_INTENDER,
        tgt.LEGACY_PLEDGER              = src.LEGACY_PLEDGER,
        tgt.LEGACY_CONSIDERER           = src.LEGACY_CONSIDERER,
        tgt.LEGACY_ENQUIRER             = src.LEGACY_ENQUIRER,
        tgt.IS_MAJOR_DONOR              = src.IS_MAJOR_DONOR,
        tgt.IS_POLITICIAN               = src.IS_POLITICIAN,
        tgt.IS_CELEBRITY                = src.IS_CELEBRITY,
        tgt.IN_MEMORY_DONATION_HONOUREE = src.IN_MEMORY_DONATION_HONOUREE,
        tgt.IN_MEMORY_NEXT_OF_KIN       = src.IN_MEMORY_NEXT_OF_KIN,
        tgt.BENEVOLENT_FAMILY           = src.BENEVOLENT_FAMILY,
        tgt.IS_CORPORATE                = src.IS_CORPORATE,
        tgt.NAS_BRANCH_CONTACT          = src.NAS_BRANCH_CONTACT,
        tgt.PR_CASE_STUDY               = src.PR_CASE_STUDY,
        tgt.STATUTORY_AUTHORITY         = src.STATUTORY_AUTHORITY,
        tgt.SPECIAL_EVENTER             = src.SPECIAL_EVENTER,
        tgt.TRUSTS                      = src.TRUSTS,
        tgt.LEGACY_SUPPORTER            = src.LEGACY_SUPPORTER,
        tgt.SOLICIT_CODES               = src.SOLICIT_CODES
    WHEN NOT MATCHED THEN INSERT (
        GOLDEN_RECORD_ID, DOMAIN, FULL_NAME, FIRST_NAME, LAST_NAME, EMAIL, PHONE,
        ADDRESS_LINE1, CITY, POSTCODE, COUNTRY, COUNTRY_ISO2,
        ALL_EMAILS, ALL_PHONES, ALL_ADDRESSES,
        SOURCE_SYSTEMS, SOURCE_RECORD_COUNT, CONFIDENCE_SCORE, MATCH_GROUP_ID,
        CREATED_AT, LAST_UPDATED, _IS_ACTIVE,
        FOUR_YEAR,
        MIDDLE_NAME, TITLE, TITLE_2, SUFFIX, SUFFIX_2,
        GENDER, DATE_OF_BIRTH, DECEASED, IS_MEMORIAL, DATE_DECEASED,
        LOOKUP_ID, ADDRESS_LINE2, ADDRESS_LINE3, ADDRESS_LINE4, COUNTY,
        HOME_PHONE, MOBILE_PHONE, WORK_PHONE, TELEPHONE,
        LICENCED_USER_TYPE, PROFESSIONAL_WORK_SECTOR, JOB_TITLE,
        LEGACY_INTENDER, LEGACY_PLEDGER, LEGACY_CONSIDERER, LEGACY_ENQUIRER,
        IS_MAJOR_DONOR, IS_POLITICIAN, IS_CELEBRITY,
        IN_MEMORY_DONATION_HONOUREE, IN_MEMORY_NEXT_OF_KIN,
        BENEVOLENT_FAMILY, IS_CORPORATE, NAS_BRANCH_CONTACT, PR_CASE_STUDY,
        STATUTORY_AUTHORITY, SPECIAL_EVENTER, TRUSTS, LEGACY_SUPPORTER,
        SOLICIT_CODES
    ) VALUES (
        src.GOLDEN_RECORD_ID, src.DOMAIN, src.FULL_NAME, src.FIRST_NAME, src.LAST_NAME, src.EMAIL, src.PHONE,
        src.ADDRESS_LINE1, src.CITY, src.POSTCODE, src.COUNTRY, src.COUNTRY_ISO2,
        src.ALL_EMAILS, src.ALL_PHONES, src.ALL_ADDRESSES,
        src.SOURCE_SYSTEMS, src.SOURCE_RECORD_COUNT, src.CONFIDENCE_SCORE, src.MATCH_GROUP_ID,
        CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), TRUE,
        src.FOUR_YEAR,
        src.MIDDLE_NAME, src.TITLE, src.TITLE_2, src.SUFFIX, src.SUFFIX_2,
        src.GENDER, src.DATE_OF_BIRTH, src.DECEASED, src.IS_MEMORIAL, src.DATE_DECEASED,
        src.LOOKUP_ID, src.ADDRESS_LINE2, src.ADDRESS_LINE3, src.ADDRESS_LINE4, src.COUNTY,
        src.HOME_PHONE, src.MOBILE_PHONE, src.WORK_PHONE, src.TELEPHONE,
        src.LICENCED_USER_TYPE, src.PROFESSIONAL_WORK_SECTOR, src.JOB_TITLE,
        src.LEGACY_INTENDER, src.LEGACY_PLEDGER, src.LEGACY_CONSIDERER, src.LEGACY_ENQUIRER,
        src.IS_MAJOR_DONOR, src.IS_POLITICIAN, src.IS_CELEBRITY,
        src.IN_MEMORY_DONATION_HONOUREE, src.IN_MEMORY_NEXT_OF_KIN,
        src.BENEVOLENT_FAMILY, src.IS_CORPORATE, src.NAS_BRANCH_CONTACT, src.PR_CASE_STUDY,
        src.STATUTORY_AUTHORITY, src.SPECIAL_EVENTER, src.TRUSTS, src.LEGACY_SUPPORTER,
        src.SOLICIT_CODES
    );
    rows_golden := SQLROWCOUNT;

    UPDATE MDM_DB.GOLD.GOLDEN_RECORDS
    SET _IS_ACTIVE = FALSE, LAST_UPDATED = CURRENT_TIMESTAMP()
    WHERE _IS_ACTIVE = TRUE AND IS_MANUALLY_EDITED = FALSE
        AND MATCH_GROUP_ID NOT IN (
            SELECT MATCH_GROUP_ID FROM MDM_DB.MDM.MATCH_GROUPS
            WHERE STATUS IN (''Auto-Approved'', ''Approved'', ''Pending Review'')
            UNION ALL
            SELECT ''SG-'' || sr.STANDARDISED_ID
            FROM MDM_DB.STAGING.STANDARDISED_RECORDS sr
            WHERE sr._IS_ACTIVE = TRUE
              AND sr.STANDARDISED_ID NOT IN (
                  SELECT mc.STANDARDISED_ID FROM MDM_DB.STAGING.MATCH_COMPONENTS mc
                  WHERE mc.MATCH_GROUP_ID IN (
                      SELECT MATCH_GROUP_ID FROM MDM_DB.MDM.MATCH_GROUPS
                      WHERE STATUS IN (''Auto-Approved'', ''Approved'', ''Pending Review'')
                  )
              )
        );
    rows_deactivated := SQLROWCOUNT;

    -- Deactivate golden records superseded by a cluster merge. A loser is a pre-existing golden
    -- tied to a current cluster whose deterministic survivor (oldest CREATED_AT, lexical tiebreak)
    -- is a different golden record. The group-gone step above misses these: a merged cluster
    -- reuses one former group''s label, so the loser''s stale MATCH_GROUP_ID still resolves to a
    -- live group. This runs before the XREF prune so the loser''s stale links are then removed.
    UPDATE MDM_DB.GOLD.GOLDEN_RECORDS
    SET _IS_ACTIVE = FALSE, LAST_UPDATED = CURRENT_TIMESTAMP()
    WHERE _IS_ACTIVE = TRUE
        AND IS_MANUALLY_EDITED = FALSE
        AND GOLDEN_RECORD_ID IN (
            WITH strong_group_ids AS (
                SELECT MATCH_GROUP_ID FROM MDM_DB.MDM.MATCH_GROUPS
                WHERE STATUS IN (''Auto-Approved'', ''Approved'', ''Pending Review'')
            ),
            singleton_ids AS (
                SELECT sr.STANDARDISED_ID
                FROM MDM_DB.STAGING.STANDARDISED_RECORDS sr
                WHERE sr._IS_ACTIVE = TRUE
                  AND sr.STANDARDISED_ID NOT IN (
                      SELECT mc.STANDARDISED_ID FROM MDM_DB.STAGING.MATCH_COMPONENTS mc
                      WHERE mc.MATCH_GROUP_ID IN (SELECT MATCH_GROUP_ID FROM strong_group_ids)
                  )
            ),
            cluster_existing_gr AS (
                SELECT mc.MATCH_GROUP_ID, gr.GOLDEN_RECORD_ID, gr.CREATED_AT
                FROM MDM_DB.STAGING.MATCH_COMPONENTS mc
                INNER JOIN MDM_DB.GOLD.XREF x ON mc.STANDARDISED_ID = x.STANDARDISED_ID
                INNER JOIN MDM_DB.GOLD.GOLDEN_RECORDS gr ON x.GOLDEN_RECORD_ID = gr.GOLDEN_RECORD_ID
                WHERE mc.MATCH_GROUP_ID IN (SELECT MATCH_GROUP_ID FROM strong_group_ids)
                UNION ALL
                SELECT ''SG-'' || si.STANDARDISED_ID AS MATCH_GROUP_ID, gr.GOLDEN_RECORD_ID, gr.CREATED_AT
                FROM singleton_ids si
                INNER JOIN MDM_DB.GOLD.XREF x ON si.STANDARDISED_ID = x.STANDARDISED_ID
                INNER JOIN MDM_DB.GOLD.GOLDEN_RECORDS gr ON x.GOLDEN_RECORD_ID = gr.GOLDEN_RECORD_ID
            ),
            cluster_survivor AS (
                SELECT MATCH_GROUP_ID, GOLDEN_RECORD_ID, CREATED_AT
                FROM cluster_existing_gr
                QUALIFY ROW_NUMBER() OVER (PARTITION BY MATCH_GROUP_ID ORDER BY CREATED_AT ASC NULLS LAST, GOLDEN_RECORD_ID ASC) = 1
            )
            SELECT GOLDEN_RECORD_ID FROM cluster_existing_gr
            EXCEPT
            SELECT GOLDEN_RECORD_ID FROM cluster_survivor
        );
    rows_merge_losers := SQLROWCOUNT;

    MERGE INTO MDM_DB.GOLD.XREF tgt
    USING (
        SELECT gr.GOLDEN_RECORD_ID, sr.SOURCE_SYSTEM, sr.SOURCE_RECORD_ID, sr.STANDARDISED_ID
        FROM MDM_DB.GOLD.GOLDEN_RECORDS gr
        INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS mc ON gr.MATCH_GROUP_ID = mc.MATCH_GROUP_ID
        INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
            ON mc.STANDARDISED_ID = sr.STANDARDISED_ID AND sr._IS_ACTIVE = TRUE
        WHERE gr._IS_ACTIVE = TRUE
            AND sr.SOURCE_RECORD_ID IS NOT NULL
        UNION ALL
        SELECT gr.GOLDEN_RECORD_ID, sr.SOURCE_SYSTEM, sr.SOURCE_RECORD_ID, sr.STANDARDISED_ID
        FROM MDM_DB.GOLD.GOLDEN_RECORDS gr
        INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
            ON gr.MATCH_GROUP_ID = ''SG-'' || sr.STANDARDISED_ID AND sr._IS_ACTIVE = TRUE
        WHERE gr._IS_ACTIVE = TRUE AND gr.MATCH_GROUP_ID LIKE ''SG-%''
            AND sr.SOURCE_RECORD_ID IS NOT NULL
    ) src
    ON tgt.GOLDEN_RECORD_ID = src.GOLDEN_RECORD_ID
        AND tgt.SOURCE_SYSTEM = src.SOURCE_SYSTEM
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
    WHEN MATCHED THEN UPDATE SET
        tgt.STANDARDISED_ID = src.STANDARDISED_ID,
        tgt.LINKED_AT       = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (
        GOLDEN_RECORD_ID, SOURCE_SYSTEM, SOURCE_RECORD_ID, STANDARDISED_ID, LINKED_AT, LINKED_BY
    ) VALUES (
        src.GOLDEN_RECORD_ID, src.SOURCE_SYSTEM, src.SOURCE_RECORD_ID, src.STANDARDISED_ID, CURRENT_TIMESTAMP(), ''SYSTEM''
    );
    rows_xref := SQLROWCOUNT;

    -- Prune XREF links to inactive golden records (stale after a cluster merge).
    DELETE FROM MDM_DB.GOLD.XREF
    WHERE GOLDEN_RECORD_ID IN (
        SELECT GOLDEN_RECORD_ID FROM MDM_DB.GOLD.GOLDEN_RECORDS WHERE _IS_ACTIVE = FALSE
    );
    rows_xref_pruned := SQLROWCOUNT;

    -- Prune split-orphan XREF links: a standardised id that splits out of a former match group
    -- keeps a stale link to its old, still-active golden. The inactive-golden prune above misses
    -- these because that old golden is still active (carried forward by another group). Delete any
    -- link whose standardised id authoritatively resolves to a different active golden. The auth
    -- subquery mirrors the XREF MERGE src (active goldens via strong groups plus SG- singletons),
    -- so the surviving link is the one the MERGE just wrote. RE capture rows (STANDARDISED_ID IS
    -- NULL, LINKED_BY WRITEBACK/RE_WRITEBACK) cannot match the STANDARDISED_ID join, so they remain
    -- untouched. D365 capture rows (LINKED_BY D365_WRITEBACK) do set STANDARDISED_ID and are
    -- deliberately in scope for this prune: if a captured GUID''s golden record later splits away,
    -- the stale link is removed like any other, and ADF simply re-dispatches and recaptures it.
    -- Placed before the backfill UPDATE so its (SOURCE_SYSTEM, SOURCE_RECORD_ID) fan-out is resolved.
    DELETE FROM MDM_DB.GOLD.XREF t
    USING (
        SELECT sr.STANDARDISED_ID, gr.GOLDEN_RECORD_ID
        FROM MDM_DB.GOLD.GOLDEN_RECORDS gr
        INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS mc ON gr.MATCH_GROUP_ID = mc.MATCH_GROUP_ID
        INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
            ON mc.STANDARDISED_ID = sr.STANDARDISED_ID AND sr._IS_ACTIVE = TRUE
        WHERE gr._IS_ACTIVE = TRUE
        UNION ALL
        SELECT sr.STANDARDISED_ID, gr.GOLDEN_RECORD_ID
        FROM MDM_DB.GOLD.GOLDEN_RECORDS gr
        INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
            ON gr.MATCH_GROUP_ID = ''SG-'' || sr.STANDARDISED_ID AND sr._IS_ACTIVE = TRUE
        WHERE gr._IS_ACTIVE = TRUE AND gr.MATCH_GROUP_ID LIKE ''SG-%''
    ) auth
    WHERE t.STANDARDISED_ID = auth.STANDARDISED_ID
        AND t.GOLDEN_RECORD_ID <> auth.GOLDEN_RECORD_ID;
    rows_split_pruned := SQLROWCOUNT;

    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS sr
    SET sr.GOLDEN_RECORD_ID = xr.GOLDEN_RECORD_ID
    FROM MDM_DB.GOLD.XREF xr
    WHERE sr.SOURCE_SYSTEM = xr.SOURCE_SYSTEM
        AND sr.SOURCE_RECORD_ID = xr.SOURCE_RECORD_ID
        AND sr._IS_ACTIVE = TRUE;
    rows_backfill := SQLROWCOUNT;

    RETURN ''Golden records complete. Golden: '' || rows_golden || '', Deactivated: '' || rows_deactivated || '', Merge losers: '' || rows_merge_losers || '', XREF: '' || rows_xref || '', XREF pruned: '' || rows_xref_pruned || '', XREF split-orphans pruned: '' || rows_split_pruned || '', Backfill: '' || rows_backfill;
END;
';