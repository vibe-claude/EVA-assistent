# EVA — персональный AI-ассистент

> Форк [ClaudeClaw](https://github.com/moazbuilds/ClaudeClaw), развитый в самостоятельный продукт.

EVA работает в Telegram 24/7. Знает твой контекст, помнит документы, ведёт задачи, делает утренние брифинги. Не нужно объяснять ей одно и то же дважды.

---

## Установка (одна команда)

```bash
curl -fsSL https://raw.githubusercontent.com/vibe-claude/EVA-assistent/main/install.sh | bash
```

Или с указанием дир��ктории:

```bash
curl -fsSL https://raw.githubusercontent.com/vibe-claude/EVA-assistent/main/install.sh | bash -s ~/eva
```

Скрипт сам:
- Проверит и установит `bun` (если нет)
- Клонирует репозиторий
- Установит зависимости
- Запросит токен Telegram-бота
- Настроит `settings.json`
- Создаст скрипт запуска

---

## Требования

- **Claude CLI** — основной движок. Установи: `npm install -g @anthropic-ai/claude-code` или скачай с [claude.ai/code](https://claude.ai/code)
- **Bun** — установится автоматически
- **Telegram Bot Token** — создай бота через [@BotFather](https://t.me/BotFather)

---

## Быстрый старт

```bash
# 1. Установка
curl -fsSL https://raw.githubusercontent.com/vibe-claude/EVA-assistent/main/install.sh | bash

# 2. Авторизация в Claude (один раз)
claude

# 3. Запуск EVA
~/eva/start.sh

# 4. Напиши своему боту в Telegram
# EVA сама представится и настроится
```

---

## Что умеет EVA

| Возможность | Описание |
|---|---|
| Задачи | Создаёт, закрывает, напоминает. Интеграция с Notion. |
| Утренний брифинг | Задачи + просроченные + платежи — каждое утро |
| Вечерний итог | Что сделано, что открыто, оценка дня |
| База знаний | Сохраняет документы, письма, заметки в wiki/ |
| Обработка файлов | PDF, фото, сканы — извлекает содержимое через subprocess |
| Голосовые сообщения | Транскрибирует через Whisper (локально) |
| Вечерняя рефлексия | Дневник + анализ недели |
| Dream System | Ночная консолидация памяти |
| IKIGAI / цели | Опрос + долгосрочные цели + трекер привычек |
| Браузер | Поиск в интернете че��ез Playwright MCP |
| Самообучение | Запоминает уроки и правки пользователя |
| Ротация сессий | Автоматически по размеру и возрасту |

---

## Структура

```
~/eva/
├── CLAUDE.md              — характер и правила (редактируй под себя)
├── USER.md                — профиль пользователя (заполняется при первом запуске)
├── install.sh             — установ��ик
├── start.sh               — запуск (создаётся при установке)
├── .env                   — токены (Notion, и др.)
├── skills/
│   ├── index.md           — маршрутизация задач по скиллам
│   ├── jobs.md            — логика джобов
│   ├── docs.md            — обработка документов
│   ├── dialog.md          — триггеры диалога
│   └── notion.md          — интеграция с Notion
├── prompts/
│   ├── IDENTITY.md        — ДНК агента (кто такая EVA)
│   ├── BOOTSTRAP.md       — первый запуск
│   └── SOUL.md            — философия
├── wiki/                  — база знаний (LLM-generated)
│   ├── index.md           — каталог стр��ниц
│   └── log.md             — append-only лог событий
├── raw/                   — оригиналы документов
├── goals/                 — IKIGAI, цели, привычки
├── memory/                — уроки, дневник, саммари сессий
├── tasks/                 — активные задачи и архив
└── .claude/claudeclaw/
    ├── settings.json      — конфигурация
    └── jobs/              — расписание джобов
```

---

## Джобы — настрой под свой ритм

Каждый джоб — MD-файл с cron-расписанием в frontmatter:

```markdown
---
description: Утренний брифинг
schedule: 45 8 * * 1-5
recurring: true
---
Прочитай задачи из Notion и выведи брифинг на сегодня.
Читай инструкцию в skills/jobs.md → work-morning.
```

Примеры джобов (шаблоны в `.claude/claudeclaw/jobs/`):
- `work-morning.md` — утренний брифинг (08:45 пн–пт)
- `work-check-1.md` — дневная проверка (11:30 пн–пт)
- `work-evening.md` — итог дня (18:00 пн–пт)
- `evening-reflection.md` — дневник (20:30 ежедневно)
- `dream-system.md` — ночная консолидация (03:00)

---

## Интеграция с Notion

1. Создай интеграцию на [notion.so/my-integrations](https://www.notion.so/my-integrations)
2. Скопируй токен в `.env`:
   ```
   NOTION_TOKEN=ntn_xxxxxxxxxxxxxxxx
   NOTION_TASKS_DB=your-database-id
   ```
3. Добавь интеграцию к своей базе задач в Notion
4. Шаблоны curl-запросов — в `skills/notion.md`

---

## Первый запуск

При первом сообщении EVA запустит BOOTSTRAP — задаст тебе несколько вопросов:
- Как тебя зовут
- Как ты хочешь общаться (тон, язык)
- Часовой пояс и рабочие часы
- Нужна ли интеграция с Notion

После этого заполнит `CLAUDE.md` и `USER.md` — и будет помнить всё это в каждой сессии.

---

## Паттерн базы знаний (Karpathy)

EVA не хранит документы в БД — ведёт вики из MD-файлов:

- `raw/` — неизменяемые оригиналы (PDF, сканы, фото)
- `wiki/` — LLM-генерируемые страницы по объектам и процессам
- `wiki/log.md` — append-only лог всех событий

При получении документа: извлечение через subprocess → вопрос "Сохранить?" → запись в wiki.

---

## На основе

- [ClaudeClaw](https://github.com/moazbuilds/ClaudeClaw) by [@moazbuilds](https://github.com/moazbuilds) — daemon framework
- [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — knowledge base pattern
- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) — local voice transcription

---

*EVA — персональный пр��ект. Код предоставляется как есть.*
