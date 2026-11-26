# Задачи и проверки

## VELTRIX 9.0 Final Edition

- [x] Confirm 6f4baa5 Recovery baseline. Release job 45825393851 succeeded. Simulator job 45820541270 passed on ancestor 91a659a.
- [x] Confirm existing archive commit marker and verify a full-history Git backup in ignored dist/.
- [x] Confirm existing public repository and standard macOS runner.
- [ ] Complete repository and asset audit, including historical archives and CI artifacts.
- [ ] Verify navigation, Home, search, and Settings copy in the simulator.
- [ ] Complete Markets, analytics, cards, history, QR, notifications, authentication, and remaining UX work.
- [ ] Verify migration, visual acceptance, and final ARM64 IPA.

## Veltrix 7.1

- [x] Заменить PIN приложения авторизацией iOS с политикой `.deviceOwnerAuthentication` и сохранить включённую блокировку при обновлении.
- [x] Переработать редактор Buy, Sell и Swap, проверку, подтверждение и завершение сделки.
- [x] Проверить конвертацию Decimal, резерв лимитных ордеров и MAX для дробных остатков.
- [x] Подключить системную доставку через `UNUserNotificationCenter` с диагностикой разрешений и ошибок.
- [ ] Проверить итоговый прогон, просмотреть скриншоты и сверить Release ARM64 на Windows.
- [ ] Проверить Face ID, ввод код-пароля и отображение системного баннера на физическом iPhone.

## Veltrix 7.0

- [x] Обновить айдентику, навигацию, Home, Explore, Profile, Activity и Settings.
- [x] Добавить запуск, новый экран блокировки и камерный QR-сканер.
- [x] Доработать ввод, проверку и завершение локальных операций.
- [x] Добавить локальные уведомления, настройки приватности и переходы к записи.
- [x] Расширить визуальные варианты карт и студию.
- [x] Изолировать базу съёмочного портфеля и проверить возврат к основной базе.
- [x] Проверить итоговую ревизию на macOS, просмотреть скриншоты XCTest и собрать ARM64 IPA.
- [ ] Проверить камеру, биометрию, системные баннеры и установку на физическом iPhone.

### Проверенная сборка Veltrix 7.0.0

- Исходный коммит `ea130ed`. Xcode 26.3 на GitHub Actions. Прошли 21 модульный тест и 7 UI-тестов. [Итоговый запуск](https://github.com/hutoru/Veltrix/actions/runs/45683787373)
- Просмотрены 17 снимков iPhone SE (3-го поколения) из изолированных UI-тестов. Тест рыночной покупки и снимок Home подтвердили отображение общей стоимости после покупки дробного количества BTC. На снимке сканера показано состояние недоступной камеры.
- `dist/Veltrix.ipa` содержит неподписанный Release для iPhoneOS ARM64 с минимальной версией iOS 16.0 и локализациями EN/RU. SHA-256 сверена после скачивания на Windows. Тестовые котировки исключены из Release.
- Индивидуальные PNG лежат в `dist/screenshots`, архив — в `dist/Veltrix-Screenshots.zip`. Проверка iPhone XS и iPhone 15 Pro Max, включая CoreMotion и частоту кадров, остаётся отдельным этапом.

## Предыдущие версии

- [x] Изучить Larpy и составить матрицу функций.
- [x] Создать модель, торговый движок, лимитные ордера, виртуальные карты и локальное хранилище.
- [x] Подключить публичные котировки, историю, WebSocket, курсы валют и кеш.
- [x] Реализовать пять разделов, интерактивные графики, публикацию результата и резервные копии.
- [x] Добавить свой бренд, локализации, темы, PIN и биометрическую блокировку.
- [x] Написать XCTest и XCUITest, подготовить XcodeGen, GitHub Actions и загрузку IPA на Windows.
- [x] Выполнить Xcode-тесты на GitHub Actions и проверить итоговый IPA.
- [ ] Подписать и проверить на физическом iPhone XS при подключённом устройстве.

## Проверенная сборка

- VELTRIX 1.0.0, исходный коммит `1480b16`. [Успешный запуск GitHub Actions](https://github.com/hutoru/Veltrix/actions/runs/45634483549)
- Xcode 26.3, iPhone SE (3-го поколения), iOS 26.2 Simulator. Прошли 16 модульных тестов и 3 UI-теста.
- Release IPA скачан и проверен в Windows. В `Payload/Veltrix.app` находятся ARM64 Mach-O для iPhoneOS, ресурсы и обе локализации. В бинарнике и Info.plist указан iOS 16.0. Mach-O не содержит команды подписи. SHA-256 совпадает с контрольной суммой артефакта.
- Публичные API проверены отдельно. CoinGecko вернул котировки всех 30 активов. Frankfurter покрыл все 77 кодов валют с учётом базового USD. Kraken вернул исторические свечи и реальную сделку BTC/USD через WebSocket.
- Установка и биометрия на физическом iPhone XS, а также запуск на рантайме iOS 16 ожидают проверки на устройстве.
