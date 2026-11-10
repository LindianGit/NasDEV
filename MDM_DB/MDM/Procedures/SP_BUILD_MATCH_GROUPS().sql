CREATE OR REPLACE PROCEDURE MDM_DB.MDM.SP_BUILD_MATCH_GROUPS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    -- Orchestrator: extract attributes -> generate candidate pairs and flags -> score the
    -- pairs -> build core groups from strong edges -> list weaker links as proposals.
    -- Only strong edges (at or above STRONG_THRESHOLD, identity-grade, or steward-approved) join
    -- records into a group; a weaker link can never carry a record into a fused group.
    LET rows_candidates INT := 0;
    LET rows_components INT := 0;
    LET rows_groups     INT := 0;
    LET rows_members    INT := 0;
    LET rows_proposals  INT := 0;
    TRUNCATE TABLE MDM_DB.STAGING.MATCH_COMPONENTS;
    TRUNCATE TABLE MDM_DB.STAGING.MATCH_PROPOSALS;
    TRUNCATE TABLE MDM_DB.MDM.MATCH_GROUPS;
    TRUNCATE TABLE MDM_DB.MDM.MATCH_GROUP_MEMBERS;

    CALL MDM_DB.STAGING.SP_EXTRACT_MATCH_ATTRIBUTES();
    CALL MDM_DB.STAGING.SP_GENERATE_MATCH_PAIRS();
    CALL MDM_DB.STAGING.SP_SCORE_MATCH_CANDIDATES();
    SELECT COUNT(*) INTO :rows_candidates FROM MDM_DB.STAGING.MATCH_CANDIDATES;

    INSERT INTO MDM_DB.STAGING.MATCH_COMPONENTS (STANDARDISED_ID, MATCH_GROUP_LABEL)
    -- IS_STRONG is decided once, in SP_SCORE_MATCH_CANDIDATES.
    SELECT STANDARDISED_ID_A, STANDARDISED_ID_A FROM MDM_DB.STAGING.MATCH_CANDIDATES WHERE IS_STRONG
    UNION
    SELECT STANDARDISED_ID_B, STANDARDISED_ID_B FROM MDM_DB.STAGING.MATCH_CANDIDATES WHERE IS_STRONG;
    rows_components := SQLROWCOUNT;

    CALL MDM_DB.STAGING.SP_BUILD_MATCH_COMPONENTS();

    UPDATE MDM_DB.STAGING.MATCH_COMPONENTS SET MATCH_GROUP_ID = ''MG-'' || MATCH_GROUP_LABEL;

    INSERT INTO MDM_DB.MDM.MATCH_GROUPS (
        MATCH_GROUP_ID, DOMAIN, MATCH_SCORE, MATCH_METHOD, RECORD_COUNT, STATUS, CREATED_AT, UPDATED_AT
    )
    WITH group_counts AS (
        SELECT MATCH_GROUP_ID, COUNT(*) AS RECORD_COUNT
        FROM MDM_DB.STAGING.MATCH_COMPONENTS
        GROUP BY MATCH_GROUP_ID
        HAVING COUNT(*) > 1
    ),
    group_scores AS (
        -- Average only the strong edges that built the group. Weaker links are proposals, not
        -- part of the group''s evidence, and would drag the average down.
        SELECT c1.MATCH_GROUP_ID,
            AVG(cand.MATCH_SCORE) AS AVG_SCORE
        FROM MDM_DB.STAGING.MATCH_CANDIDATES cand
        INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS c1 ON cand.STANDARDISED_ID_A = c1.STANDARDISED_ID
        INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS c2
            ON cand.STANDARDISED_ID_B = c2.STANDARDISED_ID AND c1.MATCH_GROUP_ID = c2.MATCH_GROUP_ID
        WHERE cand.IS_STRONG
        GROUP BY c1.MATCH_GROUP_ID
    ),
    group_edge_stats AS (
        -- Pick the match method with the most strong edges in this group (most representative signal)
        SELECT c1.MATCH_GROUP_ID, cand.MATCH_METHOD,
            ROW_NUMBER() OVER (PARTITION BY c1.MATCH_GROUP_ID ORDER BY COUNT(*) DESC) AS RN
        FROM MDM_DB.STAGING.MATCH_CANDIDATES cand
        INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS c1 ON cand.STANDARDISED_ID_A = c1.STANDARDISED_ID
        INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS c2
            ON cand.STANDARDISED_ID_B = c2.STANDARDISED_ID AND c1.MATCH_GROUP_ID = c2.MATCH_GROUP_ID
        WHERE cand.IS_STRONG
        GROUP BY c1.MATCH_GROUP_ID, cand.MATCH_METHOD
    ),
    group_domains AS (
        SELECT mc.MATCH_GROUP_ID,
            CASE WHEN MIN(sr.SOURCE_DOMAIN) = MAX(sr.SOURCE_DOMAIN)
                 THEN MIN(sr.SOURCE_DOMAIN)
                 ELSE ''MIXED''
            END AS DOMAIN
        FROM MDM_DB.STAGING.MATCH_COMPONENTS mc
        INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr ON mc.STANDARDISED_ID = sr.STANDARDISED_ID
        GROUP BY mc.MATCH_GROUP_ID
    ),
    group_has_identity_edge AS (
        -- Groups carrying an identity-grade edge are floored at Pending Review so
        -- that averaging against weaker co-edges cannot demote them to Low Confidence.
        -- IS_IDENTITY is decided in SP_SCORE_MATCH_CANDIDATES (see MATCH_OVERRIDES).
        SELECT DISTINCT c1.MATCH_GROUP_ID
        FROM MDM_DB.STAGING.MATCH_CANDIDATES cand
        INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS c1 ON cand.STANDARDISED_ID_A = c1.STANDARDISED_ID
        INNER JOIN MDM_DB.STAGING.MATCH_COMPONENTS c2
            ON cand.STANDARDISED_ID_B = c2.STANDARDISED_ID AND c1.MATCH_GROUP_ID = c2.MATCH_GROUP_ID
        WHERE cand.IS_STRONG AND cand.IS_IDENTITY
    )
    SELECT
        gc.MATCH_GROUP_ID,
        gd.DOMAIN,
        gs.AVG_SCORE,
        ges.MATCH_METHOD,
        gc.RECORD_COUNT,
        CASE
            -- Backstop against chaining: very large groups never auto-merge.
            WHEN gc.RECORD_COUNT >= sc.MAX_SIZE THEN ''Low Confidence''
            WHEN gs.AVG_SCORE >= 95 THEN ''Auto-Approved''
            WHEN gs.AVG_SCORE >= 85 THEN ''Pending Review''
            WHEN ghie.MATCH_GROUP_ID IS NOT NULL THEN ''Pending Review''
            ELSE ''Low Confidence''
        END,
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP()
    FROM group_counts gc
    CROSS JOIN (
        SELECT COALESCE(MAX(VALUE), 1000000000) AS MAX_SIZE
        FROM MDM_DB.MDM.MATCH_CONFIG WHERE PARAM = ''MAX_GROUP_SIZE''
    ) sc
    INNER JOIN group_scores gs     ON gc.MATCH_GROUP_ID = gs.MATCH_GROUP_ID
    INNER JOIN group_edge_stats ges ON gc.MATCH_GROUP_ID = ges.MATCH_GROUP_ID AND ges.RN = 1
    INNER JOIN group_domains gd     ON gc.MATCH_GROUP_ID = gd.MATCH_GROUP_ID
    LEFT JOIN group_has_identity_edge ghie ON gc.MATCH_GROUP_ID = ghie.MATCH_GROUP_ID;
    rows_groups := SQLROWCOUNT;

    INSERT INTO MDM_DB.MDM.MATCH_GROUP_MEMBERS (
        MATCH_GROUP_ID, SOURCE_SYSTEM, SOURCE_RECORD_ID, STANDARDISED_ID,
        MATCH_PROBABILITY, IS_SURVIVING_RECORD, ADDED_AT
    )
    SELECT
        mc.MATCH_GROUP_ID,
        sr.SOURCE_SYSTEM,
        sr.SOURCE_RECORD_ID,
        mc.STANDARDISED_ID,
        mg.MATCH_SCORE,
        ROW_NUMBER() OVER (PARTITION BY mc.MATCH_GROUP_ID ORDER BY sr.LAST_UPDATED DESC NULLS LAST) = 1,
        CURRENT_TIMESTAMP()
    FROM MDM_DB.STAGING.MATCH_COMPONENTS mc
    INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr ON mc.STANDARDISED_ID = sr.STANDARDISED_ID
    INNER JOIN MDM_DB.MDM.MATCH_GROUPS mg ON mc.MATCH_GROUP_ID = mg.MATCH_GROUP_ID;
    rows_members := SQLROWCOUNT;

    -- Proposals: linking edges below the strong line. A proposal says "these two records (or core
    -- groups) may belong together". It fuses nothing until a steward approves it, which writes an
    -- APPROVED row to STEWARDSHIP_APPROVALS and makes the edge strong on the next run. A weak edge
    -- between two records already in the same core group adds nothing and is skipped.
    INSERT INTO MDM_DB.STAGING.MATCH_PROPOSALS (
        STANDARDISED_ID_A, STANDARDISED_ID_B, MATCH_METHOD, MATCH_SCORE, CORE_GROUP_ID_A, CORE_GROUP_ID_B
    )
    SELECT c.STANDARDISED_ID_A, c.STANDARDISED_ID_B, c.MATCH_METHOD, c.MATCH_SCORE,
           ma.MATCH_GROUP_ID, mb.MATCH_GROUP_ID
    FROM MDM_DB.STAGING.MATCH_CANDIDATES c
    LEFT JOIN MDM_DB.STAGING.MATCH_COMPONENTS ma ON ma.STANDARDISED_ID = c.STANDARDISED_ID_A
    LEFT JOIN MDM_DB.STAGING.MATCH_COMPONENTS mb ON mb.STANDARDISED_ID = c.STANDARDISED_ID_B
    WHERE c.IS_LINKING AND NOT c.IS_STRONG
      AND NOT (ma.MATCH_GROUP_ID IS NOT NULL AND ma.MATCH_GROUP_ID = mb.MATCH_GROUP_ID);
    rows_proposals := SQLROWCOUNT;

    RETURN ''Matching complete. Candidates: '' || rows_candidates || '', Components: '' || rows_components || '', Groups: '' || rows_groups || '', Members: '' || rows_members || '', Proposals: '' || rows_proposals;
END;
';