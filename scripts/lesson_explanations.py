"""Authored bilingual teaching prose and practical reading examples.

This layer changes section bodies only. Exercise definitions and the original
syntax examples remain owned by the established curriculum generator.
"""
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
REVIEW_FILES = [
    'lesson-explanations-001-034.json',
    'lesson-explanations-035-068.json',
    'lesson-explanations-069-102.json',
]


def lessons(course):
    return [lesson for module in course['modules']
            for topic in module['topics'] for lesson in topic['lessons']]


def load_reviews():
    reviews = {}
    for filename in REVIEW_FILES:
        entries = json.loads((ROOT / 'scripts' / filename).read_text())['lessons']
        for lesson_id, entry in entries.items():
            if lesson_id in reviews:
                raise ValueError(f'Duplicate explanation review: {lesson_id}')
            for language in ['en', 'ru']:
                bodies = entry[language]
                if len(bodies) != 11 or any(not isinstance(body, str) or not body.strip() for body in bodies):
                    raise ValueError(f'Expected eleven authored sections: {lesson_id}/{language}')
                if '\n\n' in bodies[6]:
                    raise ValueError(f'Expected-results introduction must be one paragraph: {lesson_id}/{language}')
                if language == 'ru' and any(not re.search('[А-Яа-яЁё]', body) for body in bodies):
                    raise ValueError(f'Missing Russian adaptation: {lesson_id}')
            if not entry.get('review') or not entry.get('sources'):
                raise ValueError(f'Missing individual review record: {lesson_id}')
            if any(not source.startswith('https://www.postgresql.org/docs/18/') for source in entry['sources']):
                raise ValueError(f'Expected official PostgreSQL 18 references: {lesson_id}')
            reviews[lesson_id] = entry
    return reviews


def result_table(columns, rows):
    lines = [' | '.join(columns), ' | '.join('—' for _ in columns)]
    lines.extend(' | '.join('NULL' if cell is None else cell for cell in row) for row in rows)
    return '\n'.join(lines)


def lesson_body(entry, language, index):
    body = entry[language][index]
    if index != 4:
        return body
    example = entry['workedExample']
    script = '\n'.join(part.strip() for part in [example.get('setupSQL', ''), example['sql']] if part.strip())
    result_label = '**Result**' if language == 'en' else '**Результат**'
    return '\n\n'.join([body, example[language + 'Before'], '```sql\n' + script + '\n```',
                         result_label, result_table(example['columns'], example['rows']), example[language + 'After']])


def validate_teaching_order(course, reviews):
    entries = lessons(course)
    positions = {lesson['id']: index for index, lesson in enumerate(entries)}
    visible_sections = {0, 1, 2, 3, 4, 6}
    for lesson in entries:
        entry = reviews[lesson['id']]
        coverage = entry['taskCoverage']
        if [item['exerciseID'] for item in coverage] != [exercise['id'] for exercise in lesson['exercises']]:
            raise ValueError(f'Task review coverage/order mismatch: {lesson["id"]}')
        for item in coverage:
            if not item['requires'] or not item['taughtIn'] or not item['resolution'].strip():
                raise ValueError(f'Incomplete task review: {item["exerciseID"]}')
            for reference in item['taughtIn']:
                source_id, section = reference.split(':')
                if source_id not in positions or positions[source_id] > positions[lesson['id']]:
                    raise ValueError(f'Task depends on future teaching: {item["exerciseID"]}/{reference}')
                if int(section) not in visible_sections:
                    raise ValueError(f'Required teaching must be visible before practice: {item["exerciseID"]}/{reference}')
        example = entry['workedExample']
        if not example['sql'].strip() or not example['columns'] or not isinstance(example['rows'], list):
            raise ValueError(f'Incomplete worked example: {lesson["id"]}')
        for key in ['enBefore', 'ruBefore', 'enAfter', 'ruAfter']:
            if not example[key].strip():
                raise ValueError(f'Missing worked-example prose: {lesson["id"]}/{key}')
        for row in example['rows']:
            if len(row) != len(example['columns']) or any(cell is not None and not isinstance(cell, str) for cell in row):
                raise ValueError(f'Invalid worked-example row: {lesson["id"]}')
            if any(cell is not None and any(character in cell for character in '|\r\n') for cell in row):
                raise ValueError(f'Worked-example cells must fit the native table renderer: {lesson["id"]}')


def worked_examples(course, reviews=None):
    reviews = reviews or load_reviews()
    return dict(version=course['version'], examples=[
        dict(lessonID=lesson['id'], fixtureID='retail',
             **{key: value for key, value in reviews[lesson['id']]['workedExample'].items()
                if key in ['sql', 'setupSQL', 'columns', 'rows']})
        for lesson in lessons(course)
    ])


def write_worked_examples(course):
    destination = ROOT / 'Sources/SQLCore/Resources/reading-examples.json'
    destination.write_text(json.dumps(worked_examples(course), ensure_ascii=False, indent=2) + '\n')


def non_prose_payload(course):
    """Protect every field except course version, two wording edits and bodies."""
    payload = json.loads(json.dumps(course))
    payload.pop('version', None)
    for module in payload['modules']:
        for topic in module['topics']:
            if topic['id'] == 'm08-topic':
                topic.pop('title', None)
            for lesson in topic['lessons']:
                for section in lesson['sections']:
                    section.pop('body', None)
    return payload


def contract_hash(course):
    return hashlib.sha256(json.dumps(non_prose_payload(course), ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def apply_explanations(course, language):
    reviews = load_reviews()
    entries = lessons(course)
    if set(reviews) != {lesson['id'] for lesson in entries}:
        raise ValueError('Explanation review must cover every installed lesson exactly once')
    validate_teaching_order(course, reviews)
    before = contract_hash(course)
    for lesson in entries:
        if len(lesson['sections']) != 11:
            raise ValueError(f'Unexpected learning structure: {lesson["id"]}')
        # Preserve the measured result table, including values, NULLs and order.
        table = lesson['sections'][6]['body'].partition('\n\n')[2]
        for index in range(11):
            body = lesson_body(reviews[lesson['id']], language, index)
            lesson['sections'][index]['body'] = body + ('\n\n' + table if index == 6 and table else '')
    if before != contract_hash(course):
        raise ValueError('Teaching-prose overlay changed the curriculum contract')
