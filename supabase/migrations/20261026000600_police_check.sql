-- CLG's rule: every tutor needs a national police check issued in the last
-- 5 years. A National Police Check covers all of Australia, so it is
-- required for students in every state.

insert into public.check_requirements (state, kind, basis) values
  ('SA', 'police_check', 'student_state'),
  ('NSW', 'police_check', 'student_state'),
  ('VIC', 'police_check', 'student_state'),
  ('QLD', 'police_check', 'student_state'),
  ('WA', 'police_check', 'student_state'),
  ('TAS', 'police_check', 'student_state'),
  ('ACT', 'police_check', 'student_state'),
  ('NT', 'police_check', 'student_state')
on conflict do nothing;

-- Admin entry of a check counts as verification against the screening
-- record, so stamp who did it. A police check counts for 5 years from the
-- date it was issued, so its expiry is worked out here.
create or replace function private.stamp_tutor_check()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.kind = 'police_check' then
    if new.completed_on is null or new.completed_on > current_date then
      raise exception 'Enter the date the police check was issued' using errcode = '23514';
    end if;
    new.expires_on := new.completed_on + interval '5 years';
  end if;
  if tg_op = 'INSERT'
     or new.reference is distinct from old.reference
     or new.expires_on is distinct from old.expires_on
     or new.completed_on is distinct from old.completed_on
     or new.kind is distinct from old.kind then
    new.verified_by := auth.uid();
    new.verified_at := now();
  end if;
  return new;
end;
$$;

-- Each tutor's checks and what is missing. Every active tutor now also
-- shows a police check, so a missing one stands out.
create or replace view public.tutor_check_status
with (security_invoker = true) as
with needed as (
  select c.tutor_id, c.kind
  from public.tutor_checks c
  where c.verified_at is not null
  union
  select w.tutor_id, r.kind
  from public.tutor_work_settings w
  join public.check_requirements r on r.state = w.work_state and r.basis = 'tutor_state'
  union
  select t.account_id, 'police_check'::public.tutor_check_kind
  from public.tutor_profiles t
  where t.active
)
select
  n.tutor_id,
  a.full_name,
  n.kind,
  c.reference,
  c.expires_on,
  case
    when c.expires_on is null then 'missing'
    when c.expires_on < current_date then 'expired'
    when c.expires_on < current_date + 60 then 'expiring_soon'
    else 'current'
  end as status
from needed n
join public.accounts a on a.id = n.tutor_id
left join lateral (
  select reference, expires_on from public.tutor_checks
  where tutor_id = n.tutor_id and kind = n.kind and verified_at is not null
  order by expires_on desc limit 1
) c on true;
