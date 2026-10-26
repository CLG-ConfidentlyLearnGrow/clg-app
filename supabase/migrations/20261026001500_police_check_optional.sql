-- Carla's decision (26 Oct 2026): a national police check (Nationally
-- Coordinated Criminal History Check) is no longer required. Working with
-- children checks already include criminal history screening, and are what
-- the law requires for child-related work. Tutors can still record a police
-- check (it still counts for 5 years from issue), but it no longer decides
-- who can be matched with a student.
-- First aid certificates can also be recorded. They are optional too.

delete from public.check_requirements where kind = 'police_check';

-- Back to showing the checks a tutor holds plus any their work state needs,
-- without a forced "missing" police check line.
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

-- Maths is split into General, Essential and Advanced, because each is
-- taught very differently (Carla, 26 Oct 2026). A plain "Maths" entry is
-- refused for new rows; existing rows are left for the tutor to update.
alter table public.tutor_teaching
  add constraint tutor_teaching_maths_split
  check (lower(trim(subject)) not in ('maths', 'math', 'mathematics')) not valid;
