CREATE OR REPLACE PROCEDURE MDM_DB.STAGING.SP_GENERATE_MATCH_PAIRS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    -- Stage 2 of 3. Blocking only: find candidate pairs (blocks), then record how each pair
    -- compares on every attribute. No scores and no weights here; SP_SCORE_MATCH_CANDIDATES
    -- turns these flags into scores, so scoring policy can change without touching blocking.
    LET rows_pairs INT := 0;
    TRUNCATE TABLE MDM_DB.STAGING.MATCH_PAIR_FLAGS;

    INSERT INTO MDM_DB.STAGING.MATCH_PAIR_FLAGS (
        STANDARDISED_ID_A, STANDARDISED_ID_B, IS_ORGANISATION,
        BLK_EMAIL, BLK_MOBILE, BLK_LANDLINE, BLK_NAME_POSTCODE,
        BLK_ORG_NAME, BLK_ORG_NAME_POSTCODE, BLK_RE_ID, BLK_RE_ID_ORG,
        EMAIL_STATE, MOBILE_STATE, POSTCODE_STATE,
        LANDLINE_SHARED, ORG_PHONE_SHARED, FIRST_NAME_SIM, LAST_NAME_SIM, ADDRESS_LINE_SIM,
        EMAIL_SHARE_COUNT, ADDRESS_LIVE_SIM, ORG_NAME_MATCH
    )
    WITH capped_phones AS (
        -- Frequency caps stop switchboards and placeholder numbers creating mega-groups.
        -- Extraction is already distinct per (record, phone), so COUNT(*) is a record count.
        SELECT STANDARDISED_ID, PHONE, PHONE_CLASS, IS_ORGANISATION
        FROM MDM_DB.STAGING.MATCH_ATTR_PHONES
        QUALIFY COUNT(*) OVER (PARTITION BY PHONE) <=
            CASE WHEN PHONE_CLASS = ''MOBILE'' THEN 5 ELSE 10 END
    ),
    capped_org_names AS (
        -- Names shared by more than 3 records are brand or multi-site names; drop them.
        SELECT STANDARDISED_ID, ORG_KEY
        FROM MDM_DB.STAGING.MATCH_ATTR_ORG_KEYS
        QUALIFY COUNT(*) OVER (PARTITION BY ORG_KEY) <= 3
    ),
    blk_email AS (
        SELECT DISTINCT e1.STANDARDISED_ID AS ID_A, e2.STANDARDISED_ID AS ID_B, ''EMAIL'' AS BLK
        FROM MDM_DB.STAGING.MATCH_ATTR_EMAILS e1
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_EMAILS e2
            ON e1.EMAIL = e2.EMAIL
            AND e1.STANDARDISED_ID < e2.STANDARDISED_ID
            AND e1.IS_ORGANISATION = e2.IS_ORGANISATION
    ),
    blk_mobile AS (
        SELECT DISTINCT p1.STANDARDISED_ID AS ID_A, p2.STANDARDISED_ID AS ID_B, ''MOBILE'' AS BLK
        FROM capped_phones p1
        INNER JOIN capped_phones p2
            ON p1.PHONE = p2.PHONE
            AND p1.STANDARDISED_ID < p2.STANDARDISED_ID
            AND p1.IS_ORGANISATION = p2.IS_ORGANISATION
        WHERE p1.PHONE_CLASS = ''MOBILE'' AND p2.PHONE_CLASS = ''MOBILE''
    ),
    blk_landline AS (
        SELECT DISTINCT p1.STANDARDISED_ID AS ID_A, p2.STANDARDISED_ID AS ID_B, ''LANDLINE'' AS BLK
        FROM capped_phones p1
        INNER JOIN capped_phones p2
            ON p1.PHONE = p2.PHONE
            AND p1.STANDARDISED_ID < p2.STANDARDISED_ID
            AND p1.IS_ORGANISATION = p2.IS_ORGANISATION
        WHERE p1.PHONE_CLASS = ''LANDLINE'' OR p2.PHONE_CLASS = ''LANDLINE''
    ),
    blk_name_postcode AS (
        -- Same postcode and either identical names, or similar names on preferred addresses.
        SELECT DISTINCT a1.STANDARDISED_ID AS ID_A, a2.STANDARDISED_ID AS ID_B, ''NAME_POSTCODE'' AS BLK
        FROM MDM_DB.STAGING.MATCH_ATTR_ADDRESSES a1
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_ADDRESSES a2
            ON a1.POSTCODE = a2.POSTCODE
            AND a1.STANDARDISED_ID < a2.STANDARDISED_ID
        WHERE a1.IS_ORGANISATION = FALSE AND a2.IS_ORGANISATION = FALSE
            AND a1.FIRST_NAME IS NOT NULL AND a1.LAST_NAME IS NOT NULL
            AND (
                (a1.FIRST_NAME = a2.FIRST_NAME AND a1.LAST_NAME = a2.LAST_NAME)
                OR (a1.IS_PREFERRED = 1 AND a2.IS_PREFERRED = 1
                    AND JAROWINKLER_SIMILARITY(a1.LAST_NAME, a2.LAST_NAME) >= 85
                    AND JAROWINKLER_SIMILARITY(a1.FIRST_NAME, a2.FIRST_NAME) >= 80)
            )
    ),
    blk_org_name AS (
        SELECT DISTINCT k1.STANDARDISED_ID AS ID_A, k2.STANDARDISED_ID AS ID_B, ''ORG_NAME'' AS BLK
        FROM capped_org_names k1
        INNER JOIN capped_org_names k2
            ON k1.ORG_KEY = k2.ORG_KEY AND k1.STANDARDISED_ID < k2.STANDARDISED_ID
    ),
    blk_org_name_postcode AS (
        SELECT DISTINCT a1.STANDARDISED_ID AS ID_A, a2.STANDARDISED_ID AS ID_B, ''ORG_NAME_POSTCODE'' AS BLK
        FROM MDM_DB.STAGING.MATCH_ATTR_ADDRESSES a1
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_ADDRESSES a2
            ON a1.POSTCODE = a2.POSTCODE AND a1.STANDARDISED_ID < a2.STANDARDISED_ID
        INNER JOIN capped_org_names k1 ON k1.STANDARDISED_ID = a1.STANDARDISED_ID
        INNER JOIN capped_org_names k2 ON k2.STANDARDISED_ID = a2.STANDARDISED_ID AND k2.ORG_KEY = k1.ORG_KEY
        WHERE a1.IS_ORGANISATION = TRUE AND a2.IS_ORGANISATION = TRUE
    ),
    blk_re AS (
        SELECT STANDARDISED_ID_A AS ID_A, STANDARDISED_ID_B AS ID_B,
            CASE LINK_TYPE WHEN ''CONTACT'' THEN ''RE_ID'' ELSE ''RE_ID_ORG'' END AS BLK
        FROM MDM_DB.STAGING.MATCH_ATTR_RE_LINKS
    ),
    pair_blocks AS (
        SELECT ID_A, ID_B, BLK FROM blk_email
        UNION ALL SELECT ID_A, ID_B, BLK FROM blk_mobile
        UNION ALL SELECT ID_A, ID_B, BLK FROM blk_landline
        UNION ALL SELECT ID_A, ID_B, BLK FROM blk_name_postcode
        UNION ALL SELECT ID_A, ID_B, BLK FROM blk_org_name
        UNION ALL SELECT ID_A, ID_B, BLK FROM blk_org_name_postcode
        UNION ALL SELECT ID_A, ID_B, BLK FROM blk_re
    ),
    pairs AS (
        SELECT ID_A, ID_B,
            BOOLOR_AGG(BLK = ''EMAIL'')             AS BLK_EMAIL,
            BOOLOR_AGG(BLK = ''MOBILE'')            AS BLK_MOBILE,
            BOOLOR_AGG(BLK = ''LANDLINE'')          AS BLK_LANDLINE,
            BOOLOR_AGG(BLK = ''NAME_POSTCODE'')     AS BLK_NAME_POSTCODE,
            BOOLOR_AGG(BLK = ''ORG_NAME'')          AS BLK_ORG_NAME,
            BOOLOR_AGG(BLK = ''ORG_NAME_POSTCODE'') AS BLK_ORG_NAME_POSTCODE,
            BOOLOR_AGG(BLK = ''RE_ID'')             AS BLK_RE_ID,
            BOOLOR_AGG(BLK = ''RE_ID_ORG'')         AS BLK_RE_ID_ORG
        FROM pair_blocks
        GROUP BY ID_A, ID_B
    ),
    -- Attribute comparisons are evaluated per candidate pair, so cost scales with the
    -- number of pairs rather than with the size of each attribute''s value space.
    shared_email AS (
        SELECT DISTINCT p.ID_A, p.ID_B
        FROM pairs p
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_EMAILS a ON a.STANDARDISED_ID = p.ID_A
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_EMAILS b ON b.STANDARDISED_ID = p.ID_B AND b.EMAIL = a.EMAIL
    ),
    shared_mobile AS (
        SELECT DISTINCT p.ID_A, p.ID_B
        FROM pairs p
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_PHONES a ON a.STANDARDISED_ID = p.ID_A AND a.PHONE_CLASS = ''MOBILE''
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_PHONES b ON b.STANDARDISED_ID = p.ID_B AND b.PHONE = a.PHONE
    ),
    shared_landline AS (
        SELECT DISTINCT p.ID_A, p.ID_B
        FROM pairs p
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_PHONES a ON a.STANDARDISED_ID = p.ID_A AND a.PHONE_CLASS = ''LANDLINE''
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_PHONES b ON b.STANDARDISED_ID = p.ID_B AND b.PHONE = a.PHONE
    ),
    shared_org_phone AS (
        -- Capped pool, so a switchboard number shared by many organisations does not count.
        SELECT DISTINCT p.ID_A, p.ID_B
        FROM pairs p
        INNER JOIN capped_phones a ON a.STANDARDISED_ID = p.ID_A
        INNER JOIN capped_phones b ON b.STANDARDISED_ID = p.ID_B AND b.PHONE = a.PHONE
    ),
    shared_org_name AS (
        -- Same normalised organisation name, from the uncapped keys: the frequency cap in
        -- capped_org_names limits blocking, but name equality must not depend on it.
        SELECT DISTINCT p.ID_A, p.ID_B
        FROM pairs p
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_ORG_KEYS a ON a.STANDARDISED_ID = p.ID_A
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_ORG_KEYS b ON b.STANDARDISED_ID = p.ID_B AND b.ORG_KEY = a.ORG_KEY
    ),
    shared_postcode AS (
        SELECT DISTINCT p.ID_A, p.ID_B
        FROM pairs p
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_ADDRESSES a ON a.STANDARDISED_ID = p.ID_A
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_ADDRESSES b ON b.STANDARDISED_ID = p.ID_B AND b.POSTCODE = a.POSTCODE
    ),
    email_share AS (
        -- Fewest records holding any email the pair shares. An email held by many records is a
        -- shared inbox and weak evidence; one held by two records is strong. Scoring caps the
        -- email override on this count.
        SELECT p.ID_A, p.ID_B, MIN(h.HOLDERS) AS HOLDERS
        FROM pairs p
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_EMAILS a ON a.STANDARDISED_ID = p.ID_A
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_EMAILS b ON b.STANDARDISED_ID = p.ID_B AND b.EMAIL = a.EMAIL
        INNER JOIN (
            SELECT EMAIL, COUNT(DISTINCT STANDARDISED_ID) AS HOLDERS
            FROM MDM_DB.STAGING.MATCH_ATTR_EMAILS
            GROUP BY EMAIL
        ) h ON h.EMAIL = a.EMAIL
        GROUP BY p.ID_A, p.ID_B
    ),
    address_sim AS (
        -- Best address-line similarity across addresses that share a postcode. A missing line
        -- on either side is skipped, so a pair with no comparable lines gets NULL (no credit).
        -- LIVE_SIM ignores matches where both addresses are previous: an old shared address is
        -- weaker evidence than a current one.
        SELECT p.ID_A, p.ID_B,
            MAX(JAROWINKLER_SIMILARITY(a.ADDRESS_LINE1, b.ADDRESS_LINE1)) AS SIM,
            MAX(IFF(COALESCE(a.IS_CURRENT, TRUE) OR COALESCE(b.IS_CURRENT, TRUE),
                    JAROWINKLER_SIMILARITY(a.ADDRESS_LINE1, b.ADDRESS_LINE1), NULL)) AS LIVE_SIM
        FROM pairs p
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_ADDRESSES a ON a.STANDARDISED_ID = p.ID_A
        INNER JOIN MDM_DB.STAGING.MATCH_ATTR_ADDRESSES b
            ON b.STANDARDISED_ID = p.ID_B AND b.POSTCODE = a.POSTCODE
        WHERE a.ADDRESS_LINE1 IS NOT NULL AND b.ADDRESS_LINE1 IS NOT NULL
        GROUP BY p.ID_A, p.ID_B
    ),
    has_email    AS (SELECT DISTINCT STANDARDISED_ID FROM MDM_DB.STAGING.MATCH_ATTR_EMAILS),
    has_mobile   AS (SELECT DISTINCT STANDARDISED_ID FROM MDM_DB.STAGING.MATCH_ATTR_PHONES WHERE PHONE_CLASS = ''MOBILE''),
    has_postcode AS (SELECT DISTINCT STANDARDISED_ID FROM MDM_DB.STAGING.MATCH_ATTR_ADDRESSES)
    SELECT p.ID_A, p.ID_B, ra.IS_ORGANISATION,
        p.BLK_EMAIL, p.BLK_MOBILE, p.BLK_LANDLINE, p.BLK_NAME_POSTCODE,
        p.BLK_ORG_NAME, p.BLK_ORG_NAME_POSTCODE, p.BLK_RE_ID, p.BLK_RE_ID_ORG,
        CASE WHEN se.ID_A IS NOT NULL THEN ''MATCH''
             WHEN hea.STANDARDISED_ID IS NULL OR heb.STANDARDISED_ID IS NULL THEN ''UNKNOWN''
             ELSE ''CONFLICT'' END,
        CASE WHEN sm.ID_A IS NOT NULL THEN ''MATCH''
             WHEN hma.STANDARDISED_ID IS NULL OR hmb.STANDARDISED_ID IS NULL THEN ''UNKNOWN''
             ELSE ''CONFLICT'' END,
        CASE WHEN sp.ID_A IS NOT NULL THEN ''MATCH''
             WHEN hpa.STANDARDISED_ID IS NULL OR hpb.STANDARDISED_ID IS NULL THEN ''UNKNOWN''
             ELSE ''CONFLICT'' END,
        sl.ID_A IS NOT NULL,
        so.ID_A IS NOT NULL,
        JAROWINKLER_SIMILARITY(ra.FIRST_NAME, rb.FIRST_NAME),
        JAROWINKLER_SIMILARITY(ra.LAST_NAME, rb.LAST_NAME),
        asim.SIM,
        es.HOLDERS,
        asim.LIVE_SIM,
        son.ID_A IS NOT NULL
    FROM pairs p
    INNER JOIN MDM_DB.STAGING.MATCH_ATTR_RECORDS ra ON ra.STANDARDISED_ID = p.ID_A
    INNER JOIN MDM_DB.STAGING.MATCH_ATTR_RECORDS rb ON rb.STANDARDISED_ID = p.ID_B
    LEFT JOIN shared_email     se ON se.ID_A = p.ID_A AND se.ID_B = p.ID_B
    LEFT JOIN shared_mobile    sm ON sm.ID_A = p.ID_A AND sm.ID_B = p.ID_B
    LEFT JOIN shared_landline  sl ON sl.ID_A = p.ID_A AND sl.ID_B = p.ID_B
    LEFT JOIN shared_org_phone so ON so.ID_A = p.ID_A AND so.ID_B = p.ID_B
    LEFT JOIN shared_postcode  sp ON sp.ID_A = p.ID_A AND sp.ID_B = p.ID_B
    LEFT JOIN shared_org_name son ON son.ID_A = p.ID_A AND son.ID_B = p.ID_B
    LEFT JOIN address_sim    asim ON asim.ID_A = p.ID_A AND asim.ID_B = p.ID_B
    LEFT JOIN email_share      es ON es.ID_A = p.ID_A AND es.ID_B = p.ID_B
    LEFT JOIN has_email    hea ON hea.STANDARDISED_ID = p.ID_A
    LEFT JOIN has_email    heb ON heb.STANDARDISED_ID = p.ID_B
    LEFT JOIN has_mobile   hma ON hma.STANDARDISED_ID = p.ID_A
    LEFT JOIN has_mobile   hmb ON hmb.STANDARDISED_ID = p.ID_B
    LEFT JOIN has_postcode hpa ON hpa.STANDARDISED_ID = p.ID_A
    LEFT JOIN has_postcode hpb ON hpb.STANDARDISED_ID = p.ID_B;
    rows_pairs := SQLROWCOUNT;

    RETURN ''Pair generation complete. Pairs: '' || rows_pairs;
END;
';