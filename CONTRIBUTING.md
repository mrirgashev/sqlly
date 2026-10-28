# Contributing

Contributions to the original application and course are accepted under the MIT License. Do not copy paid course text, proprietary datasets, or third-party exercises. The Stepik references informed navigation and learning workflow only.

1. Read the architecture, engine security, and content format documents.
2. Build the pinned PostgreSQL runtime and run `swift test`.
3. Keep UI, persistence, execution, and grading changes separate. Views must not evaluate SQL themselves.
4. For new exercises, provide original prompts, fixtures, a valid reference solution, progressive hints, expected behavior, and explicit ordering/column policies. Include adversarial fixture data with duplicates, NULLs, changed IDs, and empty cases as relevant.
5. Verify every reference solution against the bundled PostgreSQL version. A generated lesson is not sufficient evidence of correctness.
6. For security-sensitive engine changes, test timeouts, role escalation, filesystem restrictions, fixture isolation, cleanup after errors, and server restarts.
7. Keep English and Russian resources complete and preserve SQL/fixture/assessment parity. Translate new course prompts, hints, explanations, and UI strings in the same change.
8. For visible changes, inspect the running app in both languages, light and dark appearance, and at its minimum window size. Include keyboard and VoiceOver checks.
9. For reactive execution, test rapid edits, step/language switches, superseded results, manual submission, and shutdown. Live previews must never award completion or enqueue unbounded database work.
10. Explain the problem, user-visible behavior, and tests actually run in the pull request. Do not claim compatibility based on compilation alone.

Use clear technical English, stable content IDs, and small reviewable changes. Open an issue before changing the progress format or PostgreSQL major version. Never commit credentials, personal progress files, certificates, or local database clusters.
