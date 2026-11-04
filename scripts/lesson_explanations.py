"""Authored bilingual teaching prose, applied after exercise generation.

This layer changes section bodies only. Exercise definitions and executable
examples remain owned by the established curriculum generator.
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
    before = contract_hash(course)
    for lesson in entries:
        if len(lesson['sections']) != 11:
            raise ValueError(f'Unexpected learning structure: {lesson["id"]}')
        # Preserve the measured result table, including values, NULLs and order.
        table = lesson['sections'][6]['body'].partition('\n\n')[2]
        for index, body in enumerate(reviews[lesson['id']][language]):
            lesson['sections'][index]['body'] = body + ('\n\n' + table if index == 6 and table else '')
    if before != contract_hash(course):
        raise ValueError('Teaching-prose overlay changed the curriculum contract')
