#!/usr/bin/env python3
"""Build SQLLY's original Russian course adaptation; no network or runtime translation.

The TSV files hold authored prose. SQL, fixture data, identifiers, checks, IDs,
and typed answer metadata are copied byte-for-byte from the English course.
"""
import copy
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Sources/SQLCore/Resources/curriculum.json'
DEST = SOURCE.with_name('curriculum-ru.json')


def rows(filename, fields):
    output = {}
    for line in (ROOT / 'scripts' / filename).read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        values = line.split('\t', fields - 1)
        if len(values) != fields:
            raise ValueError(f'Expected {fields} fields: {line}')
        if values[0] in output:
            raise ValueError(f'Duplicate translation: {values[0]}')
        output[values[0]] = values[1:]
    return output


LESSONS = rows('ru-lessons.tsv', 6)
EXERCISES = rows('ru-exercises.tsv', 3)
EXTRA = {}
for filename in ['extra-foundation-exercises.json', 'extra-advanced-exercises.json']:
    path = ROOT / 'scripts' / filename
    if path.exists():
        for exercise in json.loads(path.read_text()):
            EXTRA[exercise['id']] = exercise['ru']

MODULES = [
    'Основы баз данных', 'SELECT и форма результата', 'Фильтрация и логика',
    'NULL и текстовые шаблоны', 'Выражения, CASE и типы', 'Агрегатные функции',
    'GROUP BY и HAVING', 'Основы соединений', 'Кардинальность и существование',
    'Подзапросы и производные таблицы', 'CTE и операции множеств',
    'INSERT, UPDATE и DELETE', 'Upsert и транзакционные изменения',
    'Типы данных PostgreSQL', 'Даты, время и интервалы', 'Массивы и JSONB',
    'Ограничения и проектирование таблиц', 'Нормализация, схемы и миграции',
    'Основы оконных функций', 'Оконные рамки и аналитика',
    'Представления и материализация', 'Функции, процедуры и PL/pgSQL',
    'Триггеры и полнотекстовый поиск', 'Типы индексов и методы доступа',
    'EXPLAIN и оптимизация запросов', 'Статистика и обслуживание',
    'Транзакции, MVCC и конкуренция', 'Безопасность и права',
    'Резервные копии, репликация и эксплуатация', 'Рекурсия и иерархии',
    'Специальные возможности PostgreSQL', 'Практические сложные задачи',
    'Проекты: торговля и гостиница', 'Итоговые проекты: финансы и аналитика',
]
TOPICS = [
    'Реляционное мышление', 'Выбор и форма данных', 'Построение условий',
    'Неизвестные значения и шаблоны', 'Вычисляемые значения',
    'Сводки по таблице', 'Отчёты по группам', 'Связывание фактов',
    'Правильность соединений', 'Запросы внутри запросов', 'Композиция наборов',
    'Изменение строк', 'Надёжные операции записи', 'Выбор представления данных',
    'Запросы с учётом времени', 'Структурированные коллекции',
    'Защита правил данных', 'Развитие модели', 'Вычисления по строкам',
    'Аналитические приёмы', 'Повторно используемые отчёты',
    'Серверные программы', 'Автоматизация и поиск', 'Структуры доступа',
    'Измерение работы запроса', 'Поддержание данных', 'Координация транзакций',
    'Управление доступом', 'Восстановление и эксплуатация',
    'Обход связанных данных', 'Инструменты PostgreSQL',
    'Решение сложных задач', 'Практика торговли и гостиницы',
    'Практика финансов и аналитики',
]
SECTION_TITLES = [
    'Основная идея', 'Зачем это нужно', 'Как это работает', 'Разбор синтаксиса',
    'Небольшой пример', 'Практическое применение', 'Ожидаемый результат',
    'Частые ошибки', 'Связанные понятия', 'Осмысленная практика', 'Краткий итог',
]
CLAUSES = [
    ('WITH RECURSIVE', 'WITH RECURSIVE объявляет начальные строки и рекурсивную часть, которая читает предыдущий рабочий набор.'),
    ('WITH ', 'WITH даёт промежуточному запросу имя; главный SELECT читает его результат.'),
    ('SELECT', 'SELECT перечисляет выходные выражения в нужном порядке. AS задаёт псевдоним.'),
    ('FROM', 'FROM задаёт источник строк. Псевдонимы уточняют принадлежность столбцов.'),
    ('JOIN', 'JOIN объединяет строки; ON задаёт связь, а вид соединения определяет сохранение строк без пары.'),
    ('WHERE', 'WHERE оставляет только строки с истинным условием до группировки и окон.'),
    ('GROUP BY', 'GROUP BY определяет уровень результата, а агрегаты сводят каждую группу.'),
    ('HAVING', 'HAVING отбирает готовые группы после вычисления агрегатов.'),
    ('OVER', 'OVER определяет раздел, порядок и, при необходимости, рамку оконного вычисления.'),
    ('ORDER BY', 'ORDER BY задаёт порядок результата. Последующие ключи разрешают равенство предыдущих.'),
    ('LIMIT', 'LIMIT ограничивает число строк после сортировки. Однозначный дополнительный ключ делает выбор воспроизводимым.'),
    ('INSERT', 'INSERT перечисляет целевые столбцы и соответствующие значения или исходный запрос.'),
    ('UPDATE', 'UPDATE задаёт таблицу, SET — новые значения, WHERE — изменяемые строки.'),
    ('DELETE', 'DELETE FROM задаёт таблицу, WHERE определяет удаляемые строки.'),
    ('RETURNING', 'RETURNING показывает значения строк, изменённых этой командой.'),
    ('ON CONFLICT', 'ON CONFLICT выбирает ключ конфликта и действие; EXCLUDED содержит предложенные значения.'),
    ('CREATE TABLE', 'CREATE TABLE объявляет имена, типы, значения по умолчанию и ограничения таблицы.'),
    ('CREATE FUNCTION', 'CREATE FUNCTION задаёт типы аргументов, тип результата, язык и тело функции.'),
    ('CREATE PROCEDURE', 'CREATE PROCEDURE объявляет именованную операцию, CALL вызывает её.'),
    ('CREATE TRIGGER', 'CREATE TRIGGER задаёт время, событие, уровень строки или команды и функцию триггера.'),
    ('CREATE INDEX', 'CREATE INDEX задаёт метод доступа и ключи; условие частичного индекса ограничивает строки.'),
    ('CREATE VIEW', 'CREATE VIEW сохраняет определение запроса; вызывающий код отдельно задаёт окончательный порядок.'),
    ('CREATE MATERIALIZED VIEW', 'CREATE MATERIALIZED VIEW сохраняет строки запроса; REFRESH пересчитывает их.'),
    ('ALTER TABLE', 'ALTER TABLE меняет существующую таблицу; необходимо учитывать её данные и блокировки.'),
    ('BEGIN', 'BEGIN начинает транзакцию, COMMIT сохраняет изменения, ROLLBACK отменяет их.'),
    ('PREPARE', 'PREPARE объявляет типизированные параметры вроде $1; EXECUTE передаёт значения отдельно.'),
    ('EXPLAIN', 'EXPLAIN показывает план. ANALYZE выполняет команду; отключение времени делает проверку структуры воспроизводимой.'),
    ('VACUUM', 'VACUUM обслуживает таблицу вне явной транзакции; ANALYZE также обновляет статистику.'),
]
MODELS = {
    'l010-e4': 'Результат содержит один столбец x и ноль строк. Известные значения равны 2 и не удовлетворяют x <> 2. Сравнение с NULL неизвестно, а WHERE принимает только истину.',
    'l056-e4': 'salary | salary_rank | dense_salary_rank\n— | — | —\n90 | 1 | 1\n80 | 2 | 2\n80 | 2 | 2\n70 | 4 | 3\n\nRANK учитывает позиции строк, поэтому после двух равных строк ранг перескакивает к 4. DENSE_RANK считает различные группы, поэтому следующий ранг равен 3.',
    'l079-e4': 'В READ COMMITTED каждая команда получает новый снимок, поэтому второе чтение может увидеть чужое зафиксированное изменение. В REPEATABLE READ оба чтения используют снимок транзакции и не видят изменение, зафиксированное позже. SERIALIZABLE предотвращает аномалии сериализации, но может прервать транзакцию с ошибкой сериализации. Приложение должно повторить всю транзакцию с ограниченной политикой повторов, не дублируя внешние побочные эффекты.',
    'l102-e4': 'Сначала сравните фильтры статуса и времени: отчёты должны использовать одинаковые заказы. Проверьте, не удаляет ли INNER JOIN гостевые заказы или заказы без позиций. Исследуйте кардинальность: сумма заголовка не должна повторяться для каждой позиции, а позиции — размножаться другими связями. Сначала сверяйте отдельные заказы, затем общий итог. Уточните налоги, доставку, скидки, возвраты и округление, которые могут входить только в заголовок. Проверьте NULL и единицы валюты. Сохраните однозначный отчёт расхождений по заказу и подтвердите бизнес-определение показателя.',
}
CHOICES = {
    'A': 'Выполнить SELECT id FROM customers WHERE name=$1, передав имя отдельно через API привязки параметров драйвера.',
    'B': 'Добавить исходное имя строковой конкатенацией после WHERE name= и выполнить полученный текст.',
    'C': 'Окружить исходное имя одинарными кавычками через интерполяцию строк и выполнить команду.',
    'D': 'Отклонять только имена со словом DROP, остальные добавлять строковой конкатенацией.',
}
COMMENTS = {
    '-- Write your PostgreSQL query here': '-- Напишите запрос PostgreSQL здесь',
    '-- Apply the business filter and group by month': '-- Примените бизнес-фильтр и сгруппируйте по месяцу',
    '-- Return the matching name': '-- Верните подходящее название',
}


