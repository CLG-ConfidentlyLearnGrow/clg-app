# How to use the CLG app

The step-by-step guides for each kind of account now live **inside the
app**, under **App guide** in each dashboard's side menu (16 Nov 2026). Each
account sees only the guide for its own roles and admin level.

The words are kept with the code in `src/lib/app-guides/`:

| File | Guide |
| --- | --- |
| `parent.ts` | Parents and carers |
| `student.ts` | Students 16+ with their own login (and adult learners) |
| `tutor.ts` | Tutors |
| `admin.ts` | Admins: one guide each for Owner, Operations, Support and Finance |

Who can open which guide is set in `src/lib/app-guides/index.ts`
(`guidesFor`). See `docs/features/app-guides.md` for the research brief.

## Keeping the guides up to date

When a change alters what someone can do in the app, or the name of a
button or menu item, update the matching guide in the same pull request.
The older markdown guides that used to be in this folder were replaced by
the in-app guides (they had fallen behind the app, for example families no
longer book times themselves).
