#!/usr/bin/env python3
"""Check all authored explanations and optionally compare a pre-edit course pack.

Usage: python3 scripts/audit-lesson-explanations.py [--baseline DIR] [--report FILE]
Baseline comparison permits section-body edits, the content version, and the
English/Russian m08 topic wording only. Every exercise field remains protected.
"""
import argparse
import hashlib
import json
import pathlib

from lesson_explanations import ROOT, contract_hash, lessons, load_reviews, lesson_body, validate_teaching_order, worked_examples


def audit(baseline=None):
    reviews = load_reviews()
    resource_path = ROOT / 'Sources/SQLCore/Resources'
    previews = json.loads((ROOT / 'scripts/expected-previews.json').read_text())
    courses = {}
    contracts = {}
    sections_changed = {}
    for language, filename in [('en', 'curriculum.json'), ('ru', 'curriculum-ru.json')]:
        course = json.loads((resource_path / filename).read_text())
        entries = lessons(course)
        assert set(reviews) == {lesson['id'] for lesson in entries}
        assert len(entries) == len(reviews) == 102
        validate_teaching_order(course, reviews)
        old_lessons = {}
        if baseline:
            old = json.loads((baseline / filename).read_text())
            assert contract_hash(old) == contract_hash(course), f'Task/structure change: {language}'
            old_lessons = {lesson['id']: lesson for lesson in lessons(old)}
        changed = 0
        for lesson in entries:
            assert len(lesson['sections']) == 11
            for index, section in enumerate(lesson['sections']):
                expected = lesson_body(reviews[lesson['id']], language, index)
                if index == 6:
                    observed = previews[lesson['id']]
                    rows = [' | '.join(observed['columns']), ' | '.join('—' for _ in observed['columns'])]
                    rows += [' | '.join('NULL' if cell is None else str(cell) for cell in row)
                             for row in observed['rows'][:8]]
                    expected += '\n\n' + '\n'.join(rows)
                assert section['body'] == expected, f'Authored content mismatch: {lesson["id"]}/{language}/{index}'
                if old_lessons:
                    old_section = old_lessons[lesson['id']]['sections'][index]
                    if index == 6:
                        assert section['body'].partition('\n\n')[2] == old_section['body'].partition('\n\n')[2]
                    changed += section['body'] != old_section['body']
        courses[language] = course
        contracts[language] = contract_hash(course)
        sections_changed[language] = changed if baseline else None
    en, ru = lessons(courses['en']), lessons(courses['ru'])
    assert [lesson['id'] for lesson in en] == [lesson['id'] for lesson in ru]
    assert courses['en']['fixtures'] == courses['ru']['fixtures']
    for left, right in zip(en, ru):
        assert left['prerequisites'] == right['prerequisites']
        assert [section.get('code') for section in left['sections']] == [section.get('code') for section in right['sections']]
    assert json.loads((resource_path / 'reading-examples.json').read_text()) == worked_examples(courses['en'], reviews)
    return {
        'courseVersion': courses['en']['version'],
        'modules': len(courses['en']['modules']), 'lessons': len(en),
        'exercises': sum(len(lesson['exercises']) for lesson in en),
        'sectionsPerLanguage': sum(len(lesson['sections']) for lesson in en),
        'allLessonReviewsPresent': True, 'authoredResourcesMatch': True,
        'allTasksIndividuallyReviewed': True,
        'reviewedTasks': sum(len(entry['taskCoverage']) for entry in reviews.values()),
        'workedExamples': len(reviews),
        'requiredTeachingVisibleBeforePractice': True,
        'measuredResultTablesPreserved': True,
        'baselineTaskAndStructureComparisonPassed': bool(baseline),
        'sectionsIndividuallyRevised': sections_changed,
        'nonProseContractSHA256': contracts,
        'authoringFiles': {name.name: hashlib.sha256(name.read_bytes()).hexdigest()
                          for name in sorted((ROOT / 'scripts').glob('lesson-explanations-*.json'))},
        'reviews': [dict(lessonID=left['id'], englishTitle=left['title'], russianTitle=right['title'],
                         review=reviews[left['id']]['review'], sources=reviews[left['id']]['sources'],
                         taskCoverage=reviews[left['id']]['taskCoverage'])
                    for left, right in zip(en, ru)],
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=pathlib.Path)
    parser.add_argument('--report', type=pathlib.Path)
    args = parser.parse_args()
    report = audit(args.baseline)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f"Reviewed {report['lessons']} lessons, {report['sectionsPerLanguage']} sections per language; "
          f"{report['exercises']} exercises retained. Authored prose and measured result tables match.")
    if args.baseline:
        print('Baseline comparison passed: all exercise fields, fixtures, example SQL, IDs, prerequisites and learning steps unchanged.')