def translated_comments(sql):
    lines = []
    for line in sql.splitlines(keepends=True):
        content = line.strip()
        if content in COMMENTS:
            indent = line[:len(line) - len(line.lstrip())]
            newline = '\n' if line.endswith('\n') else ''
            line = indent + COMMENTS[content] + newline
        lines.append(line)
    return ''.join(lines)


def executable_starter(sql):
    return '\n'.join(line for line in sql.splitlines() if not line.lstrip().startswith('--'))


def main():
    english = json.loads(SOURCE.read_text())
    russian = copy.deepcopy(english)
    russian['title'] = 'SQLLY: SQL и PostgreSQL'
    count = 0
    for index, module in enumerate(russian['modules']):
        module['title'] = MODULES[index]
        for topic in module['topics']:
            topic['title'] = TOPICS[index]
            for lesson in topic['lessons']:
                title, idea, why, how, mistake = LESSONS[lesson['id']]
                lesson['title'] = title
                for exercise in lesson['exercises']:
                    count += 1
                    exercise['starterSQL'] = translated_comments(exercise['starterSQL'])
                    localized = EXTRA.get(exercise['id'])
                    if localized:
                        exercise['title'] = localized['title']
                        exercise['prompt'] = localized['prompt']
                        exercise['hints'] = localized.get('hints') or [f'Определите, что представляет одна строка в задаче «{exercise["title"]}».', how, mistake]
                        exercise['explanation'] = localized.get('explanation') or idea + ' ' + how
                    else:
                        exercise['title'], exercise['prompt'] = EXERCISES[exercise['id']]
                        exercise['hints'] = [f'Определите, что означает одна строка результата в задаче «{exercise["title"]}», и какие столбцы нужны.', how, mistake]
                        if exercise['kind'] == 'explain':
                            exercise['explanation'] = 'Сравните свой ответ с образцом, отметьте недостающие пункты и добавьте конкретный пример. Нажимайте «Проверено», когда можете объяснить правило своими словами. Этот ответ оценивается самостоятельно, без автоматического сравнения текста.'
                        elif exercise['kind'] == 'choose':
                            exercise['explanation'] = how + ' Проверьте все варианты, а не только первый подходящий. ' + mistake
                        else:
                            exercise['explanation'] = idea + ' ' + how + ' Решение сохраняет требуемые столбцы, значения, повторы, правила NULL и порядок. Проверка использует независимые учебные наборы и принимает другой корректный SQL.'
                    if exercise['id'] in MODELS:
                        exercise['modelAnswer'] = MODELS[exercise['id']]
                    if exercise['id'] == 'l083-e4':
                        for option in exercise['choices']:
                            option['text'] = CHOICES[option['id']]
                examples = lesson['exercises']
                codes = [section.get('code') for section in lesson['sections']]
                original_expected = lesson['sections'][6]['body']
                table = original_expected.split('\n\n', 1)[1] if '\n\n' in original_expected else ''
                expected = 'Результат небольшого примера на учебном наборе Retail, полученный в PostgreSQL 18.6. Показано не больше восьми строк; NULL обозначает отсутствующее значение.'
                if examples[0].get('validationSQL'):
                    expected = 'Результат отдельного проверочного запроса после выполнения небольшого примера на учебном наборе Retail в PostgreSQL 18.6. Это проверка полученного состояния, а не непосредственно вывод команды в редакторе. Проверяются данные и требуемая структура: типы, NULL, значения по умолчанию, identity, ограничения, индексы и политики. Показано не больше восьми строк.'
                if table:
                    expected += '\n\n' + table
                guides = [text for token, text in CLAUSES if re.search(r'\b' + re.escape(token.strip()) + r'\b', examples[0]['solutionSQL'], re.I)]
                prerequisite_names = [LESSONS[p][0] for p in lesson['prerequisites']]
                related = ('Перед этим полезно изучить: ' + ', '.join(prerequisite_names) + '. ' if prerequisite_names else 'Предыдущие знания SQL не требуются. ') + 'Сравните небольшой пример с практической задачей: правило остаётся тем же при добавлении строк.'
                bodies = [idea, why, how, how + '\n\n' + '\n'.join('• ' + g for g in guides), examples[0]['prompt'], examples[2]['prompt'], expected, mistake, related,
                          f'Выполните практические шаги этого понятия по порядку. Всего заданий: {len(examples)}. Сначала изучите результат пробного запроса, затем отправьте решение на проверку. Ошибка не стирает прогресс. Открывайте подсказки постепенно и отмечайте сложные шаги для повторения.', idea + ' ' + how]
                lesson['sections'] = [dict(title=SECTION_TITLES[i], body=body, **({'code': codes[i]} if codes[i] is not None else {})) for i, body in enumerate(bodies)]
    # A content-language switch must never alter query semantics or progress IDs.
    sql_fields = ['id', 'kind', 'solutionSQL', 'fixtureIDs', 'ordered', 'columnNames', 'validationSQL', 'stateValidationSQL', 'correctChoiceIDs', 'predictionColumns', 'checkOutput', 'outputOrdered']
    en_lessons = [l for m in english['modules'] for t in m['topics'] for l in t['lessons']]
    ru_lessons = [l for m in russian['modules'] for t in m['topics'] for l in t['lessons']]
    assert english['fixtures'] == russian['fixtures']
    for en, ru in zip(en_lessons, ru_lessons):
        assert en['id'] == ru['id'] and en['prerequisites'] == ru['prerequisites']
        assert len(en['exercises']) == len(ru['exercises'])
        for before, after in zip(en['exercises'], ru['exercises']):
            assert executable_starter(before['starterSQL']) == executable_starter(after['starterSQL'])
            for key in sql_fields:
                assert before.get(key) == after.get(key), (before['id'], key)
            for key in ['title', 'prompt', 'explanation']:
                assert re.search('[А-Яа-яЁё]', after[key]), (after['id'], key)
            assert all(re.search('[А-Яа-яЁё]', hint) for hint in after['hints'])
        assert all(re.search('[А-Яа-яЁё]', section['body']) for section in ru['sections'])
    DEST.write_text(json.dumps(russian, ensure_ascii=False, indent=2) + '\n')
    def execution_payload(course):
        return dict(fixtures=course['fixtures'], exercises=[dict(**{key: e.get(key) for key in sql_fields}, starter=executable_starter(e['starterSQL'])) for m in course['modules'] for t in m['topics'] for l in t['lessons'] for e in l['exercises']])
    en_hash = hashlib.sha256(json.dumps(execution_payload(english), ensure_ascii=False, sort_keys=True).encode()).hexdigest()
    ru_hash = hashlib.sha256(json.dumps(execution_payload(russian), ensure_ascii=False, sort_keys=True).encode()).hexdigest()
    assert en_hash == ru_hash
    audit = dict(courseVersion=english['version'], modules=len(russian['modules']), lessons=len(ru_lessons), exercises=count,
                 translatedLessonSections=sum(len(l['sections']) for l in ru_lessons), translatedPrompts=count,
                 translatedHints=sum(len(e['hints']) for l in ru_lessons for e in l['exercises']), missingTranslations=[],
                 executableFieldsAndFixturesSHA256=en_hash, executableParity=True,
                 note='Full-line instructional comments are localized; SQL tokens, literals, reference/check scripts, fixtures, policies and IDs are unchanged between languages.')
    audit_path = ROOT / 'docs/verification/localization-content-audit.json'
    audit_path.parent.mkdir(parents=True, exist_ok=True)
    audit_path.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n')
    print(f'Russian curriculum: {len(ru_lessons)} lessons, {count} exercises. SQL, fixtures, checks and IDs unchanged.')


if __name__ == '__main__':
    main()
