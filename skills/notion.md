# Notion — интеграция с задачами

> Заполни DB ID и токен после установки EVA.

## Настройка

Токен и ID хранятся в `.env`:
```bash
NOTION_TOKEN=ntn_xxxxxxxxxxxxxxxxxxxx
NOTION_TASKS_DB=your-database-id-here
NOTION_PAYMENTS_DB=your-payments-db-id-here  # опционально
```

Заголовки для всех запросов:
```
-H "Authorization: Bearer $NOTION_TOKEN"
-H "Notion-Version: 2022-06-28"
-H "Content-Type: application/json"
```

## Структура таблицы задач (настрой под свой Notion)

Ожидаемые поля:
- `Задачи` — title (название)
- `Status` — status (В работе / Выполнено / В плане / Контроль!!!)
- `Date` — date (срок)
- `Ответственный` — text (кому делегировано)

## Получить задачи на сегодня

```bash
source .env
TODAY=$(date +%Y-%m-%d)

curl -s -X POST "https://api.notion.com/v1/databases/$NOTION_TASKS_DB/query" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d "{
    \"filter\": {
      \"and\": [
        {\"property\": \"Date\", \"date\": {\"equals\": \"$TODAY\"}},
        {
          \"or\": [
            {\"property\": \"Status\", \"status\": {\"equals\": \"В работе\"}},
            {\"property\": \"Status\", \"status\": {\"equals\": \"Контроль!!!\"}}
          ]
        }
      ]
    },
    \"sorts\": [{\"property\": \"Date\", \"direction\": \"ascending\"}]
  }"
```

## Получить просроченные

```bash
source .env
TODAY=$(date +%Y-%m-%d)

curl -s -X POST "https://api.notion.com/v1/databases/$NOTION_TASKS_DB/query" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d "{
    \"filter\": {
      \"and\": [
        {\"property\": \"Status\", \"status\": {\"equals\": \"В работе\"}},
        {\"property\": \"Date\", \"date\": {\"before\": \"$TODAY\"}}
      ]
    }
  }"
```

## Закрыть задачу

```bash
source .env
PAGE_ID="<id страницы задачи>"

curl -s -X PATCH "https://api.notion.com/v1/pages/$PAGE_ID" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{"properties": {"Status": {"status": {"name": "Выполнено"}}}}'
```

## Создать задачу

```bash
source .env

curl -s -X POST "https://api.notion.com/v1/pages" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d "{
    \"parent\": {\"database_id\": \"$NOTION_TASKS_DB\"},
    \"properties\": {
      \"Задачи\": {\"title\": [{\"text\": {\"content\": \"<название>\"}}]},
      \"Status\": {\"status\": {\"name\": \"В плане\"}},
      \"Date\": {\"date\": {\"start\": \"<YYYY-MM-DD>\"}}
    }
  }"
```

## Алгоритм синхронизации (для джобов)

1. Получить все задачи со статусом "В работе" / "Контроль!!!" / "В плане"
2. Сохранить в `tasks/active.md` построчно:
   ```
   - [ ] Название задачи | Ответственный | Дата | ID: page-id
   ```
3. Задачи "Выполнено" — переносить в `tasks/archive/YYYY-MM.md`
