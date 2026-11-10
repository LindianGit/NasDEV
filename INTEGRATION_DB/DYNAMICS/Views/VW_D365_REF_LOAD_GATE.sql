create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_LOAD_GATE(
	GATE_CODE,
	D365_TABLE,
	ROW_CONDITION_KEY,
	ROW_CONDITION_DATE,
	IS_OPEN,
	OWNER,
	DESCRIPTION
) as
-- The central list of open items that hold migration rows back. One row per
-- gate and table. Every migration view joins it. A row is held with
-- HOLD_REASON GATE:<GATE_CODE> while IS_OPEN is TRUE and the row is covered. A
-- gate covers the whole table, or only the rows chosen by ROW_CONDITION_KEY,
-- which the consuming view evaluates (for example GIFT_AID_WINDOW).
-- ROW_CONDITION_DATE is the date a row condition compares against. It is fixed,
-- never CURRENT_DATE, so the views give the same output on every query. For
-- GIFT_AID_WINDOW, a gift dated on or after it is inside the claim window. Move
-- it by hand when a load starts. To close a gate: set IS_OPEN to FALSE,
-- redeploy, and the rows move from HOLD to CREATE. A closed gate row stays in
-- the list as a record.
SELECT
    COLUMN1 AS GATE_CODE,
    COLUMN2 AS D365_TABLE,
    COLUMN3 AS ROW_CONDITION_KEY,
    CASE
        WHEN COLUMN3 = 'GIFT_AID_WINDOW'
            -- ASSUMED: gifts from 2022-04-06 (start of the 2022/23 tax year) are still
            -- claimable until 2027-04-05; the Gift Aid owner must confirm the rule
            THEN DATE '2022-04-06'
    END AS ROW_CONDITION_DATE,
    COLUMN4 AS IS_OPEN,
    COLUMN5 AS OWNER,
    COLUMN6 AS DESCRIPTION
