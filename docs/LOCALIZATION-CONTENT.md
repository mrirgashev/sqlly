# English and Russian course resources

The app ships both course packs. It does not call a translation service, translate SQL at runtime, or silently substitute English lesson prose in Russian mode.

- `Sources/SQLCore/Resources/curriculum.json` is the original English pack.
- `Sources/SQLCore/Resources/curriculum-ru.json` is the original Russian adaptation.
- `scripts/ru-lessons.tsv` contains lesson ID, Russian title, concept, purpose, operation, and common mistake in six tab-separated fields.
- `scripts/ru-exercises.tsv` contains exercise ID, Russian title, and Russian prompt in three tab-separated fields.
- Additional exercise source JSON contains English fields and a `ru` object. The generator removes authoring metadata from the installed English pack; the localizer selects the Russian prose.

Regenerate English content with `python3 scripts/generate-curriculum.py`, then run `python3 scripts/localize-curriculum.py`. The latter constructs all eleven educational sections, including localized examples, syntax guidance, prerequisite names, expected-result captions, progressive hints, worked explanations, choice prose, and written-answer rubrics. Russian explanations are naturally worded educational adaptations rather than mechanical word substitutions.

SQL keywords, executable query tokens, fixture data, identifiers, reference solutions, validation queries, ordering policies, typed answer metadata, and stable IDs remain identical across languages. Only the three instructional full-line comments in starter SQL are translated; executable text and inline output-alias comments stay unchanged. Thus switching language preserves progress and assessment semantics. Actual result-table column names and text values are database data, so values such as `London`, `paid`, and `Office` intentionally stay unchanged.

The generator raises an error for missing required translations. Its parity checks assert identical fixtures and executable fields, the same exercise order, and Russian prose for every exercise title, prompt, hint, explanation, and lesson section. The app's interface strings and PostgreSQL error explanations are maintained in separate native localization resources.

When adding a task, translate its business rule exactly, including output aliases, tie breakers, NULL policy, dates, thresholds, and expected data changes. Preserve literals that the submitted SQL must match. Run the SQL/reference audit after adding tasks and the bilingual parity checks after changing text.
