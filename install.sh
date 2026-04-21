#!/usr/bin/env bash
set -e

# ─────────────────────────────────────────────
#  EVA — установщик
# ─────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${GREEN}✔${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✘${NC}  $*"; exit 1; }
section() { echo -e "\n${BOLD}$*${NC}"; }

echo ""
echo "  ╔══════════════════════════════╗"
echo "  ║       EVA — установка        ║"
echo "  ╚══════════════════════════════╝"
echo ""

INSTALL_DIR="${1:-$HOME/eva}"

# При запуске через curl | bash stdin занят pipe-ом — читаем с терминала напрямую
INTERACTIVE_IN="/dev/tty"
ask() {
  local prompt="$1" varname="$2"
  printf "  %s" "$prompt" > /dev/tty
  read -r "$varname" < "$INTERACTIVE_IN"
}

# ─── 1. Проверить bun ───────────────────────
section "1. Проверяю окружение..."

if ! command -v bun &>/dev/null; then
  warn "bun не найден. Устанавливаю..."
  curl -fsSL https://bun.sh/install | bash
  # Добавить bun в PATH для текущей сессии
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  if ! command -v bun &>/dev/null; then
    error "Не удалось установить bun. Установи вручную: https://bun.sh"
  fi
  info "bun установлен: $(bun --version)"
else
  info "bun найден: $(bun --version)"
fi

if ! command -v git &>/dev/null; then
  error "git не найден. Установи git и запусти скрипт снова."
fi

if ! command -v claude &>/dev/null; then
  warn "claude CLI не найден."
  echo ""
  echo "  Claude CLI нужен для работы EVA."
  echo "  Установи: npm install -g @anthropic-ai/claude-code"
  echo "  Или скачай с: https://claude.ai/code"
  echo ""
  ask "Продолжить без Claude CLI? (y/N): " CONTINUE_WITHOUT
  if [[ "$CONTINUE_WITHOUT" != "y" && "$CONTINUE_WITHOUT" != "Y" ]]; then
    echo "  Установи Claude CLI и запусти install.sh снова."
    exit 0
  fi
else
  info "claude найден: $(claude --version 2>/dev/null | head -1)"
fi

# ─── 2. Клонировать ре��озиторий ────────��────
section "2. Устанавливаю EVA в $INSTALL_DIR..."

if [ -d "$INSTALL_DIR" ] && [ "$(ls -A $INSTALL_DIR)" ]; then
  warn "Директория $INSTALL_DIR уже существует."
  ask "Обновить? (y/N): " UPDATE
  if [[ "$UPDATE" == "y" || "$UPDATE" == "Y" ]]; then
    cd "$INSTALL_DIR"
    git pull origin main 2>/dev/null || git pull 2>/dev/null || warn "Не удалось обновить — продолжаю с текущей версией"
    info "Обновлено"
  fi
else
  git clone https://github.com/vibe-claude/EVA-assistent.git "$INSTALL_DIR" 2>/dev/null || \
    error "Не удалось клонировать репозиторий. Проверь интернет."
  info "Репозиторий клонирован"
fi

cd "$INSTALL_DIR"

# ─── 3. Установить зависимости ───────────���──
section "3. Устанавливаю зависимости..."
bun install --silent
info "Node/Bun зависимости установлены"

# Python-зависимости для wiki-rag (семантический поиск)
if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
  PIP=$(command -v pip3 || command -v pip)
  info "Устанавливаю sentence-transformers (семантический поиск wiki)..."
  $PIP install -q sentence-transformers 2>/dev/null && \
    info "sentence-transformers установлен" || \
    warn "Не удалось установить sentence-transformers — поиск wiki будет ограничен"
else
  warn "pip не найден — пропускаю установку sentence-transformers"
fi

# ─── 4. Создать директорию home и credentials ───
mkdir -p "$INSTALL_DIR/home/.claude"

# Symlink credentials — без него Claude не авторизован
CREDS_SRC="$HOME/.claude/.credentials.json"
CREDS_LINK="$INSTALL_DIR/home/.claude/.credentials.json"
if [ -f "$CREDS_SRC" ]; then
  ln -sf "$CREDS_SRC" "$CREDS_LINK"
  info "Credentials подключены (симлинк)"
elif [ -L "$CREDS_LINK" ] || [ -f "$CREDS_LINK" ]; then
  info "Credentials уже настроены"
else
  warn "~/.claude/.credentials.json не найден. Авторизуйся в Claude сначала: claude"
  warn "После авторизации запусти: ln -sf $CREDS_SRC $CREDS_LINK"
fi

info "Директория home/ создана"

# ─── 5. Настройка Telegram ──────────────────
section "4. Настройка Telegram бота..."
echo ""
echo "  Тебе нужен Telegram Bot Token."
echo "  Если у тебя ещё нет бота:"
echo "  1. Открой @BotFather в Telegram"
echo "  2. Напиши /newbot"
echo "  3. Выбери имя и username"
echo "  4. Скопируй то��ен (формат: 1234567890:AAA...)"
echo ""

ask "Telegram Bot Token: " TG_TOKEN

if [ -z "$TG_TOKEN" ]; then
  warn "Токен не указан. Можно добавить позже в .claude/claudeclaw/settings.json"
