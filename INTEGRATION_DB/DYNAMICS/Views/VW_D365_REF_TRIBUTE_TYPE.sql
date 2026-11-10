create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_TRIBUTE_TYPE(
	RE_TRIBUTE_TYPE,
	D365_OPTION_LABEL,
	D365_OPTION_VALUE,
	MAP_STATUS,
	NOTE
) as
-- RE tribute type to the D365 tribute or memory type. RE values come from the
-- live tributes, the option value from the D365 metadata. MAP_STATUS: MAPPED,
-- UNMAPPED (decided: no target), NEW (an RE value with no decision),
-- NO_D365_OPTION (the label is not in the metadata).
WITH RE_VALUES AS (
    SELECT DISTINCT TRIM(TRIBUTETYPEDESCRIPTION) AS RE_TRIBUTE_TYPE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_TRIBUTES
    WHERE NULLIF(TRIM(TRIBUTETYPEDESCRIPTION), '') IS NOT NULL
),

DECISIONS AS (
    SELECT
        COLUMN1 AS RE_TRIBUTE_TYPE,
        COLUMN2 AS D365_OPTION_LABEL,
        COLUMN3 AS NOTE
    FROM
        VALUES
        ('In memory of', 'In Memory', 'Clear'),
        (
            'In Celebration of the birthday of',
            'In Honor',
            'Celebration types load as In Honor'
        ),
        (
            'In Celebration of the wedding of',
            'In Honor',
            'Celebration types load as In Honor'
        ),
        (
            'In Celebration of the anniversary of',
            'In Honor',
            'Celebration types load as In Honor'
        ),
        (
            'In Celebration of the',
            'In Honor',
            'Celebration types load as In Honor'
        ),
        (
            'In Celebration of the baptism of',
            'In Honor',
            'Celebration types load as In Honor'
        ),
        (
            'In Celebration of the retirement',
            'In Honor',
            'Celebration types load as In Honor'
        ),
        ('Other', NULL, 'No D365 equivalent; the column stays empty')
)

SELECT
    R.RE_TRIBUTE_TYPE,
    D.D365_OPTION_LABEL,
    O.OPTION_VALUE AS D365_OPTION_VALUE,
    CASE
        WHEN D.RE_TRIBUTE_TYPE IS NULL THEN 'NEW'
        WHEN D.D365_OPTION_LABEL IS NULL THEN 'UNMAPPED'
        WHEN O.OPTION_VALUE IS NULL THEN 'NO_D365_OPTION'
        ELSE 'MAPPED'
    END AS MAP_STATUS,
    D.NOTE
FROM RE_VALUES AS R
LEFT JOIN DECISIONS AS D ON R.RE_TRIBUTE_TYPE = D.RE_TRIBUTE_TYPE
LEFT JOIN RAW.DYNAMICS.VW_ODS_METADATA_OPTIONS AS O
    ON
        O.ENTITY_LOGICALNAME = 'msnfp_tributeormemory'
        AND O.ATTRIBUTE_LOGICALNAME = 'msnfp_tributeormemorytypecode'
        AND UPPER(TRIM(D.D365_OPTION_LABEL)) = UPPER(TRIM(O.OPTION_LABEL));