create or replace view MDM_DB.GOLD.VW_GOLDEN_RECORD_IDS(
	GOLDEN_RECORD_ID,
	RE_CONSTITUENT_ID,
	HS_OBJECT_ID,
	D365_CONTACT_ID,
	D365_ACCOUNT_ID,
	RE_EXISTS,
	HS_EXISTS,
	D365_CONTACT_EXISTS,
	D365_ACCOUNT_EXISTS,
	IS_GDPR_SUPPRESSED
) as
-- Golden-centric id and existence view.
-- One row per active golden record; exposes per-platform source ids
-- and absence flags. IS_GDPR_SUPPRESSED gates records through erasure.
-- RE_CONSTITUENT_ID and HS_OBJECT_ID pick the oldest record (lowest
-- numeric id) via a null-safe bucketed key for write-back stability.
-- D365_CONTACT_ID/D365_ACCOUNT_ID follow the same pattern, split by
-- STANDARDISED_ID prefix ('D365-'/'D365C-') since both share
-- SOURCE_SYSTEM = 'DYNAMICS'.
SELECT
    GR.GOLDEN_RECORD_ID,
    MIN_BY(
        CASE WHEN X.SOURCE_SYSTEM = 'RAISERS_EDGE' THEN X.SOURCE_RECORD_ID END,
        CASE
            WHEN X.SOURCE_SYSTEM = 'RAISERS_EDGE'
                THEN CASE
                    WHEN TRY_TO_NUMBER(X.SOURCE_RECORD_ID) IS NOT NULL
                        THEN
                            '0'
                            || LPAD(
                                TO_VARCHAR(TRY_TO_NUMBER(X.SOURCE_RECORD_ID)),
                                38,
                                '0'
                            )
                    ELSE '1' || X.SOURCE_RECORD_ID
                END
        END
    ) AS RE_CONSTITUENT_ID,
    MIN_BY(
        CASE WHEN X.SOURCE_SYSTEM = 'HUBSPOT' THEN X.SOURCE_RECORD_ID END,
        CASE
            WHEN X.SOURCE_SYSTEM = 'HUBSPOT'
                THEN CASE
                    WHEN TRY_TO_NUMBER(X.SOURCE_RECORD_ID) IS NOT NULL
                        THEN
                            '0'
                            || LPAD(
                                TO_VARCHAR(TRY_TO_NUMBER(X.SOURCE_RECORD_ID)),
                                38,
                                '0'
                            )
                    ELSE '1' || X.SOURCE_RECORD_ID
                END
        END
    ) AS HS_OBJECT_ID,
    MIN_BY(
        CASE WHEN X.STANDARDISED_ID LIKE 'D365-%' THEN X.SOURCE_RECORD_ID END,
        CASE
            WHEN X.STANDARDISED_ID LIKE 'D365-%'
                THEN CASE
                    WHEN TRY_TO_NUMBER(X.SOURCE_RECORD_ID) IS NOT NULL
                        THEN
                            '0'
                            || LPAD(
                                TO_VARCHAR(TRY_TO_NUMBER(X.SOURCE_RECORD_ID)),
                                38,
                                '0'
                            )
                    ELSE '1' || X.SOURCE_RECORD_ID
                END
        END
    ) AS D365_CONTACT_ID,
    MIN_BY(
        CASE WHEN X.STANDARDISED_ID LIKE 'D365C-%' THEN X.SOURCE_RECORD_ID END,
        CASE
            WHEN X.STANDARDISED_ID LIKE 'D365C-%'
                THEN CASE
                    WHEN TRY_TO_NUMBER(X.SOURCE_RECORD_ID) IS NOT NULL
                        THEN
                            '0'
                            || LPAD(
                                TO_VARCHAR(TRY_TO_NUMBER(X.SOURCE_RECORD_ID)),
                                38,
                                '0'
                            )
                    ELSE '1' || X.SOURCE_RECORD_ID
                END
        END
    ) AS D365_ACCOUNT_ID,
    BOOLOR_AGG(X.SOURCE_SYSTEM = 'RAISERS_EDGE') AS RE_EXISTS,
    BOOLOR_AGG(X.SOURCE_SYSTEM = 'HUBSPOT') AS HS_EXISTS,
    BOOLOR_AGG(X.STANDARDISED_ID LIKE 'D365-%') AS D365_CONTACT_EXISTS,
    BOOLOR_AGG(X.STANDARDISED_ID LIKE 'D365C-%') AS D365_ACCOUNT_EXISTS,
    BOOLOR_AGG(S.GOLDEN_RECORD_ID IS NOT NULL) AS IS_GDPR_SUPPRESSED
FROM MDM_DB.GOLD.GOLDEN_RECORDS AS GR
LEFT JOIN MDM_DB.GOLD.XREF AS X
    ON GR.GOLDEN_RECORD_ID = X.GOLDEN_RECORD_ID
LEFT JOIN MDM_DB.GOLD.GDPR_SUPPRESSED_GOLDEN_RECORDS AS S
    ON GR.GOLDEN_RECORD_ID = S.GOLDEN_RECORD_ID
WHERE GR._IS_ACTIVE = TRUE
GROUP BY GR.GOLDEN_RECORD_ID;