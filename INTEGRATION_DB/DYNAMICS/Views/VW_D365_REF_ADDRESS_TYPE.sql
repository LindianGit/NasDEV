create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_ADDRESS_TYPE(
	D365_TABLE,
	ADDRESS_SLOT,
	D365_ATTRIBUTE,
	RE_ADDRESS_TYPE,
	D365_OPTION_LABEL,
	D365_OPTION_VALUE,
	MAP_STATUS,
	NOTE
) as
-- RE address type to the D365 address type option, per table and address slot.
-- RE types come from the live RE data. The decisions are the rule for each
-- slot. The option value comes from the D365 metadata by label, because each
-- slot has its own list. MAP_STATUS: MAPPED, UNMAPPED (decided: no D365
-- option), NEW (an RE type with no decision), NO_D365_OPTION (the label is not
-- in the metadata). Incomplete is never emitted.
WITH RE_VALUES AS (
    SELECT DISTINCT TRIM(ADDRESSTYPEDESCRIPTION) AS RE_ADDRESS_TYPE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTADDRESSES
    WHERE NULLIF(TRIM(ADDRESSTYPEDESCRIPTION), '') IS NOT NULL
),

DECISIONS AS (
    SELECT
        COLUMN1 AS D365_TABLE,
        COLUMN2 AS ADDRESS_SLOT,
        COLUMN3 AS RE_ADDRESS_TYPE,
        COLUMN4 AS D365_OPTION_LABEL,
        COLUMN5 AS NOTE
    FROM
        VALUES
        (
            'contact',
            1,
            'Home',
            'Primary',
            'Slot 1 takes the preferred address of any type'
        ),
        (
            'contact',
            1,
            'Business',
            'Business',
            'Slot 1 takes the preferred address of any type'
        ),
        ('contact', 1, 'Previous address', NULL, 'No D365 option: left empty'),
        (
            'contact',
            1,
            'Alternate Address',
            'Alternate',
            'Slot 1 takes the preferred address of any type'
        ),
        ('contact', 1, 'Branch', NULL, 'No D365 option: left empty'),
        (
            'contact',
            1,
            'RE 7 Conversion - Spouse Home',
            NULL,
            'No D365 option: left empty'
        ),
        ('contact', 1, 'Delivery', NULL, 'No D365 option: left empty'),
        ('contact', 1, 'Regional Office', NULL, 'No D365 option: left empty'),
        (
            'contact',
            1,
            'RE 7 Conversion - Relation',
            NULL,
            'No D365 option: left empty'
        ),
        (
            'contact',
            1,
            'RE 7 Conversion - Contact',
            NULL,
            'No D365 option: left empty'
        ),
        (
            'contact',
            1,
            'RE 7 Conversion - Affiliation',
            NULL,
            'No D365 option: left empty'
        ),
        ('contact', 1, 'Parent Address', NULL, 'No D365 option: left empty'),
        (
            'contact',
            1,
            'Aspergers United Address',
            NULL,
            'No D365 option: left empty'
        ),
        (
            'contact',
            1,
            'RE 7 Conversion - Employment',
            NULL,
            'No D365 option: left empty'
        ),
        (
            'account',
            1,
            'Home',
            'Primary',
            'Slot 1 takes the preferred address of any type'
        ),
        (
            'account',
            1,
            'Business',
            'Business',
            'Slot 1 takes the preferred address of any type'
        ),
        ('account', 1, 'Previous address', NULL, 'No D365 option: left empty'),
        (
            'account',
            1,
            'Alternate Address',
            'Alternative',
            'Slot 1 takes the preferred address of any type'
        ),
        ('account', 1, 'Branch', NULL, 'No D365 option: left empty'),
        (
            'account',
            1,
            'RE 7 Conversion - Spouse Home',
            NULL,
            'No D365 option: left empty'
        ),
        ('account', 1, 'Delivery', NULL, 'No D365 option: left empty'),
        ('account', 1, 'Regional Office', NULL, 'No D365 option: left empty'),
        (
            'account',
            1,
            'RE 7 Conversion - Relation',
            NULL,
            'No D365 option: left empty'
        ),
        (
            'account',
            1,
            'RE 7 Conversion - Contact',
            NULL,
            'No D365 option: left empty'
        ),
        (
            'account',
            1,
            'RE 7 Conversion - Affiliation',
            NULL,
            'No D365 option: left empty'
        ),
        ('account', 1, 'Parent Address', NULL, 'No D365 option: left empty'),
        (
            'account',
            1,
            'Aspergers United Address',
            NULL,
            'No D365 option: left empty'
        ),
        (
            'account',
            1,
            'RE 7 Conversion - Employment',
            NULL,
            'No D365 option: left empty'
        ),
        (
            'contact',
            2,
            'Business',
            'Business',
            'Slot 2 holds Business addresses only'
        ),
        (
            'contact',
            3,
            'Alternate Address',
            'Alternate',
            'Slot 3 holds Alternate Address addresses only'
        )
),

SLOTS AS (
    -- Slot 1 of each table takes every RE type, so a new type shows up as NEW.
    SELECT
        T.COLUMN1 AS D365_TABLE,
        1 AS ADDRESS_SLOT,
        R.RE_ADDRESS_TYPE
    FROM RE_VALUES AS R
    CROSS JOIN VALUES ('contact'), ('account') AS T
    UNION ALL
    -- Slots 2 and 3 only hold the one type the decision names.
    SELECT
        D.D365_TABLE,
        D.ADDRESS_SLOT,
        D.RE_ADDRESS_TYPE
    FROM DECISIONS AS D
    INNER JOIN RE_VALUES AS R ON D.RE_ADDRESS_TYPE = R.RE_ADDRESS_TYPE
    WHERE D.ADDRESS_SLOT > 1
)

SELECT
    S.D365_TABLE,
    S.ADDRESS_SLOT,
    'address' || S.ADDRESS_SLOT || '_addresstypecode' AS D365_ATTRIBUTE,
    S.RE_ADDRESS_TYPE,
    D.D365_OPTION_LABEL,
    O.OPTION_VALUE AS D365_OPTION_VALUE,
    CASE
        WHEN D.RE_ADDRESS_TYPE IS NULL THEN 'NEW'
        WHEN D.D365_OPTION_LABEL IS NULL THEN 'UNMAPPED'
        WHEN O.OPTION_VALUE IS NULL THEN 'NO_D365_OPTION'
        ELSE 'MAPPED'
    END AS MAP_STATUS,
    D.NOTE
FROM SLOTS AS S
LEFT JOIN DECISIONS AS D
    ON
        S.D365_TABLE = D.D365_TABLE
        AND S.ADDRESS_SLOT = D.ADDRESS_SLOT
        AND S.RE_ADDRESS_TYPE = D.RE_ADDRESS_TYPE
LEFT JOIN RAW.DYNAMICS.VW_ODS_METADATA_OPTIONS AS O
    ON
        S.D365_TABLE = O.ENTITY_LOGICALNAME
        AND 'address' || S.ADDRESS_SLOT || '_addresstypecode'
        = O.ATTRIBUTE_LOGICALNAME
        AND UPPER(TRIM(D.D365_OPTION_LABEL)) = UPPER(TRIM(O.OPTION_LABEL));