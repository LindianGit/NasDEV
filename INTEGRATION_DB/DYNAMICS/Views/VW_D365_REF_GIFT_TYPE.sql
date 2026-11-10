create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_GIFT_TYPE(
	RE_GIFT_TYPE_CODE,
	RE_GIFT_TYPE,
	D365_TARGET,
	MAP_STATUS,
	NOTE
) as
-- Where each RE gift type loads: TRANSACTION, COMMITMENT, SCHEDULE or
-- NOT_LOADED. RE types come from the live gifts. Loading a header (pledge,
-- regular giving) as a transaction would count the money twice. MAP_STATUS:
-- MAPPED, or NEW for an RE type with no decision (held by the consumers).
WITH RE_VALUES AS (
    SELECT DISTINCT
        GIFTTYPECODE AS RE_GIFT_TYPE_CODE,
        GIFTTYPEDESCRIPTION AS RE_GIFT_TYPE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_GIFTS
    WHERE GIFTTYPECODE IS NOT NULL
),

DECISIONS AS (
    SELECT
        COLUMN1 AS RE_GIFT_TYPE_CODE,
        COLUMN2 AS D365_TARGET,
        COLUMN3 AS NOTE
    FROM
        VALUES
        (1, 'TRANSACTION', 'Gift'),
        (31, 'TRANSACTION', 'Payment against a regular giving schedule'),
        (2, 'TRANSACTION', 'Payment against a pledge'),
        (19, 'TRANSACTION', 'Payment against a pledge'),
        (3, 'TRANSACTION', 'Payment against a pledge'),
        (16, 'TRANSACTION', 'Payment against a pledge'),
        (15, 'TRANSACTION', 'Gift'),
        (9, 'TRANSACTION', 'Gift'),
        (18, 'TRANSACTION', 'Gift'),
        (
            8,
            'COMMITMENT',
            'Pledge header: loads as a donor commitment, not a transaction'
        ),
        (
            27,
            'COMMITMENT',
            'Pledge header: loads as a donor commitment, not a transaction'
        ),
        (30, 'SCHEDULE', 'Regular giving header: loads as a payment schedule'),
        (
            28,
            'NOT_LOADED',
            'Kept in Snowflake; finance must confirm it stays out'
        ),
        (
            33,
            'NOT_LOADED',
            'Kept in Snowflake; finance must confirm it stays out'
        ),
        (
            21,
            'NOT_LOADED',
            'Kept in Snowflake; finance must confirm it stays out'
        ),
        (
            22,
            'NOT_LOADED',
            'Kept in Snowflake; finance must confirm it stays out'
        ),
        (
            34,
            'NOT_LOADED',
            'Kept in Snowflake; finance must confirm it stays out'
        )
)

SELECT
    R.RE_GIFT_TYPE_CODE,
    R.RE_GIFT_TYPE,
    D.D365_TARGET,
    IFF(D.RE_GIFT_TYPE_CODE IS NULL, 'NEW', 'MAPPED') AS MAP_STATUS,
    D.NOTE
FROM RE_VALUES AS R
LEFT JOIN DECISIONS AS D ON R.RE_GIFT_TYPE_CODE = D.RE_GIFT_TYPE_CODE;