create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_APPEAL_EVENT(
	RE_APPEAL_NAME,
	YEAR_ASKED,
	D365_EVENT_CODE,
	NOTE
) as
-- Maps an RE appeal and year to a D365 event, for proposals that load as event
-- packages. Empty until NAS supplies the rule. Proposals with no row here are
-- held. The rule is a reviewed list, not a string parse, because a string rule
-- breaks silently.
SELECT
    NULL::VARCHAR AS RE_APPEAL_NAME,
    NULL::VARCHAR AS YEAR_ASKED,
    NULL::VARCHAR AS D365_EVENT_CODE,
    NULL::VARCHAR AS NOTE
WHERE FALSE;