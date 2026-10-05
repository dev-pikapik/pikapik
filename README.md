# pikapik

Маленькие полезные штуки для macOS в строке меню.

Сейчас внутри одна, но главная: **Ctrl+клик работает как обычный клик**. Контекстное меню больше не выскакивает.
Это спасает в играх, где Ctrl — кнопка действия: зажал Ctrl, кликнул — получил выстрел или выбор, а не меню.

- Правый клик мышью и тап двумя пальцами работают как раньше.
- Ctrl на клавиатуре остаётся нажатым — игра его видит.
- Включается и выключается одним переключателем.
- macOS 14 Sonoma и новее, Apple Silicon и Intel. На macOS 26 Tahoe — Liquid Glass.

## Установка

Через Homebrew:

```bash
brew tap dev-pikapik/pikapik https://github.com/dev-pikapik/pikapik && brew install --cask pikapik
```

Или без Homebrew, одной командой в Терминале:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dev-pikapik/pikapik/main/install.sh)"
```

Оба способа ставят готовую сборку в `/Applications`, снимают карантин, запускают приложение, просят доступы и включают автозапуск.
Хочешь собрать сам из исходников — добавь `--source` в конце (нужны Xcode Command Line Tools):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dev-pikapik/pikapik/main/install.sh)" -- --source
```

Или скачай `pikapik.dmg` из [Releases](https://github.com/dev-pikapik/pikapik/releases) и перетащи в «Программы». Если macOS не даёт открыть:

```bash
xattr -dr com.apple.quarantine /Applications/pikapik.app
```

## Обновления

Приложение само проверяет новые версии — при запуске и раз в 6 часов. Когда выходит новая, в меню появляется кнопка **Обновить до …**: один клик, и pikapik скачает, поставит и перезапустит себя.
Внизу меню видно текущую версию, там же кнопка **Проверить**.

Через Homebrew тоже можно: `brew upgrade --cask pikapik`.

После обновления macOS считает приложение новым, поэтому доступы надо включить ещё раз — окно с подсказкой откроется само.

## Доступы

Без них macOS не пустит приложение к кликам. При первом запуске откроется окно с подсказкой, а macOS покажет свои запросы.

Открой **System Settings › Privacy & Security** и включи pikapik в двух списках:

| Раздел | Зачем |
|---|---|
| **Accessibility** (Универсальный доступ) | чтобы менять клик |
| **Input Monitoring** (Мониторинг ввода) | чтобы видеть клик |

Приложение само проверяет доступы каждые 1,5 секунды — ничего перезапускать не нужно. Иконка в меню станет обычной стрелкой с кликом.

Не работает, хотя галочка стоит? Так бывает после пересборки. Удали pikapik из обоих списков кнопкой «−», затем нажми в меню **Проверить доступы** и включи заново.

## Иконка в строке меню

| Иконка | Что значит |
|---|---|
| стрелка с кликом | Активно — Ctrl+клик работает как обычный клик |
| перечёркнутая стрелка | Выключено |
| треугольник | Включено, но нет доступа |

## Автозапуск

Включается сам при первом запуске. Выключить или включить обратно — переключатель **Открывать при входе** в меню.
Если macOS попросит подтверждение: **System Settings › General › Login Items** → разреши pikapik.

## Удаление

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dev-pikapik/pikapik/main/uninstall.sh)"
```

Ставил через Homebrew — тогда `brew uninstall --cask --zap pikapik`.
Оба способа закроют приложение, уберут его из автозапуска и удалят. Скрипт ещё и сбросит доступы.

## Сборка из исходников

Нужны только Xcode Command Line Tools.

```bash
git clone https://github.com/dev-pikapik/pikapik.git
cd pikapik
./scripts/build.sh      # build/pikapik.app
./scripts/package.sh    # build/pikapik.dmg и build/pikapik.zip
```

### Подпись

По умолчанию сборка подписывается ad-hoc — этого хватает для своего Mac.
Есть Developer ID? Тогда можно подписать и нотаризовать:

```bash
xcrun notarytool store-credentials pika-notary --apple-id you@example.com --team-id TEAMID
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=pika-notary ./scripts/package.sh
```

## Как устроено

```
Sources/pikapik/
  main.swift, App.swift, MenuView.swift
  Tools/Tool.swift                   протокол Tool и ToolRegistry
  Tools/CtrlClick/CtrlClickTool.swift
  Common/                            общие куски интерфейса, доступы, автозапуск, обновления
Casks/pikapik.rb                  Homebrew cask
scripts/                             сборка, упаковка, релиз
```

Ctrl+клик ловится через `CGEventTap` до того, как событие попадёт в приложения. У левого клика снимается флаг Ctrl — и всё.
Правый клик и клавиатура не трогаются.

Новый инструмент = новый файл в `Tools/` с классом под протокол `Tool` и одна строка в `ToolRegistry.tools`.

## Выпустить новую версию

```bash
./scripts/release.sh 1.0.1
```

Скрипт поднимет версию, соберёт `.zip` и `.dmg`, обновит cask, закоммитит, поставит тег, запушит и создаст релиз на GitHub.
Установленные приложения увидят его сами.

## Лицензия

MIT, © 2026 pikapik. См. [LICENSE-MIT](LICENSE-MIT).
