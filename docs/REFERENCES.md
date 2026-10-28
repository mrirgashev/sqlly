# Research and design provenance

Researched 28 October 2026. These references informed architecture and workflow. Their lesson text and exercises are not included in SQLLY.

## Learning workflow

The supplied [lesson 415553](https://stepik.org/lesson/415553/step/1?unit=405082) returned no readable lesson body through the web reader. Its page title identifies a Python course, and the public lesson endpoint identifies the lesson as “Часть 1.” We do not claim to have inspected an accessible SQL lesson at that URL.

Fallback research used Stepik's accessible [SQL trainer course page](https://stepik.org/course/63054/promo), its public API, and official support pages for [course structure](https://www.support.stepik.org/hc/en-us/articles/360000263214) and [assignment types](https://www.support.stepik.org/hc/en-us/articles/360000380594). The support pages were readable in search results; some direct fetches returned HTTP 502.

Public endpoints inspected:

- `https://stepik.org/api/courses/63054`: course and section IDs.
- `https://stepik.org/api/sections/112676`: units within the relational foundations module.
- `https://stepik.org/api/units/279268` and `279269`: lesson relationships.
- `https://stepik.org/api/lessons/297508` and `297509`: ordered lesson steps.
- `https://stepik.org/api/steps/2445668` and adjacent SQL steps: SQL task blocks with user-code execution enabled.

This supports a course → module → lesson → ordered step workflow, short theory adjacent to practice, and executable SQL tasks. SQLLY adds a topic grouping for detailed navigation. Learner authentication and answer submission were not performed on Stepik, so its live answer-checking messages, logged-in transitions, and grading internals were not inspected. SQLLY's grading and feedback are original implementation choices.

## Design skills actually inspected

Neither requested design skill was present in the locally available skill inventory. Visiting a listing does not install a skill. The actual upstream instruction files were retrieved and read directly:

- [Apple Design instructions](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md), linked by the [OpenDesign page](https://open-design.ai/skills/apple-design/). This is web-oriented guidance. Applicable principles: immediate feedback, interruptible motion, familiar behavior, system typography, accessible contrast, reduced motion/transparency, restraint, and clear wayfinding. Native controls implement split resizing and standard macOS interaction; web CSS and pointer recipes are not copied into the application.
- [aicodedecode SwiftUI Pro instructions](https://github.com/aicodedecode/awesome-muse-skills/blob/main/skills/swiftui-pro/SKILL.md), the source linked by the [requested directory listing](https://www.skillsdirectory.com/skills/aicodedecode-swiftui-pro). The listing was accessible via HTTP despite the web reader failing. Applicable guidance: one owner per state, observable main-actor UI models, small views, stable IDs, lifecycle tasks, explicit loading/error/empty states, keyboard handling, and accessibility labels. AppKit is bridged for the rich SQL editor.

No skill was silently installed, and none of the skill text is redistributed with the app. Their own upstream licenses govern their instructions.

## Architecture documentation sources

Consult [engine research](ENGINE.md) and [third-party notices](../THIRD_PARTY_NOTICES.md) for version-pinned database source, compatibility, license, and redistribution decisions. Version-specific SQL behavior is documented against the official PostgreSQL 18 manuals rather than inferred from other engines.

## SQLLY icon reference

The requested [Bootstrap Database icon](https://icons.getbootstrap.com/icons/database/) and the [Bootstrap Icons MIT license](https://github.com/twbs/icons/blob/main/LICENSE) were inspected. SQLLY uses the familiar database-cylinder idea, but its AppKit paths, dimensions, composition, black background, white strokes, and green accent are original. No Bootstrap SVG, icon font, or path data is bundled. The generated artwork is included under this project's MIT license.
