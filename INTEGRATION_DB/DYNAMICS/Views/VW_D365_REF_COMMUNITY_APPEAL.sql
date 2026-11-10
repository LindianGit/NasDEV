create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_COMMUNITY_APPEAL(
	RE_APPEAL_NAME,
	RE_APPEAL_CODE,
	IS_COMMUNITY_APPEAL,
	NOTE
) as
-- Every appeal name on an RE proposal, and whether its proposals load as D365
-- event packages (TRUE) or opportunities (FALSE). RE appeal names look like
-- 'COE005: Birthday/ Celebration', so the match is on the code before the
-- colon. A name with no colon is its own code. The community list is a draft:
-- NAS fundraising must confirm it.
WITH RE_VALUES AS (
    SELECT DISTINCT
        TRIM(APPEALDESCRIPTION) AS RE_APPEAL_NAME,
        TRIM(SPLIT_PART(TRIM(APPEALDESCRIPTION), ':', 1)) AS RE_APPEAL_CODE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_PROPOSALS
    WHERE NULLIF(TRIM(APPEALDESCRIPTION), '') IS NOT NULL
),

COMMUNITY AS (
    SELECT
        COLUMN1 AS RE_APPEAL_CODE,
        COLUMN2 AS NOTE
    FROM VALUES
    -- ASSUMED: COE code taken as a community appeal; NAS to confirm
    ('COE001', 'Community events appeal'),
    -- ASSUMED: COE code taken as a community appeal; NAS to confirm
    ('COE002', 'Community events appeal'),
    -- ASSUMED: COE code taken as a community appeal; NAS to confirm
    ('COE004', 'Community events appeal'),
    -- ASSUMED: COE code taken as a community appeal; NAS to confirm
    ('COE005', 'Community events appeal'),
    -- ASSUMED: COE code taken as a community appeal; NAS to confirm
    ('COE006', 'Community events appeal'),
    -- ASSUMED: COE code taken as a community appeal; NAS to confirm
    ('COE015', 'Community events appeal')
)

SELECT
    R.RE_APPEAL_NAME,
    R.RE_APPEAL_CODE,
    C.RE_APPEAL_CODE IS NOT NULL AS IS_COMMUNITY_APPEAL,
    C.NOTE
FROM RE_VALUES AS R
LEFT JOIN COMMUNITY AS C ON R.RE_APPEAL_CODE = C.RE_APPEAL_CODE;