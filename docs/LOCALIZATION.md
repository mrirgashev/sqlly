# Application localization

SQLLY bundles English and Russian interface resources and course packs. Select English or Русский in Settings; the choice is saved in the existing application defaults domain `org.querycraft.QueryCraft`. Switching language refreshes navigation, application menus, lesson prose, hints, feedback, settings, and app-owned file-panel messages while retaining stable progress IDs and the learner’s SQL.

## Resources

- The executable target's `Resources/en.lproj/Localizable.strings` and `Resources/ru.lproj/Localizable.strings` contain the app interface entries, with matching keys and interpolation contracts. The current release audit records their verified count.
- SQLCore has its own localized grading feedback resources, selected by `CourseLanguage`.
- `Sources/SQLCore/Resources/curriculum.json` and `curriculum-ru.json` carry the original bilingual course. See [content localization](LOCALIZATION-CONTENT.md) for authoring tables, exercise overrides, and executable-code parity.

The Swift package declares English as its development localization. App metadata advertises both supported languages. SQLLY uses system fonts and UTF-8 resources; no external font files are required. The app-owned language preference does not rename macOS folders or replace the operating system's own file-browser chrome.

## Preserve the code contract

Translate prose and interface labels, not SQL keywords, identifiers, data values, choice IDs, ordering policies, or grading checks. A starter instruction comment may be translated; its executable tokens must remain the same. Reference and validation SQL are identical in both packs. PostgreSQL's original diagnostic text remains available as source evidence, with localized application explanations; the preserved runtime was built without gettext/NLS catalogs.

## Contributor verification

Run the localization/content audit and automated tests after changing resources. Validate `.strings` syntax with `plutil -lint`, keep every key and format placeholder aligned, and inspect the running app in both languages. Check long Russian labels at the minimum window size, all numbered steps, menus, empty/error/loading states, progressive hints, native answer controls, file-panel messages, and theme switching. Confirm language changes and restarts retain SQL drafts, completion, bookmarks, and review flags. A key-count check alone does not establish translation quality or layout quality.
