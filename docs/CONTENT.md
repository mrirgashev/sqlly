# Curriculum and exercise format

English content is bundled at `Sources/SQLCore/Resources/curriculum.json` and Russian content at `curriculum-ru.json`. `scripts/generate-curriculum.py` produces the English pack, including the additional bilingual practice source files. `scripts/localize-curriculum.py` generates the Russian adaptation with executable parity checks. Python is a contributor tool only; the app decodes JSON directly and released users do not need Python.

The top-level object has `title`, `version`, `postgresVersion`, a `fixtures` dictionary of SQL fixture scripts, and an ordered `modules` array. Each module has a stable `id`, `title`, and `topics`. Each topic has an `id`, `title`, and `lessons`. Each lesson contains its stable `id`, `title`, `prerequisites` (lesson IDs), ordered `sections`, and ordered `exercises`.

A section is `{ "title": "...", "body": "...", "code": "optional SQL" }`. The eleven educational sections are preserved: the first nine form the introductory explanation, followed by five or six practice steps and a recap containing sections 10–11. A topic combines three related concept lessons into one numbered sequence and is selected directly in the flat sidebar. A lesson should explain the concept, motivation, mechanism, syntax, small and realistic examples, expected results, common mistakes, comparisons, practice, and recap. Keep prose focused and explain terminology before relying on it.

Every exercise defines:

| Field | Purpose |
| --- | --- |
| `id`, `title` | Stable globally unique exercise ID and concise title |
| `prompt` | Required behavior, result columns, relevant ordering, and business rules |
| `difficulty`, `kind` | Difficulty and task presentation |
| `starterSQL` | Initial editable SQL; may be partial or incorrect for repair tasks |
| `solutionSQL` | A valid reference solution for the bundled PostgreSQL version |
| `fixtureIDs` | One or more named fixture scripts; multiple fixtures catch hardcoded results |
| `ordered` | Whether rows must appear in the specified order |
| `columnNames` | Whether output column names are part of the result contract |
| `hints` | Progressive conceptual hints; do not start by disclosing the full answer |
| `explanation` | Worked solution and reasoning |
| `validationSQL` | Optional post-submission query for validating schema or modified data |
| `stateValidationSQL` | Optional dedicated state query retained separately when the generator wraps it with a schema fingerprint |
| `checkOutput` | Optional Boolean: a state-changing task also requires the final submitted result/RETURNING table |
| `outputOrdered` | Optional Boolean for that immediate output; defaults to false and is separate from the state-check ordering policy |
| `choices`, `correctChoiceIDs` | Stable choice IDs/text and the exact valid set for a `choose` task |
| `modelAnswer` | Worked response/rubric for a written `explain` task |

Result tasks execute candidate and reference independently on equivalent fixture data. A state task executes its candidate or reference, then checks `validationSQL`. `validateDetailed` retains both the submitted script output and the committed-state check from the same mutating execution. When `checkOutput` is true, the grader also compares the immediate result columns/aliases and values, using `outputOrdered` (false unless explicitly required); state results keep their separate `ordered` policy. Generated design/state validations combine the requested data check with a deterministic schema fingerprint (columns, types, nullability, defaults, identity, constraints, indexes, and policies), so merely returning the expected rows does not satisfy a missing schema requirement. Keep validations meaningful: assert actual keys/constraints and resulting data, not only the presence of a named table. Fixture SQL is trusted bundled author content; student SQL receives the learner role's restrictions.

The app also supports `predict` tasks using a native editable result grid compared with real PostgreSQL output (the grading API serializes rows as JSON), `choose` tasks using native choice controls and exact choice-set assessment, and `explain` tasks using a written response plus model answer/rubric. Explanations are explicitly self-assessed; there is no claim of an automatic natural-language semantic grader. See [the installed inventory](CURRICULUM-AUDIT.md) for mode counts and depth limitations.

Use deterministic data. Avoid wall-clock assertions, locale-dependent formatting, reliance on unstated row order, exact optimizer costs, or machine-dependent execution timing. Specify tie-breakers when grading ordered rows. Include NULLs, duplicate values, absent relationships, changed identifiers, and boundary values in additional fixtures where they matter.

Stable IDs preserve learners' progress across edits. Do not reuse an existing exercise ID for an unrelated task. Document substantial meaning changes and version the content. Curriculum validation rejects duplicate IDs, unknown prerequisites, empty lessons, missing fixtures, and incomplete exercises. It does not prove educational quality or SQL correctness; run every reference solution against every fixture.

Operations requiring administrator rights, replication infrastructure, or concurrent sessions may be taught conceptually through safe catalog examples. Do not imply that a restricted single-operation practice environment performs backup/restore, configures replication, or demonstrates a live multi-session race unless an actual supported workflow has been added and tested.

## Localization invariants

English and Russian resources must retain identical stable IDs, prerequisite relationships, SQL fixtures, executable starter SQL, reference SQL, validation SQL, row-order/column policies, choice IDs/correct sets, and prediction-column identifiers. Translate educational prose, UI descriptions, and hints; do not translate executable SQL keywords or schema names. The single starter instruction comment may be localized; executable code remains identical. SQL choices stay as executable code; prose choices require Russian text. `checkOutput` and `outputOrdered` must match between packs. Run the localization parity audit and real PostgreSQL reference tests after editing either pack.

For the detailed authoring and parity workflow, read [content localization](LOCALIZATION-CONTENT.md) and [application localization](LOCALIZATION.md).
