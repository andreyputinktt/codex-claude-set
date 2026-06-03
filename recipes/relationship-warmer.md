# Рецепт: Relationship Warmer

Этот рецепт нужен, чтобы развернуть приватного ассистента для двух задач:

- утепление отношений через Telegram и Gmail;
- поздравления с днем рождения через Telegram first-person userapi.

## Что человеку сказать в Codex

Короткий промпт:

```text
Поставь мне утепление отношений по рецепту relationship-warmer из
andreyputinktt/codex-claude-set. Сначала спроси недостающие данные, затем
создай сервис в моем GIT root по пути assistants/relationship-warmer, подключи
Telegram first-person userapi, приватного review-бота, Gmail draft-only при
нужде, цели общения по target, live-контекст переписок и поздравления с днем
рождения из Telegram contacts. Не коммить секреты. Доведи до проверки:
выбери безопасный тестовый target, сделай dry-run draft или тест в чат/бот,
проверь login-user, status, once/draft и birthdays --dry-run.
```

Если рецепт уже доступен локально:

```text
Открой recipes/relationship-warmer.md в codex-claude-set и разверни по нему
relationship-warmer end-to-end. Начни с вопросов, потом сделай установку,
секреты, userapi Telegram, тестовый target и проверку.
```

## Полный промпт для Codex/Claude

````text
Ты мой инженер персонального AI-окружения. Нужно создать Relationship Warmer:
приватный ассистент, который помогает поддерживать важные отношения через
Telegram и Gmail и поздравляет людей с днем рождения через Telegram. Работай
end-to-end: задай вопросы, создай структуру, подключи секреты, проверь работу,
не оставляй пользователя с полуготовой инструкцией.

Ключевые принципы

1. Сервис channel-agnostic: цель общения, контекст, память, черновики, review и
   policy общие; Telegram и Gmail - только адаптеры канала.
2. Главный объект - target: человек или группа с целью общения, границами,
   каналами, расписанием и policy.
3. Текст генерируется от имени пользователя, без мета-текста про ассистента,
   промпты, источники или автоматизацию.
4. Учитывай то, о чем уже общались: live Telegram history через userapi,
   Gmail thread context, compact memory, people profile и дневники/личный
   контекст, если они есть.
5. Telegram scheduled warming отправляется first-person userapi только если
   target явно разрешает auto-send. Review bot нужен для владельца: queue,
   approve, skip, add target, status.
6. Gmail по умолчанию draft_only, пока OAuth, sender alias, cc и manual-reply
   detection не проверены.
7. Birthday flow читает Telegram contacts birthdays, берет контекст из последних
   прямых сообщений/profile/about/personal channel и пропускает человека, если
   пользователь уже написал ему что-либо в этот день.
8. Не коммить .env, токены, Telegram sessions, raw private exports, runtime
   state, логи и личные данные без явного решения пользователя.

Сначала спроси коротко

1. GIT root и сервер: локальный путь, server host, Linux user, нужно ли
   деплоить systemd.
2. Имя пользователя и timezone.
3. Есть ли OpenAI API key в GIT/.env-openai. Если нет, сохрани через
   codex-claude-set/scripts/set-secret.sh.
4. Telegram first-person userapi:
   - есть ли TELEGRAM_API_ID и TELEGRAM_API_HASH;
   - есть ли готовая Telethon session или нужно провести login-user;
   - куда хранить session file: assistants/relationship-warmer/state/telegram-user.session.
5. Приватный review bot:
   - есть ли bot token от BotFather;
   - Telegram owner chat id;
   - если нет, провести пользователя через @BotFather /newbot, /start и /getid.
6. Gmail:
   - нужен ли Gmail target сейчас;
   - какие адреса, aliases, cc, Gmail OAuth/skill уже есть;
   - если Gmail не готов, оставить Gmail targets draft_only или не включать.
7. Первый тестовый target:
   - человек, бот, свой второй аккаунт или безопасный чат;
   - Telegram username/chat id или Gmail email/search query;
   - цель общения;
   - границы: что нельзя писать, темы риска, тон;
   - режим: draft_only или auto_send;
   - расписание, если нужен scheduled warming.
8. Birthday mode:
   - включать ли ежедневный birthday timer;
   - можно ли поздравлять автоматически или сначала только dry-run/review;
   - исключения: кого никогда не поздравлять.

Структура

Создай или настрой репозиторий:

- `assistants/relationship-warmer/` - repo/service root;
- `assistants/relationship-warmer/relationship_warmer/` - Python package для
  `python -m relationship_warmer`, это не вложенный репозиторий;
- `config/targets.yaml` - static targets, goals, channels, schedules, policy;
- `state/` - ignored runtime: outbox, compact memory, Telegram session;
- `systemd/` - bot, scheduled warmer, birthdays timer;
- `tests/` - unit tests for config, context, channels, birthdays, policy;
- `README.md`, `DEV.md`, `AGENTS.md`, `.gitignore`, `requirements.txt`.

Если у пользователя уже есть исходный репозиторий-шаблон
`relationship-warmer`, используй его как template и адаптируй конфиг. Если
шаблона нет, создай минимальный сервис с теми же контрактами:

