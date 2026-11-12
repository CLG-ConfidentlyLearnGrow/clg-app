-- Privacy rights baseline: requests, download my information, breach
-- register, parental consent and marketing emails. Reuses access_rules.test.sql
-- people: owner Olive (...a0), operations admin (...b0), parent P2 (...02).
-- Adds parent Rita (...71) with child Rory, and parent Stan (...72).

select tests.claims(null); -- Signs out, so no one is signed in.
insert into auth.users (id, email, raw_user_meta_data) values -- Adds two test parents:
  ('00000000-0000-0000-0000-000000000071', 'rita@example.com', '{"signup_as":"parent","full_name":"Rita Rights"}'), -- Rita,
  ('00000000-0000-0000-0000-000000000072', 'stan@example.com', '{"signup_as":"parent","full_name":"Stan Other"}'); -- and Stan.

select tests.claims('00000000-0000-0000-0000-000000000071'); -- Signs in as test account ...71.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
create temp table rory as -- Rita adds a child, Rory, keeping the id in a short-lived table:
  select public.add_my_child('Rory Rights', (current_date - interval '8 years')::date, 'SA', 'Year 3', 'Hill PS', '[{"subject": "English"}]') as id; -- (aged 8, Year 3, English).
reset role; -- Goes back to the all-powerful test user (access rules off).
grant select on rory to authenticated; -- Lets signed-in users read that table.

