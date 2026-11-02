-- Privacy rights baseline: requests, download my information, breach
-- register, parental consent and marketing emails. Reuses access_rules.test.sql
-- people: owner Olive (...a0), operations admin (...b0), parent P2 (...02).
-- Adds parent Rita (...71) with child Rory, and parent Stan (...72).

select tests.claims(null);
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000071', 'rita@example.com', '{"signup_as":"parent","full_name":"Rita Rights"}'),
  ('00000000-0000-0000-0000-000000000072', 'stan@example.com', '{"signup_as":"parent","full_name":"Stan Other"}');

select tests.claims('00000000-0000-0000-0000-000000000071');
set role authenticated;
create temp table rory as
  select public.add_my_child('Rory Rights', (current_date - interval '8 years')::date, 'SA', 'Year 3', 'Hill PS', '[{"subject": "English"}]') as id;
reset role;
grant select on rory to authenticated;

-- ===========================================================================
-- Parental consent, renewed every 12 months
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000071');
set role authenticated;
select tests.eq((select count(*) from public.children_needing_consent()), 1, 'new child needs consent');
select public.give_parental_consent((select id from rory), '2026-11');
select tests.eq((select count(*) from public.children_needing_consent()), 0, 'consent given');
reset role;

-- Consent older than 12 months no longer counts.
update public.consent_records set given_at = now() - interval '13 months'
where student_id = (select id from rory) and kind = 'parental_consent';
select tests.claims('00000000-0000-0000-0000-000000000071');
set role authenticated;
select tests.eq((select count(*) from public.children_needing_consent()), 1, 'consent expires after 12 months');
select public.give_parental_consent((select id from rory), '2026-11');
reset role;

-- Another parent can't consent for someone else's child.
select tests.claims('00000000-0000-0000-0000-000000000072');
set role authenticated;
select tests.fails($$select public.give_parental_consent((select id from rory), '2026-11')$$, 'stranger gives consent');
select tests.eq((select count(*) from public.children_needing_consent()), 0, 'stranger sees no children');
reset role;

-- ===========================================================================
-- Marketing emails: off unless turned on
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000071');
set role authenticated;
select tests.eq(public.my_marketing_email()::int, 0, 'marketing off by default');
select public.set_marketing_email(true, '2026-11');
select public.set_marketing_email(true, '2026-11');
select tests.eq(public.my_marketing_email()::int, 1, 'marketing turned on');
select tests.eq((select count(*) from public.consent_records where kind = 'marketing_email' and withdrawn_at is null), 1, 'turned on once only');
select public.set_marketing_email(false, '2026-11');
select tests.eq(public.my_marketing_email()::int, 0, 'marketing turned off');
reset role;

-- ===========================================================================
-- Privacy requests
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000071');
set role authenticated;
create temp table req as
  select public.make_privacy_request('correction', 'Rory''s school is wrong', (select id from rory)) as id;
select public.make_privacy_request('complaint', 'I was emailed after asking not to be');
select tests.eq((select count(*) from public.privacy_requests), 2, 'person sees own requests');
select tests.eq((select count(*) from public.privacy_requests where due_on = current_date + 28), 2, 'due 28 days after it arrives');
select tests.fails($$select public.make_privacy_request('selling', 'x x x')$$, 'unknown request kind');
select tests.fails($$select public.make_privacy_request('access', '  ')$$, 'empty request');
select tests.fails($$insert into public.privacy_requests (account_id, kind, details) values (auth.uid(), 'access', 'direct')$$, 'insert directly');
select tests.fails($$update public.privacy_requests set status = 'done'$$, 'person closes own request');
select tests.fails($$select public.update_privacy_request((select id from req), 'done', 'ok')$$, 'person handles a request');
reset role;
grant select on req to authenticated;

-- A request about someone else's child is refused; others see nothing.
select tests.claims('00000000-0000-0000-0000-000000000072');
set role authenticated;
select tests.fails($$select public.make_privacy_request('deletion', 'Delete this child', (select id from rory))$$, 'request about a stranger''s child');
select tests.eq((select count(*) from public.privacy_requests), 0, 'other parent sees no requests');
reset role;

-- Too many requests in a day are refused.
select tests.claims('00000000-0000-0000-0000-000000000072');
set role authenticated;
select public.make_privacy_request('other', 'Question ' || g) from generate_series(1, 10) g;
select tests.fails($$select public.make_privacy_request('other', 'One more')$$, 'eleventh request in a day');
reset role;

-- Support and finance admins can't see requests; operations can handle them.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.privacy_requests where account_id = '00000000-0000-0000-0000-000000000071'), 2, 'operations admin sees requests');
select tests.fails($$select public.update_privacy_request((select id from req), 'refused')$$, 'refuse with no reason');
select tests.fails($$select public.update_privacy_request((select id from req), 'in_progress', null, current_date + 200, 'Complex')$$, 'extend past 90 days');
select tests.fails($$select public.update_privacy_request((select id from req), 'in_progress', null, current_date + 40)$$, 'extend with no reason');
select public.update_privacy_request((select id from req), 'in_progress', null, current_date + 40, 'Checking with the school');
select tests.eq((select count(*) from public.privacy_requests where id = (select id from req) and acknowledged_at is not null and extended_to = current_date + 40), 1, 'acknowledged and extended');
select tests.fails($$select public.update_privacy_request((select id from req), 'in_progress', null, current_date + 50, 'Again')$$, 'extend twice');
select public.update_privacy_request((select id from req), 'done', 'School corrected to Hill PS');
select tests.fails($$select public.update_privacy_request((select id from req), 'in_progress')$$, 'reopen a closed request');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000071');
set role authenticated;
select tests.eq((select count(*) from public.privacy_requests where status = 'done' and outcome like 'School corrected%'), 1, 'person sees the outcome');
reset role;

