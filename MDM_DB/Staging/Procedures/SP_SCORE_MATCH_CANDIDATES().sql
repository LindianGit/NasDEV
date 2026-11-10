CREATE OR REPLACE PROCEDURE MDM_DB.STAGING.SP_SCORE_MATCH_CANDIDATES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    -- Stage 3 of 3. Turns MATCH_PAIR_FLAGS into one scored edge per pair in MATCH_CANDIDATES.
    --   weighted score = sum of weights for matched attributes / total weight * 100
    --   a NULL on either side is not a match (the flag is UNKNOWN, which scores 0)
    -- Weights, thresholds and deterministic overrides live in MDM_DB.MDM.MATCH_CONFIG and
    -- MDM_DB.MDM.MATCH_OVERRIDES, so scoring policy changes without a deployment.
    LET rows_candidates INT := 0;
    LET config_count    INT := 0;
    LET config_missing  EXCEPTION (-20001, ''MATCH_CONFIG is missing one or more required parameters'');

    SELECT COUNT(DISTINCT PARAM) INTO :config_count
    FROM MDM_DB.MDM.MATCH_CONFIG
    WHERE PARAM IN (''WEIGHT_EMAIL'', ''WEIGHT_MOBILE'', ''WEIGHT_POSTCODE'', ''WEIGHT_FIRST_NAME'',
                    ''WEIGHT_LAST_NAME'', ''WEIGHT_ADDRESS'', ''FIRST_NAME_THRESHOLD'', ''LAST_NAME_THRESHOLD'',
                    ''ADDRESS_THRESHOLD'', ''LINK_THRESHOLD'', ''FIRST_NAME_VETO'', ''EMAIL_OVERRIDE_CAP'',
                    ''PREVIOUS_ADDRESS_FACTOR'', ''STRONG_THRESHOLD'');
    IF (config_count < 14) THEN
        RAISE config_missing;
    END IF;

    TRUNCATE TABLE MDM_DB.STAGING.MATCH_CANDIDATES;

    INSERT INTO MDM_DB.STAGING.MATCH_CANDIDATES (
        STANDARDISED_ID_A, STANDARDISED_ID_B, MATCH_METHOD, MATCH_SCORE, IS_LINKING, IS_STRONG, IS_IDENTITY
    )
    WITH cfg AS (
        SELECT
            MAX(IFF(PARAM = ''WEIGHT_EMAIL'',          VALUE, NULL)) AS W_EMAIL,
            MAX(IFF(PARAM = ''WEIGHT_MOBILE'',         VALUE, NULL)) AS W_MOBILE,
            MAX(IFF(PARAM = ''WEIGHT_POSTCODE'',       VALUE, NULL)) AS W_POSTCODE,
            MAX(IFF(PARAM = ''WEIGHT_FIRST_NAME'',     VALUE, NULL)) AS W_FIRST,
            MAX(IFF(PARAM = ''WEIGHT_LAST_NAME'',      VALUE, NULL)) AS W_LAST,
            MAX(IFF(PARAM = ''WEIGHT_ADDRESS'',        VALUE, NULL)) AS W_ADDRESS,
            MAX(IFF(PARAM = ''FIRST_NAME_THRESHOLD'',  VALUE, NULL)) AS T_FIRST,
            MAX(IFF(PARAM = ''LAST_NAME_THRESHOLD'',   VALUE, NULL)) AS T_LAST,
            MAX(IFF(PARAM = ''ADDRESS_THRESHOLD'',     VALUE, NULL)) AS T_ADDRESS,
            MAX(IFF(PARAM = ''LINK_THRESHOLD'',        VALUE, NULL)) AS T_LINK,
            MAX(IFF(PARAM = ''FIRST_NAME_VETO'',       VALUE, NULL)) AS V_FIRST,
            MAX(IFF(PARAM = ''EMAIL_OVERRIDE_CAP'',    VALUE, NULL)) AS CAP_EMAIL,
            MAX(IFF(PARAM = ''PREVIOUS_ADDRESS_FACTOR'', VALUE, NULL)) AS F_PREV,
            MAX(IFF(PARAM = ''STRONG_THRESHOLD'',      VALUE, NULL)) AS T_STRONG
        FROM MDM_DB.MDM.MATCH_CONFIG
    ),
    attr AS (
        -- 1 = both sides present and matching, 0 = anything else (including NULL).
        SELECT f.*,
            -- An email held by more records than the cap is a shared inbox: no weighted credit.
            IFF(f.EMAIL_STATE = ''MATCH'' AND COALESCE(f.EMAIL_SHARE_COUNT, 0) <= c.CAP_EMAIL, 1, 0) AS EMAIL_M,
            IFF(f.MOBILE_STATE   = ''MATCH'', 1, 0) AS MOBILE_M,
            IFF(f.POSTCODE_STATE = ''MATCH'', 1, 0) AS POSTCODE_M,
            IFF(f.FIRST_NAME_SIM >= c.T_FIRST, 1, 0) AS FIRST_M,
            IFF(f.LAST_NAME_SIM  >= c.T_LAST,  1, 0) AS LAST_M,
            -- Address line only counts alongside a shared postcode; a missing line scores 0.
            -- A match that exists only on previous addresses earns the fraction F_PREV.
            IFF(f.POSTCODE_STATE = ''MATCH'' AND f.ADDRESS_LINE_SIM >= c.T_ADDRESS,
                IFF(f.ADDRESS_LIVE_SIM >= c.T_ADDRESS, 1, c.F_PREV), 0) AS ADDRESS_M,
            -- Both first names present and too different. A NULL similarity is not a conflict.
            IFF(f.FIRST_NAME_SIM < c.T_FIRST AND c.V_FIRST = 1, 1, 0) AS FIRST_VETO,
            c.W_EMAIL, c.W_MOBILE, c.W_POSTCODE, c.W_ADDRESS, c.W_FIRST, c.W_LAST, c.T_LINK, c.T_STRONG
        FROM MDM_DB.STAGING.MATCH_PAIR_FLAGS f
        CROSS JOIN cfg c
    ),
    weighted AS (
        SELECT a.*,
            ROUND(100.0 * (
                a.EMAIL_M * a.W_EMAIL + a.MOBILE_M * a.W_MOBILE + a.POSTCODE_M * a.W_POSTCODE
                + a.ADDRESS_M * a.W_ADDRESS + a.FIRST_M * a.W_FIRST + a.LAST_M * a.W_LAST
            ) / (a.W_EMAIL + a.W_MOBILE + a.W_POSTCODE + a.W_ADDRESS + a.W_FIRST + a.W_LAST), 2) AS W_SCORE,
            COALESCE(NULLIF(ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
                IFF(a.EMAIL_M    = 1, ''EMAIL'',      NULL),
                IFF(a.MOBILE_M   = 1, ''MOBILE'',     NULL),
                IFF(a.POSTCODE_M = 1, ''POSTCODE'',   NULL),
                IFF(a.ADDRESS_M  > 0, ''ADDRESS'',    NULL),
                IFF(a.FIRST_M    = 1, ''FIRST_NAME'', NULL),
                IFF(a.LAST_M     = 1, ''LAST_NAME'',  NULL)
            ), ''+''), ''''), ''NO_ATTRIBUTE_MATCH'') AS LABEL
        FROM attr a
    ),
    override_hits AS (
        -- Which deterministic overrides each pair qualifies for.
        SELECT STANDARDISED_ID_A, STANDARDISED_ID_B, ''EXACT_RE_CONSTITUENT_ID''     AS OVERRIDE_KEY
            FROM MDM_DB.STAGING.MATCH_PAIR_FLAGS WHERE BLK_RE_ID
        UNION ALL
        SELECT STANDARDISED_ID_A, STANDARDISED_ID_B, ''EXACT_RE_CONSTITUENT_ID_ORG''
            FROM MDM_DB.STAGING.MATCH_PAIR_FLAGS WHERE BLK_RE_ID_ORG
        UNION ALL
        -- A shared email is a 100 override only when neither name conflicts. A missing name is
        -- not a conflict; a first or last name below its threshold is. Conflicting pairs
        -- (family, spouses, shared inboxes) fall back to their weighted score. Organisations have
        -- no personal names to conflict, so for them the organisation names must match: an
        -- administrator''s inbox shared by many different trusts is not evidence they are one.
        SELECT f.STANDARDISED_ID_A, f.STANDARDISED_ID_B, ''EXACT_EMAIL''
            FROM MDM_DB.STAGING.MATCH_PAIR_FLAGS f
            CROSS JOIN cfg c
            WHERE f.BLK_EMAIL
              AND NOT COALESCE(f.FIRST_NAME_SIM < c.T_FIRST OR f.LAST_NAME_SIM < c.T_LAST, FALSE)
              -- An email held by many records is a shared inbox: no 100 override.
              AND COALESCE(f.EMAIL_SHARE_COUNT, 0) <= c.CAP_EMAIL
              AND (NOT COALESCE(f.IS_ORGANISATION, FALSE) OR COALESCE(f.ORG_NAME_MATCH, FALSE))
        UNION ALL
        -- Full name plus full address (postcode and address line) for individuals.
        SELECT STANDARDISED_ID_A, STANDARDISED_ID_B, ''NAME_ADDRESS''
            FROM attr WHERE FIRST_M = 1 AND LAST_M = 1 AND ADDRESS_M = 1 AND NOT IS_ORGANISATION
        UNION ALL
        -- Same, but the shared address is previous on both records: a lower score.
        SELECT STANDARDISED_ID_A, STANDARDISED_ID_B, ''NAME_ADDRESS_PREVIOUS''
            FROM attr WHERE FIRST_M = 1 AND LAST_M = 1 AND ADDRESS_M > 0 AND ADDRESS_M < 1 AND NOT IS_ORGANISATION
        UNION ALL
        -- Same first name, last name and postcode with no address line to compare (or a different
        -- one). The weighted score alone is 30, under the link threshold, so these would otherwise
        -- be invisible. A fixed score makes them proposals for a steward; they never merge on their own.
        SELECT STANDARDISED_ID_A, STANDARDISED_ID_B, ''NAME_POSTCODE''
            FROM attr WHERE FIRST_M = 1 AND LAST_M = 1 AND POSTCODE_M = 1 AND NOT IS_ORGANISATION
        UNION ALL
        SELECT STANDARDISED_ID_A, STANDARDISED_ID_B, ''ORG_NAME_POSTCODE_PHONE''
            FROM MDM_DB.STAGING.MATCH_PAIR_FLAGS WHERE BLK_ORG_NAME_POSTCODE AND ORG_PHONE_SHARED
        UNION ALL
        SELECT STANDARDISED_ID_A, STANDARDISED_ID_B, ''ORG_NAME_POSTCODE''
            FROM MDM_DB.STAGING.MATCH_PAIR_FLAGS WHERE BLK_ORG_NAME_POSTCODE AND NOT ORG_PHONE_SHARED
        UNION ALL
        SELECT STANDARDISED_ID_A, STANDARDISED_ID_B, ''ORG_NAME''
            FROM MDM_DB.STAGING.MATCH_PAIR_FLAGS WHERE BLK_ORG_NAME
    ),
    override_best AS (
        SELECT h.STANDARDISED_ID_A, h.STANDARDISED_ID_B,
            MAX(o.SCORE)                  AS O_SCORE,
            MAX_BY(o.OVERRIDE_KEY, o.SCORE) AS O_KEY,
            BOOLOR_AGG(o.IS_LINKING)      AS O_LINKING,
            BOOLOR_AGG(o.IS_IDENTITY)     AS O_IDENTITY
        FROM override_hits h
        INNER JOIN MDM_DB.MDM.MATCH_OVERRIDES o ON o.OVERRIDE_KEY = h.OVERRIDE_KEY
        GROUP BY h.STANDARDISED_ID_A, h.STANDARDISED_ID_B
    ),
    scored AS (
        SELECT w.STANDARDISED_ID_A, w.STANDARDISED_ID_B,
            CASE WHEN ob.O_SCORE IS NOT NULL AND ob.O_SCORE >= w.W_SCORE THEN ob.O_KEY ELSE w.LABEL END AS METHOD,
            GREATEST(w.W_SCORE, COALESCE(ob.O_SCORE, 0)) AS SCORE,
            ((w.W_SCORE >= w.T_LINK) AND w.FIRST_VETO = 0) OR COALESCE(ob.O_LINKING, FALSE) AS LINKING,
            -- Identity-grade: authoritative ID links, or email / mobile plus an exact first and last name.
            COALESCE(ob.O_IDENTITY, FALSE)
                OR ((w.EMAIL_M = 1 OR w.MOBILE_M = 1) AND w.FIRST_NAME_SIM = 100 AND w.LAST_NAME_SIM = 100) AS IDENTITY,
            w.T_STRONG
        FROM weighted w
        LEFT JOIN override_best ob
            ON ob.STANDARDISED_ID_A = w.STANDARDISED_ID_A AND ob.STANDARDISED_ID_B = w.STANDARDISED_ID_B
    )
    SELECT s.STANDARDISED_ID_A, s.STANDARDISED_ID_B,
        -- Steward decisions win: APPROVED is a strong link, REJECTED never links.
        CASE WHEN ap.DECISION = ''APPROVED'' THEN ''STEWARD_APPROVED'' ELSE s.METHOD END,
        CASE WHEN ap.DECISION = ''APPROVED'' THEN 100 ELSE s.SCORE END,
        CASE ap.DECISION WHEN ''APPROVED'' THEN TRUE WHEN ''REJECTED'' THEN FALSE ELSE s.LINKING END,
        -- Strong = links the core group: at or above the threshold, identity-grade, or approved.
        CASE ap.DECISION WHEN ''APPROVED'' THEN TRUE WHEN ''REJECTED'' THEN FALSE
             ELSE s.LINKING AND (s.SCORE >= s.T_STRONG OR s.IDENTITY) END,
        s.IDENTITY
    FROM scored s
    LEFT JOIN MDM_DB.MDM.STEWARDSHIP_APPROVALS ap
        ON ap.STANDARDISED_ID_A = s.STANDARDISED_ID_A AND ap.STANDARDISED_ID_B = s.STANDARDISED_ID_B;
    rows_candidates := SQLROWCOUNT;

    RETURN ''Scoring complete. Candidates: '' || rows_candidates;
END;
';