-- ===========================================================================
-- Parental consent, renewed every 12 months
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000071'); -- Signs in as test account ...71.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.children_needing_consent()), 1, 'new child needs consent'); -- Checks: new child needs consent.
select public.give_parental_consent((select id from rory), '2026-11'); -- Rita gives parental consent for Rory.
select tests.eq((select count(*) from public.children_needing_consent()), 0, 'consent given'); -- Checks: consent given.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Consent older than 12 months no longer counts.
update public.consent_records set given_at = now() - interval '13 months' -- Makes the consent 13 months old:
where student_id = (select id from rory) and kind = 'parental_consent'; -- (for Rory's parental consent).
select tests.claims('00000000-0000-0000-0000-000000000071'); -- Signs in as test account ...71.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.children_needing_consent()), 1, 'consent expires after 12 months'); -- Checks: consent expires after 12 months.
select public.give_parental_consent((select id from rory), '2026-11'); -- Rita gives consent again.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Another parent can't consent for someone else's child.
select tests.claims('00000000-0000-0000-0000-000000000072'); -- Signs in as test account ...72.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.give_parental_consent((select id from rory), '2026-11')$$, 'stranger gives consent'); -- Checks this is refused: stranger gives consent.
select tests.eq((select count(*) from public.children_needing_consent()), 0, 'stranger sees no children'); -- Checks: stranger sees no children.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Marketing emails: off unless turned on
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000071'); -- Signs in as test account ...71.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(public.my_marketing_email()::int, 0, 'marketing off by default'); -- Checks: marketing off by default.
select public.set_marketing_email(true, '2026-11'); -- Rita says yes to marketing emails.
select public.set_marketing_email(true, '2026-11'); -- And again (should not repeat).
select tests.eq(public.my_marketing_email()::int, 1, 'marketing turned on'); -- Checks: marketing turned on.
select tests.eq((select count(*) from public.consent_records where kind = 'marketing_email' and withdrawn_at is null), 1, 'turned on once only'); -- Checks: turned on once only.
select public.set_marketing_email(false, '2026-11'); -- Rita says no to marketing emails.
select tests.eq(public.my_marketing_email()::int, 0, 'marketing turned off'); -- Checks: marketing turned off.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Privacy requests
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000071'); -- Signs in as test account ...71.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
create temp table req as -- Rita asks for a correction, keeping its id in a short-lived table:
  select public.make_privacy_request('correction', 'Rory''s school is wrong', (select id from rory)) as id; -- (Rory's school is wrong).
select public.make_privacy_request('complaint', 'I was emailed after asking not to be'); -- Rita makes a complaint.
select tests.eq((select count(*) from public.privacy_requests), 2, 'person sees own requests'); -- Checks: person sees own requests.
select tests.eq((select count(*) from public.privacy_requests where due_on = current_date + 28), 2, 'due 28 days after it arrives'); -- Checks: due 28 days after it arrives.
select tests.fails($$select public.make_privacy_request('selling', 'x x x')$$, 'unknown request kind'); -- Checks this is refused: unknown request kind.
select tests.fails($$select public.make_privacy_request('access', '  ')$$, 'empty request'); -- Checks this is refused: empty request.
select tests.fails($$insert into public.privacy_requests (account_id, kind, details) values (auth.uid(), 'access', 'direct')$$, 'insert directly'); -- Checks this is refused: insert directly.
select tests.fails($$update public.privacy_requests set status = 'done'$$, 'person closes own request'); -- Checks this is refused: person closes own request.
select tests.fails($$select public.update_privacy_request((select id from req), 'done', 'ok')$$, 'person handles a request'); -- Checks this is refused: person handles a request.
reset role; -- Goes back to the all-powerful test user (access rules off).
grant select on req to authenticated; -- Lets signed-in users read that table.

-- A request about someone else's child is refused; others see nothing.
select tests.claims('00000000-0000-0000-0000-000000000072'); -- Signs in as test account ...72.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.make_privacy_request('deletion', 'Delete this child', (select id from rory))$$, 'request about a stranger''s child'); -- Checks this is refused: request about a stranger's child.
select tests.eq((select count(*) from public.privacy_requests), 0, 'other parent sees no requests'); -- Checks: other parent sees no requests.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Too many requests in a day are refused.
select tests.claims('00000000-0000-0000-0000-000000000072'); -- Signs in as test account ...72.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.make_privacy_request('other', 'Question ' || g) from generate_series(1, 10) g; -- Makes 10 more requests at once.
select tests.fails($$select public.make_privacy_request('other', 'One more')$$, 'eleventh request in a day'); -- Checks this is refused: eleventh request in a day.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Support and finance admins can't see requests; operations can handle them.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.privacy_requests where account_id = '00000000-0000-0000-0000-000000000071'), 2, 'operations admin sees requests'); -- Checks: operations admin sees requests.
select tests.fails($$select public.update_privacy_request((select id from req), 'refused')$$, 'refuse with no reason'); -- Checks this is refused: refuse with no reason.
select tests.fails($$select public.update_privacy_request((select id from req), 'in_progress', null, current_date + 200, 'Complex')$$, 'extend past 90 days'); -- Checks this is refused: extend past 90 days.
select tests.fails($$select public.update_privacy_request((select id from req), 'in_progress', null, current_date + 40)$$, 'extend with no reason'); -- Checks this is refused: extend with no reason.
select public.update_privacy_request((select id from req), 'in_progress', null, current_date + 40, 'Checking with the school'); -- An admin marks the correction as in progress, with a new due date.
select tests.eq((select count(*) from public.privacy_requests where id = (select id from req) and acknowledged_at is not null and extended_to = current_date + 40), 1, 'acknowledged and extended'); -- Checks: acknowledged and extended.
select tests.fails($$select public.update_privacy_request((select id from req), 'in_progress', null, current_date + 50, 'Again')$$, 'extend twice'); -- Checks this is refused: extend twice.
select public.update_privacy_request((select id from req), 'done', 'School corrected to Hill PS'); -- An admin marks it done.
select tests.fails($$select public.update_privacy_request((select id from req), 'in_progress')$$, 'reopen a closed request'); -- Checks this is refused: reopen a closed request.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000071'); -- Signs in as test account ...71.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.privacy_requests where status = 'done' and outcome like 'School corrected%'), 1, 'person sees the outcome'); -- Checks: person sees the outcome.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Download my information
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000071'); -- Signs in as test account ...71.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
create temp table export as select public.my_data_export() as data; -- Rita downloads her data, kept in a short-lived table.
select public.log_my_data_export(); -- Records that she downloaded it.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq(jsonb_array_length((select data -> 'records' -> 'accounts' from export)), 1, 'export has own account'); -- Checks: export has own account.
select tests.eq(jsonb_array_length((select data -> 'records' -> 'students' from export)), 1, 'export has own child'); -- Checks: export has own child.
select tests.eq((select count(*) from export where data -> 'records' -> 'students' -> 0 ->> 'full_name' = 'Rory Rights'), 1, 'it is the right child'); -- Checks: it is the right child.
select tests.eq(jsonb_array_length((select data -> 'records' -> 'consent_records' from export)), 3, 'export has consents (child twice, marketing once)'); -- Checks: export has consents (child twice, marketing once).
select tests.eq(jsonb_array_length((select data -> 'records' -> 'privacy_requests' from export)), 2, 'export has own requests'); -- Checks: export has own requests.
select tests.eq(jsonb_array_length((select data -> 'records' -> 'account_private' from export)), 1, 'export has own contact details'); -- Checks: export has own contact details.
select tests.eq((select count(*) from export where data::text like '%stan@example.com%' or data::text like '%Stan Other%'), 0, 'nothing about other families'); -- Checks: nothing about other families.
select tests.eq((select count(*) from export where data -> 'records' ? 'audit_log'), 0, 'activity log not included'); -- Checks: activity log not included.
select tests.eq((select count(*) from public.audit_log where action = 'export_own_data' and actor_id = '00000000-0000-0000-0000-000000000071'), 1, 'download is logged'); -- Checks: download is logged.

