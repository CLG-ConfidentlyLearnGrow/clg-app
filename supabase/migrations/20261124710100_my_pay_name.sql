-- Training and handbook: "My pay" is now "My Pay" (Carla, 22 Nov 2026, from
-- her notes on Emma's Job Proposal). The side menu item was renamed in the
-- app; this changes the same words in the training lessons, quiz questions
-- and handbook pages that name it, so they match what people see.
--
-- Only the exact words "My pay" are changed. Safe to run more than once.

update public.training_lessons set body = replace(body, 'My pay', 'My Pay') -- lessons: the new name,
where body like '%My pay%'; -- only those that use the old name
update public.training_modules set summary = replace(summary, 'My pay', 'My Pay') -- module summaries: the new name,
where summary like '%My pay%'; -- only those that use the old name
update public.training_questions set prompt = replace(prompt, 'My pay', 'My Pay') -- quiz questions: the new name,
where prompt like '%My pay%'; -- only those that use the old name
update public.training_questions set options = array(select replace(o, 'My pay', 'My Pay') from unnest(options) with ordinality as t(o, n) order by n) -- quiz choices: the new name, in the same order,
where array_to_string(options, '|') like '%My pay%'; -- only those that use the old name
update public.handbook_pages set body = replace(body, 'My pay', 'My Pay') -- handbook pages: the new name,
where body like '%My pay%'; -- only those that use the old name
