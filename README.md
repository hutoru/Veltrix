# VELTRIX

**Beyond the balance.** Нативный симулятор криптовалютного портфеля, торговли и виртуальных карт для iPhone. Балансы, переводы, платежи и ордера существуют внутри симуляции. Приложение не запрашивает регистрацию, доступ к кошельку или банковские реквизиты.

## Системные требования

- iPhone XS или другой iPhone с ARM64 и iOS 16.0 либо новее.
- Windows 11 и Git for Windows для работы с кодом. GitHub CLI нужен только для получения артефакта из командной строки.
- Сборка выполняется на стандартном runner GitHub Actions `macos-15`. Для приватного репозитория сборка расходует включённую квоту аккаунта. В настройках биллинга можно задать остановку при исчерпании бюджета. [GitHub Actions и квоты](https://docs.github.com/en/actions/concepts/billing-and-usage)

## Скачать IPA на Windows

1. Откройте [Build iOS IPA](https://github.com/hutoru/Veltrix/actions/workflows/build-ios.yml). Если нужна новая сборка, выберите **Run workflow → main**.
2. В успешном запуске скачайте **Veltrix-unsigned-ipa** и распакуйте артефакт. Внутри находятся `Veltrix.ipa` и контрольная сумма SHA-256.
3. Через PowerShell можно скачать и одновременно проверить последний успешный артефакт.

```powershell
.\scripts\setup.ps1 -InstallGitHubCli
gh auth login
.\scripts\download-ipa.ps1 -Repository hutoru/Veltrix
```

По умолчанию скрипт сохраняет файлы в `dist`. Параметр `-RunId` позволяет выбрать запуск.

## Установить на iPhone

Артефакт GitHub нужно подписать перед установкой. Для бесплатного Apple ID подпись обычно действует 7 дней, после чего приложение нужно обновить через инструмент подписи. AltStore Classic допускает до трёх активных приложений, установленных таким способом. На iOS 16 может потребоваться «Режим разработчика» в разделе «Конфиденциальность и безопасность». [AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore) · [Режим разработчика Apple](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

- **Sideloadly.** Подключите разблокированный iPhone по USB, подтвердите доверие этому компьютеру, выберите устройство и `Veltrix.ipa`. Введите Apple ID в Sideloadly, нажмите **Start** и следуйте подсказкам на iPhone. [Sideloadly](https://sideloadly.io/)
- **AltStore Classic.** Установите AltServer на Windows, через него установите AltStore на iPhone, перенесите `Veltrix.ipa` на телефон и откройте через **My Apps → +**. Для обновления подписи AltServer должен быть доступен. [Установка AltStore на Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-classic)

## Данные и поведение симуляции

- **Криптовалюты.** CoinGecko предоставляет сводные котировки, капитализацию, объём и историю. Kraken поставляет поток сделок по выбранным USD-парам и свечи для поддерживаемых пар. Для `ALL` без подходящей пары Kraken используется доступная годовая история CoinGecko с явной пометкой. [CoinGecko](https://docs.coingecko.com/reference/coins-id-market-chart) · [Условия](https://www.coingecko.com/en/api_terms) · [Kraken OHLC](https://docs.kraken.com/api/docs/rest-api/get-ohlc-data/)
- **Доступность.** Публичный CoinGecko может ограничить анонимные запросы. Необязательный бесплатный ключ Demo хранится в Keychain. Если сеть недоступна, приложение показывает последние сохранённые данные с датой. Рыночные операции и исполнение лимитных ордеров используют свежие котировки при активном приложении. Исполнение по пропущенным движениям рынка в фоне не моделируется.
- **Валюты.** Расчёты симуляции ведутся в USD. Отображение использует справочные курсы Frankfurter, их дату публикации и выбранную точность. Для отсутствующего курса UI показывает прочерк. [Frankfurter](https://frankfurter.dev/) · [Лицензия данных](https://frankfurter.dev/license/)
- **Портфель.** История начинается с создания портфеля и включает фактические точки наблюдения и операций. Дневные П/У исключают оценённые внешние пополнения, переводы и перемещения между портфелем и картой. Карты имеют собственный баланс. При импорте резервной копии приложение запрашивает подтверждение замены текущих данных.
- **Приватность.** Портфель хранится в Core Data на устройстве. Резервный JSON и изображения для публикации помечены как симуляция. В JSON нет PIN и ключа API, баланс и операции в нём читаемы. Удаление приложения может удалить локальную базу. Экспортируйте копию перед удалением или сменой приложения на экземпляр с другим идентификатором.

## Разработка

```bash
brew install xcodegen
xcodegen generate --spec project.yml
UDID="$(bash scripts/select-simulator.sh)"
xcodebuild test -project Veltrix.xcodeproj -scheme Veltrix -destination "platform=iOS Simulator,id=$UDID"
bash scripts/build-ipa.sh
```

Workflow запускает XCTest и XCUITest перед сборкой. Скрипт сверяет архитектуру ARM64, минимальную версию iOS, платформу Mach-O, подпись и содержимое `Payload/Veltrix.app`. Физический iPhone и подпись Apple ID проверяются отдельно. [Матрица функций](FEATURE_MATRIX.md) · [Решения](DECISIONS.md) · [Задачи и проверки](TASKS.md)
