# pikapik

Маленькие полезные штуки для macOS в строке меню.

Сейчас внутри три инструмента для игр, где Ctrl — кнопка действия, а прыжок на пробеле жмут часто:

1. **Ctrl+клик работает как обычный клик**. Контекстное меню больше не выскакивает: зажал Ctrl, кликнул — получил выстрел или выбор, а не меню.
2. **Блокировка Ctrl-сочетаний**. Сам Ctrl остаётся зажатым и виден игре (бег на Ctrl работает), а все сочетания вида Ctrl+<клавиша> до системы не долетают: Ctrl+Space больше не меняет язык, Ctrl+стрелки не дёргают Mission Control и Spaces, параллельно нажатые клавиши не делают ничего лишнего.
3. **Фильтр двойного пробела**. Первый пробел всегда проходит (прыжок работает), а повторный быстрее паузы глотается и не доходит ни до игры, ни до системы: подстановка «двойной пробел → точка» и прочие реакции не срабатывают, игра не пролагивает. Пауза настраивается ползунком (по умолчанию 120 мс). Удержание пробела (автоповтор) и пробел с модификаторами — например, бег+прыжок на Ctrl+пробел — проходят всегда.

- Правый клик мышью и тап двумя пальцами работают как раньше.
- Ctrl на клавиатуре остаётся нажатым — игра его видит.
- Каждый инструмент включается и выключается своим переключателем. Не играешь — выключи блокировки, чтобы Ctrl+C, двойной пробел и другие обычные шорткаты снова работали везде.
- macOS 14 Sonoma и новее, Apple Silicon и Intel. На macOS 26 Tahoe — Liquid Glass.
- Иконка — белая стрелка с искрой клика на тёплом янтарном фоне. На macOS 26 сама подстраивается под светлую, тёмную и тонированную тему.

## Установка

Через Homebrew:

```bash
brew tap dev-pikapik/pikapik https://github.com/dev-pikapik/pikapik && brew trust dev-pikapik/pikapik && brew install --cask pikapik && open -a pikapik
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

Без них macOS не пустит приложение к кликам и клавишам. При первом запуске откроется окно с подсказкой, а macOS покажет свои запросы.

Открой **System Settings › Privacy & Security** и включи pikapik в двух списках:

| Раздел | Зачем |
|---|---|
| **Accessibility** (Универсальный доступ) | чтобы менять клики и клавиши |
| **Input Monitoring** (Мониторинг ввода) | чтобы видеть клики и клавиши |

Приложение само проверяет доступы каждые 1,5 секунды — ничего перезапускать не нужно. Иконка в меню станет обычной стрелкой с кликом.

Не работает, хотя галочка стоит? Так бывает после пересборки. Удали pikapik из обоих списков кнопкой «−», затем нажми в меню **Проверить доступы** и включи заново.

## Иконка в строке меню

| Иконка | Что значит |
|---|---|
| стрелка с кликом | Активно — перехваты работают |
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
  Tools/CtrlKeys/CtrlKeysTool.swift
  Tools/DoubleSpace/DoubleSpaceTool.swift + SpaceDebouncer.swift
  Common/                            общие куски интерфейса, доступы, автозапуск, обновления
Casks/pikapik.rb                  Homebrew cask
Resources/AppIcon.icon               иконка приложения, AppIcon.icns — запасная
scripts/                             сборка, упаковка, релиз, иконка
```

Ctrl+клик ловится через `CGEventTap` до того, как событие попадёт в приложения. У левого клика снимается флаг Ctrl — и всё.
Правый клик не трогается.

Ctrl-сочетания ловятся вторым `CGEventTap`, только для `keyDown`/`keyUp`. У нажатия, пришедшего с зажатым Ctrl, снимается флаг Ctrl (а если зажат ещё и Cmd — то и Cmd, чтобы событие не деградировало до Cmd+Space со Spotlight). Событие `flagsChanged` самого Ctrl не трогается, поэтому игра продолжает видеть зажатый Ctrl, а система сочетания уже не видит.

Двойной пробел ловится третьим `CGEventTap`, только для `keyDown` пробела (keycode 49). Первое нажатие проходит всегда, повторное быстрее паузы глотается (`return nil`). Отпускание пробела, автоповтор удерживаемого пробела и пробел с модификаторами пропускаются всегда — залипших прыжков и сломанного бега+прыжка нет. Сама пауза — чистая структура `SpaceDebouncer` без зависимостей.

Новый инструмент = новый файл в `Tools/` с классом под протокол `Tool` и одна строка в `ToolRegistry.tools`.

## Выпустить новую версию

```bash
./scripts/release.sh 1.0.2
```

Скрипт поднимет версию, закоммитит, поставит тег и запушит. Остальное делает GitHub Actions: собирает `.zip` и `.dmg` с иконкой под macOS 26, проверяет подпись, публикует релиз и обновляет cask в `main`.
Установленные приложения увидят новую версию сами.

Иконка лежит в `Resources/AppIcon.icon` (формат Icon Composer). Поменял её — пересобери запасную `Resources/AppIcon.icns` для macOS 14–15:

```bash
swift scripts/make-icns.swift
```

## Лицензия

MIT, © 2026 pikapik. См. [LICENSE-MIT](LICENSE-MIT).