- CLI commands:
  - `python -m relationship_warmer status`;
  - `python -m relationship_warmer login-user`;
  - `python -m relationship_warmer draft <target>`;
  - `python -m relationship_warmer once --target <target> --force`;
  - `python -m relationship_warmer queue`;
  - `python -m relationship_warmer check-gmail --target <target>`;
  - `python -m relationship_warmer birthdays --dry-run`;
  - `python -m relationship_warmer bot`.
- Target config supports:
  - `channels[].type: telegram|gmail`;
  - Telegram `identifier` as username, numeric chat id, or group username;
  - Gmail `email`, `search_query`, optional `cc`, optional `from_email`;
  - `scenario.purpose`, `strategy`, `prompt_guidance`;
  - `goals`, `constraints`;
  - `automation.level: draft_only|auto_send`;
  - `automation.response_policy.mode: draft_only|immediate|after_1h|evening_moscow`;
  - `delivery.auto_send`, `delivery.sender: first_person|bot`.

Env and secrets

Use shared root env files where possible:

- `GIT/.env-openai`: `OPENAI_API_KEY`, model settings;
- `GIT/.env-telegram`: `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`;
- `GIT/assistants/.env`: shared assistant owner ids if the user already uses it;
- `GIT/assistants/relationship-warmer/.env`: review bot token, owner chat id,
  service-specific overrides.

Use codex-claude-set secret helpers:

```bash
codex-claude-set/scripts/set-secret.sh --name OPENAI_API_KEY --provider openai --server <server>
codex-claude-set/scripts/set-secret.sh --name TELEGRAM_API_ID --name TELEGRAM_API_HASH --provider telegram --server <server>
codex-claude-set/scripts/set-secret.sh --name TELEGRAM_BOT_TOKEN --project assistants/relationship-warmer --server <server>
```

Never pass token values in shell args. If a token was pasted in chat/logs, tell
the user to rotate it before saving.

Telegram userapi setup

1. Ensure `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` are present.
2. Run:

```bash
cd <GIT_ROOT>/assistants/relationship-warmer
.venv/bin/python -m relationship_warmer login-user
```

3. Ask the user for phone/code/2FA only inside the terminal login prompt.
4. Store the resulting `.session` file under ignored `state/`.
5. Verify:

```bash
.venv/bin/python -m relationship_warmer status
RELATIONSHIP_WARMER_DRY_RUN=1 .venv/bin/python -m relationship_warmer draft <target>
RELATIONSHIP_WARMER_DRY_RUN=1 .venv/bin/python -m relationship_warmer birthdays --dry-run
```

Test target rule

Before enabling any real auto-send, choose one safe target:

- the user's own saved messages / test chat / bot chat;
- or a trusted person who consented;
- or Gmail draft-only target.

Then verify one of these:

- Telegram draft-only: generate draft and show queue item;
- Telegram auto-send test: send to safe test chat only;
- Gmail: create draft only, confirm recipient/cc/from alias and no auto-send;
- Birthday: `birthdays --target <safe_contact> --dry-run`.

Do not declare the install done until at least one target produces a sane
draft/send result and `status` runs without secret leakage.

Systemd

If server deployment is requested, create user-level or system services:

- `relationship-warmer-bot.service` - private review bot;
- `relationship-warmer-once.service` + timer - scheduled warming;
- `relationship-warmer-birthdays.service` + timer - daily birthday check.

Timers should use the user's timezone and randomized or fixed safe windows.
Birthday default can be around local midday. After enabling, check:

```bash
systemctl --user status relationship-warmer-bot.service --no-pager
systemctl --user list-timers 'relationship-warmer*' --no-pager
journalctl --user -u relationship-warmer-bot.service -n 50 --no-pager
```

Quality gates

Every generated message must pass these checks before send or draft creation:

- no JSON, markdown junk, prompt/source/meta text;
- no invented facts;
- no pressure, guilt, demand for response, or unsafe intimacy;
- respects target goal and constraints;
- short enough for channel;
- for minors: no adult emotional burden;
- for groups: invitation/reflection, not command/report;
- for Gmail: clear subject/body, cc/from alias handled, no accidental auto-send.

OpenSpec

If the agent changes behavior, prompts, service runtime, data schema, systemd,
or channel policy, use OpenSpec in the service repo automatically. If the task
is only target config or secret setup, no new OpenSpec change is needed.

Completion checklist

- repo exists at `assistants/relationship-warmer`;
- no extra nested repo, only Python package `relationship_warmer/`;
- `.gitignore` excludes `.env`, `state/`, logs, sessions;
- venv created and requirements installed;
- OpenAI env loaded or dry-run mode documented;
- Telegram userapi login completed or clearly marked pending;
- review bot token/owner id saved in ignored env if bot enabled;
- first target exists with goal, constraints, channel and policy;
- `status` works;
- safe `draft` or `once --force` test completed;
- `birthdays --dry-run` works or pending reason is explicit;
- systemd enabled and checked if server deployment was requested;
- README/DEV explain commands, env, targets, and safety boundary.
````

## Для списка рецептов

Когда пользователь спрашивает "Какие рецепты есть в codex-claude-set", агент
должен читать `recipes/README.md` и показывать этот рецепт как:

- `relationship-warmer.md` - утепление отношений через Telegram/Gmail и
  Telegram birthday congratulations с first-person userapi.