FROM
    VALUES
    (
        'EVENT_FIELD_RULES',
        'msnfp_event',
        NULL,
        TRUE,
        'D365 team',
        'The virtual flag, start and end times, owning team and unique event id rules are not agreed with the D365 team.'
    ),
    (
        'THIRDPARTY_SOURCE_NAME',
        'mha_thirdpartysupporterreference',
        NULL,
        TRUE,
        'Data team',
        'The third-party source row for Raiser''s Edge must be read from D365, and its spelling confirmed, before references load.'
    ),
    (
        'ADDRESS_SLOT_RULES',
        'mha_addresschange',
        NULL,
        TRUE,
        'NAS',
        'NAS has not confirmed which addresses fill contact slots 2 and 3, so the addresses left over for history are not fixed.'
    ),
    (
        'ADDRESS_TYPE_TRANSLATION',
        'mha_addresschange',
        NULL,
        TRUE,
        'NAS',
        'NAS has not confirmed that an RE Home address is a D365 Primary address.'
    ),
    (
        'COUNTRY_MATCHING',
        'mha_addresschange',
        NULL,
        TRUE,
        'D365 team and NAS',
        'The D365 ISO country list is not loaded and the country alias list is not signed off.'
    ),
    (
        'CANVASSER_RELATIONSHIPS',
        'connection',
        NULL,
        TRUE,
        'NAS',
        'NAS has not confirmed that relationships of canvassers are dropped at either end.'
    ),
    (
        'CONNECTION_DIRECTION',
        'connection',
        NULL,
        TRUE,
        'Data team and D365 team',
        'The direction of the two roles is untested in DEV, and the one-row-per-pair rule is unproven.'
    ),
    (
        'RETIRED_CONSTITUENT_TYPES',
        'mha_relationship',
        NULL,
        TRUE,
        'NAS',
        'NAS has not said whether retired constituent types (names starting with z) are loaded.'
    ),
    (
        'CONSENT_RULES_SIGN_OFF',
        'mha_consent',
        NULL,
        TRUE,
        'NAS data protection',
        'NAS data protection has not signed off the rules that turn RE preferences into consent values.'
    ),
    (
        'CONSENT_SOURCE',
        'mha_consent',
        NULL,
        TRUE,
        'D365 team',
        'The consent source column and its Raiser''s Edge migration row do not exist in D365 yet.'
    ),
    (
        'EXCLUSION_RULES',
        'mhnas_exclusion',
        NULL,
        TRUE,
        'NAS data protection',
        'NAS data protection has not signed off how exclusions map to exclusion lists, or the channel for lottery and raffle opt outs.'
    ),
    (
        'HISTORIC_ACTIVITY_SCOPE',
        'mha_historicactivity',
        NULL,
        TRUE,
        'D365 team and NAS',
        'The source table, the full column list and the scope of historic activity are not agreed.'
    ),
    (
        'TRIBUTE_CUSTOMER_LINK',
        'msnfp_tributeormemory',
        NULL,
        TRUE,
        'D365 team',
        'The D365 team has not named the lookup that links a tribute to its supporter.'
    ),
    (
        'TRIBUTE_SCOPE',
        'msnfp_tributeormemory',
        NULL,
        TRUE,
        'D365 team and NAS',
        'Tributes have no link to the tributee or acknowledgee, and the type map is a judgement call.'
    ),
    (
        'MEMBERSHIP_SCOPE',
        'msnfp_membership',
        NULL,
        TRUE,
        'D365 team and NAS',
        'The full membership column list and scope are not agreed.'
    ),
    (
        'GIFT_TYPE_SCOPE',
        'msnfp_donorcommitment',
        NULL,
        TRUE,
        'NAS finance',
        'Finance has not confirmed which gift types load as pledges and which stay out.'
    ),
    (
        'PLEDGE_STATUS_TERMINATED',
        'msnfp_donorcommitment',
        NULL,
        TRUE,
        'NAS finance',
        'Finance has not confirmed that Terminated pledges load as Cancelled.'
    ),
    (
        'SCHEDULE_STATUS_TEST',
        'msnfp_paymentschedule',
        NULL,
        TRUE,
        'D365 team',
        'A loaded inactive schedule must be shown in DEV not to create transactions or collections, and Held schedules have no D365 status.'
    ),
    (
        'AUTOMATION_ON_LOAD',
        'msnfp_paymentschedule',
        NULL,
        TRUE,
        'D365 team',
        'Plug-ins, flows and rollups that fire on create are not inventoried, bypassed or paused.'
    ),
    (
        'GIFT_TYPE_SCOPE',
        'msnfp_transaction',
        NULL,
        TRUE,
        'NAS finance',
        'Finance has not confirmed which gift types load as transactions and that adjustments and write-offs stay out.'
    ),
    (
        'GIFT_SPLIT_ATTRIBUTION',
        'msnfp_transaction',
        NULL,
        TRUE,
        'NAS and D365 team',
        'Campaign, appeal and package sit on splits. The largest-split rule is not confirmed, and the D365 team has not said whether lines can carry them.'
    ),
    (
        'AUTOMATION_ON_LOAD',
        'msnfp_transaction',
        NULL,
        TRUE,
        'D365 team',
        'Plug-ins, flows and rollups that fire on create are not inventoried, bypassed or paused.'
    ),
    (
        'GIFT_AID_CLAIM_STATUS',
        'msnfp_transaction',
        'GIFT_AID_WINDOW',
        TRUE,
        'RE team and NAS Gift Aid owner',
        'RE has no source for the Gift Aid claim status. Gifts inside the claim window are held until it exists.'
    ),
    (
        'GIFT_TYPE_SCOPE',
        'msnfp_designatedcredit',
        NULL,
        TRUE,
        'NAS finance',
        'Finance has not confirmed which gift types load as transactions, so their lines are held too.'
    ),
    (
        'DESIGNATED_CREDIT_AMOUNT',
        'msnfp_designatedcredit',
        NULL,
        TRUE,
        'D365 team',
        'The D365 team has not confirmed that the amount column is the line amount.'
    ),
    (
        'AUTOMATION_ON_LOAD',
        'msnfp_designatedcredit',
        NULL,
        TRUE,
        'D365 team',
        'Plug-ins, flows and rollups that fire on create are not inventoried, bypassed or paused.'
    ),
    (
        'GIFT_AID_CLAIM_STATUS',
        'msnfp_designatedcredit',
        'GIFT_AID_WINDOW',
        TRUE,
        'RE team and NAS Gift Aid owner',
        'RE has no source for the Gift Aid claim status. Lines of gifts inside the claim window are held until it exists.'
    ),
    (
        'PROPOSAL_APPEAL_SPLIT',
        'opportunity',
        NULL,
        TRUE,
        'NAS fundraising',
        'The list of community appeals that decides which proposals are opportunities is not confirmed.'
    ),
    (
        'PROPOSAL_OUTCOME_MAP',
        'opportunity',
        NULL,
        TRUE,
        'NAS fundraising',
        'NAS has not confirmed the outcome for Completed, Transferred and the other open statuses.'
    ),
    (
        'PARTICIPANT_STATUS_MAP',
        'msnfp_eventpackage',
        'STREAM_PARTICIPANTS',
        TRUE,
        'NAS events team',
        'NAS has not completed the participant status table for OP, GB and the other non-status values.'
    ),
    (
        'PROPOSAL_APPEAL_SPLIT',
        'msnfp_eventpackage',
        'STREAM_PROPOSALS',
        TRUE,
        'NAS fundraising',
        'The list of community appeals that decides which proposals are event packages is not confirmed.'
    ),
    (
        'PROPOSAL_OUTCOME_MAP',
        'msnfp_eventpackage',
        'STREAM_PROPOSALS',
        TRUE,
        'NAS fundraising',
        'NAS has not supplied the event package status for proposal statuses.'
    ),
    ('APPEAL_EVENT_RULE', 'msnfp_eventpackage', 'STREAM_PROPOSALS', TRUE, 'NAS', 'NAS has not supplied the rule that links an appeal and year to an event.');