-- The other parent's export holds nothing about Rita's family.
select tests.claims('00000000-0000-0000-0000-000000000072'); -- Signs in as test account ...72.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from (select public.my_data_export() as d) x where d::text like '%Rory%' or d::text like '%rita@example.com%'), 0, 'other parent''s export is separate'); -- Checks: other parent's export is separate.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
select tests.fails($$select public.my_data_export()$$, 'signed-out export'); -- Checks this is refused: signed-out export.

-- ===========================================================================
-- Breach register
-- ===========================================================================

-- Parents can't see or add to it.
select tests.claims('00000000-0000-0000-0000-000000000071'); -- Signs in as test account ...71.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$insert into public.privacy_incidents (title, what_happened) values ('x x', 'y y y')$$, 'parent records a breach'); -- Checks this is refused: parent records a breach.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.privacy_incidents (title, what_happened, found_at, regions, children_affected) -- Records a privacy incident:
values ('Invoice sent to wrong family', 'One invoice emailed to the wrong parent', now() - interval '4 days', '{AU,NZ}', true); -- an invoice sent to the wrong family, found 4 days ago, affecting a child.
select tests.eq((select count(*) from public.privacy_incidents where recorded_by = '00000000-0000-0000-0000-0000000000b0'), 1, 'recorder stamped'); -- Checks: recorder stamped.
select tests.eq((select count(*) from public.privacy_incident_deadlines where decision_overdue), 1, '72-hr decision shown as overdue'); -- Checks: 72-hr decision shown as overdue.
select tests.eq((select count(*) from public.privacy_incident_deadlines where next_step like 'Contain it%'), 1, 'next step is to contain it'); -- Checks: next step is to contain it.
select tests.fails($$update public.privacy_incidents set found_at = now()$$, 'move the found date'); -- Checks this is refused: move the found date.
select tests.fails($$insert into public.privacy_incidents (title, what_happened, regions) values ('x x', 'y y y', '{MARS}')$$, 'unknown region'); -- Checks this is refused: unknown region.
select tests.fails($$insert into public.privacy_incidents (title, what_happened, found_at) values ('x x', 'y y y', now() + interval '1 day')$$, 'found in the future'); -- Checks this is refused: found in the future.
update public.privacy_incidents set contained_at = now(), serious_harm_likely = true, decision_reason = 'Child''s name and address'; -- The incident is contained, and serious harm is likely.
select tests.eq((select count(*) from public.privacy_incidents where assessed_at is not null), 1, 'assessment time stamped'); -- Checks: assessment time stamped.
select tests.eq((select count(*) from public.privacy_incident_deadlines where next_step like 'Tell the regulators%'), 1, 'next step is to tell regulators'); -- Checks: next step is to tell regulators.
select tests.fails($$update public.privacy_incidents set closed_at = now()$$, 'close without telling regulators'); -- Checks this is refused: close without telling regulators.
update public.privacy_incidents set regulators_told_at = now(), regulators_told = 'OAIC, NZ OPC', people_told_at = now(), closed_at = now(); -- Regulators and people are told, and it's closed.
-- A closed record matches no update rule, so an update changes nothing.
update public.privacy_incidents set lessons = 'changed later'; -- Tries to change the lessons learned.
select tests.eq((select count(*) from public.privacy_incidents where lessons is not null), 0, 'closed breach unchanged'); -- Checks: closed breach unchanged.
select tests.fails($$delete from public.privacy_incidents$$, 'delete a breach record'); -- Checks this is refused: delete a breach record.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Old closed records are deleted after the activity log period
-- ===========================================================================

select tests.claims(null); -- Signs out, so no one is signed in.
update public.privacy_requests set received_at = now() - interval '8 years', closed_at = now() - interval '8 years', due_on = current_date - 2900 -- Makes the correction 8 years old:
where id = (select id from req); -- (for Rita's correction).
select private.purge_privacy_records(); -- Clears old privacy records.
select tests.eq((select count(*) from public.privacy_requests where id = (select id from req)), 0, 'old closed request deleted'); -- Checks: old closed request deleted.
select tests.eq((select count(*) from public.privacy_requests where account_id = '00000000-0000-0000-0000-000000000071'), 1, 'open request kept'); -- Checks: open request kept.
select tests.eq((select count(*) from public.privacy_incidents), 1, 'recent breach record kept'); -- Checks: recent breach record kept.

drop table rory, req, export; -- Removes the short-lived tables.

do $$ begin raise notice 'privacy rights: all checks passed'; end $$; -- Prints that every check in this file passed.