else
  # Проверить токен
  TG_CHECK=$(curl -sf "https://api.telegram.org/bot${TG_TOKEN}/getMe" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ok',''))" 2>/dev/null)
  if [ "$TG_CHECK" = "True" ]; then
    BOT_NAME=$(curl -sf "https://api.telegram.org/bot${TG_TOKEN}/getMe" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'].get('username',''))" 2>/dev/null)
    info "Бот найден: @$BOT_NAME"
  else
    warn "Не удалось проверить токен. Убедись что он верный."
  fi
fi

# Запросить Telegram user ID
echo ""
echo "  Твой Telegram User ID (для безопасности — только ты сможешь писать EVA)."
echo "  Узнать ID: напиши @userinfobot в Telegram."
echo ""
ask "Твой Telegram User ID: " TG_USER_ID

# Записать settings.json
SETTINGS_DIR="$INSTALL_DIR/.claude/claudeclaw"
mkdir -p "$SETTINGS_DIR"

if [ -f "$SETTINGS_DIR/settings.json" ] && [ -s "$SETTINGS_DIR/settings.json" ]; then
  # Обновить существующий settings.json
  python3 -c "
import json, sys
with open('$SETTINGS_DIR/settings.json') as f:
    d = json.load(f)
if '$TG_TOKEN':
    d.setdefault('telegram', {})['token'] = '$TG_TOKEN'
if '$TG_USER_ID':
    try:
        uid = int('$TG_USER_ID')
        d['telegram']['allowedUserIds'] = [uid]
    except:
        pass
with open('$SETTINGS_DIR/settings.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
" 2>/dev/null
else
  # Создать новый settings.json
  python3 -c "
import json
settings = {
  'model': 'sonnet',
  'api': '',
  'telegram': {
    'token': '$TG_TOKEN',
    'allowedUserIds': [int('$TG_USER_ID')] if '$TG_USER_ID'.isdigit() else []
  },
  'discord': {'token': '', 'allowedUserIds': [], 'listenChannels': []},
  'timezone': 'UTC+3',
  'security': {'level': 'unrestricted', 'allowedTools': [], 'disallowedTools': []},
  'session': {'autoRotate': True, 'maxMessages': 30, 'maxAgeHours': 24, 'summaryPath': ''},
  'web': {'enabled': True, 'host': '127.0.0.1', 'port': 4632}
}
with open('$SETTINGS_DIR/settings.json', 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
print('ok')
" 2>/dev/null
fi

info "settings.json настроен"

# Защита токенов: только владелец может читать
chmod 600 "$SETTINGS_DIR/settings.json" 2>/dev/null || true
info "Права доступа к settings.json: 600 (только владелец)"

# ─── 6. Создать .env ────────────────────────
if [ ! -f "$INSTALL_DIR/.env" ]; then
  cat > "$INSTALL_DIR/.env" << 'ENV'
# EVA — переменные окружения
# Заполни после установки

# Notion (если используешь)
NOTION_TOKEN=
NOTION_TASKS_DB=
ENV
  chmod 600 "$INSTALL_DIR/.env"
  info ".env создан (заполни токены)"
else
  chmod 600 "$INSTALL_DIR/.env"
fi

# ─── 7. Создать настройки разрешений Claude Code ─
CLAUDE_SETTINGS="$INSTALL_DIR/home/.claude/settings.json"
mkdir -p "$INSTALL_DIR/home/.claude"
if [ ! -f "$CLAUDE_SETTINGS" ]; then
  cat > "$CLAUDE_SETTINGS" << 'CCSETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "MultiEdit(*)",
      "Glob(*)",
      "Grep(*)"
    ],
    "deny": []
  },
  "skipDangerousModePermissionPrompt": true
}
CCSETTINGS
  info "Разрешения Claude Code настроены"
fi

# ─── 8. Сбросить сессию для первого запуска ─
# Удаляем старую сессию чтобы гарантированно запустился bootstrap
SESSION_FILE="$INSTALL_DIR/.claude/claudeclaw/session.json"
if [ -f "$SESSION_FILE" ]; then
  rm -f "$SESSION_FILE"
  info "Сессия сброшена (запустится знакомство)"
fi

# ─── 9. Создать скрипт запуска ──────────────
cat > "$INSTALL_DIR/start.sh" << STARTSCRIPT
#!/usr/bin/env bash
# EVA — запуск
cd "$INSTALL_DIR"
HOME="$INSTALL_DIR/home" CLAUDECLAW_SKIP_PREFLIGHT=1 \\
  nohup bun run src/index.ts start --web \\
  >> "$INSTALL_DIR/daemon.log" 2>&1 &
echo "EVA запущена (PID: \$!)"
echo "Логи: $INSTALL_DIR/daemon.log"
STARTSCRIPT
chmod +x "$INSTALL_DIR/start.sh"
info "start.sh создан"

# ─── Приватность ────────────────────────────
echo ""
echo "  ⚠️  Важно о приватности:"
echo ""
echo "  EVA использует Claude AI (Anthropic, США) для обработки"
echo "  сообщений и документов. Данные передаются на серверы"
echo "  Anthropic при каждом запросе."
echo ""
echo "  Не передавай через EVA конфиденциальные медицинские,"
echo "  финансовые данные или документы под NDA."
echo ""

# ─── Итог ───────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║         Установка завершена!         ║"
echo "  ╚══════════════════════════════════════╝"
echo ""
echo "  Что дальше:"
echo ""
echo "  1. Авторизуйся в Claude:"
echo "     claude"
echo "     (войди через браузер — одна авторизация на всё)"
echo ""
echo "  2. Запусти EVA:"
echo "     $INSTALL_DIR/start.sh"
echo ""
echo "  3. Напиши своему боту в Telegram — EVA представится"
echo "     и настроится под тебя."
echo ""
if [ -n "$TG_TOKEN" ] && [ -n "$BOT_NAME" ]; then
  echo "  Твой бот: https://t.me/$BOT_NAME"
  echo ""
fi
echo "  Документация: $INSTALL_DIR/README.md"
echo ""