-- ===========================================================================
-- Download my information
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000071');
set role authenticated;
create temp table export as select public.my_data_export() as data;
select public.log_my_data_export();
reset role;
select tests.eq(jsonb_array_length((select data -> 'records' -> 'accounts' from export)), 1, 'export has own account');
select tests.eq(jsonb_array_length((select data -> 'records' -> 'students' from export)), 1, 'export has own child');
select tests.eq((select count(*) from export where data -> 'records' -> 'students' -> 0 ->> 'full_name' = 'Rory Rights'), 1, 'it is the right child');
select tests.eq(jsonb_array_length((select data -> 'records' -> 'consent_records' from export)), 3, 'export has consents (child twice, marketing once)');
select tests.eq(jsonb_array_length((select data -> 'records' -> 'privacy_requests' from export)), 2, 'export has own requests');
select tests.eq(jsonb_array_length((select data -> 'records' -> 'account_private' from export)), 1, 'export has own contact details');
select tests.eq((select count(*) from export where data::text like '%stan@example.com%' or data::text like '%Stan Other%'), 0, 'nothing about other families');
select tests.eq((select count(*) from export where data -> 'records' ? 'audit_log'), 0, 'activity log not included');
select tests.eq((select count(*) from public.audit_log where action = 'export_own_data' and actor_id = '00000000-0000-0000-0000-000000000071'), 1, 'download is logged');

-- The other parent's export holds nothing about Rita's family.
select tests.claims('00000000-0000-0000-0000-000000000072');
set role authenticated;
select tests.eq((select count(*) from (select public.my_data_export() as d) x where d::text like '%Rory%' or d::text like '%rita@example.com%'), 0, 'other parent''s export is separate');
reset role;

select tests.claims(null);
select tests.fails($$select public.my_data_export()$$, 'signed-out export');

-- ===========================================================================
-- Breach register
-- ===========================================================================

-- Parents can't see or add to it.
select tests.claims('00000000-0000-0000-0000-000000000071');
set role authenticated;
select tests.fails($$insert into public.privacy_incidents (title, what_happened) values ('x x', 'y y y')$$, 'parent records a breach');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
insert into public.privacy_incidents (title, what_happened, found_at, regions, children_affected)
values ('Invoice sent to wrong family', 'One invoice emailed to the wrong parent', now() - interval '4 days', '{AU,NZ}', true);
select tests.eq((select count(*) from public.privacy_incidents where recorded_by = '00000000-0000-0000-0000-0000000000b0'), 1, 'recorder stamped');
select tests.eq((select count(*) from public.privacy_incident_deadlines where decision_overdue), 1, '72-hr decision shown as overdue');
select tests.eq((select count(*) from public.privacy_incident_deadlines where next_step like 'Contain it%'), 1, 'next step is to contain it');
select tests.fails($$update public.privacy_incidents set found_at = now()$$, 'move the found date');
select tests.fails($$insert into public.privacy_incidents (title, what_happened, regions) values ('x x', 'y y y', '{MARS}')$$, 'unknown region');
select tests.fails($$insert into public.privacy_incidents (title, what_happened, found_at) values ('x x', 'y y y', now() + interval '1 day')$$, 'found in the future');
update public.privacy_incidents set contained_at = now(), serious_harm_likely = true, decision_reason = 'Child''s name and address';
select tests.eq((select count(*) from public.privacy_incidents where assessed_at is not null), 1, 'assessment time stamped');
select tests.eq((select count(*) from public.privacy_incident_deadlines where next_step like 'Tell the regulators%'), 1, 'next step is to tell regulators');
select tests.fails($$update public.privacy_incidents set closed_at = now()$$, 'close without telling regulators');
update public.privacy_incidents set regulators_told_at = now(), regulators_told = 'OAIC, NZ OPC', people_told_at = now(), closed_at = now();
-- A closed record matches no update rule, so an update changes nothing.
update public.privacy_incidents set lessons = 'changed later';
select tests.eq((select count(*) from public.privacy_incidents where lessons is not null), 0, 'closed breach unchanged');
select tests.fails($$delete from public.privacy_incidents$$, 'delete a breach record');
reset role;

-- ===========================================================================
-- Old closed records are deleted after the activity log period
-- ===========================================================================

select tests.claims(null);
update public.privacy_requests set received_at = now() - interval '8 years', closed_at = now() - interval '8 years', due_on = current_date - 2900
where id = (select id from req);
select private.purge_privacy_records();
select tests.eq((select count(*) from public.privacy_requests where id = (select id from req)), 0, 'old closed request deleted');
select tests.eq((select count(*) from public.privacy_requests where account_id = '00000000-0000-0000-0000-000000000071'), 1, 'open request kept');
select tests.eq((select count(*) from public.privacy_incidents), 1, 'recent breach record kept');

drop table rory, req, export;

do $$ begin raise notice 'privacy rights: all checks passed'; end $$;
