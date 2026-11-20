# TestFlight через CI

Подписанный Release-билд собирается и заливается в App Store Connect
воркфлоу `.github/workflows/testflight.yml` (macos-runner, ручной запуск:
Actions → TestFlight → Run workflow). Нон-профит аккаунт функционально
не отличается от обычного Apple Developer Program — TestFlight доступен
на любом активном аккаунте; для организаций Apple списывает членский
взнос, всё остальное то же.

## 1. Разовое: приложение в App Store Connect

1. **Соглашения.** Пользователь с ролью **Legal** в App Store Connect
   (asc.apple.com) принимает все соглашения в
   *Business / Agreements, Tax, and Banking* — без этого загрузка билдов
   заблокирована.
2. **Доступ.** Твой Apple ID приглашается в *Users and Access* с ролью
   **Admin** или **App Manager**.
3. **Приложение.** *My Apps → «+» → New App*: платформа iOS, имя
   `Chumpy`, язык, bundle ID `slop.miho.chumpy.swift` (App ID и App Group
   `group.slop.miho.chumpy.swift` регистрируются автоматически при первой
   подписанной сборке — см. шаг 3 ниже; если авто-регистрация споткнётся,
   пропиши их руками в *Certificates, Identifiers & Profiles*).

## 2. Разовое: API-ключ и секреты

1. App Store Connect → *Users and Access → Integrations → App Store
   Connect API → «+»*: имя любое, роль **App Manager** (доступ к
   Certificates, Identifiers & Profiles нужен для авто-подписи в CI).
2. Скачай `.p8` (Key ID и Issuer ID видны в таблице).
3. В настройках репозитория *Settings → Secrets and variables →
   Actions → New repository secret* добавь:

   | Секрет                | Значение                                        |
   |-----------------------|-------------------------------------------------|
   | `ASC_KEY_ID`          | Key ID из таблицы ключей                        |
   | `ASC_ISSUER_ID`       | Issuer ID (общий для аккаунта)                  |
   | `ASC_KEY_P8_BASE64`   | `base64 -w0 AuthKey_XXXX.p8`                   |
   | `ASC_TEAM_ID`         | Team ID аккаунта (Membership → Team ID)         |

Опционально `DIST_CERT_P12_BASE64` + `DIST_CERT_PASSWORD` — если хочешь
пинить конкретный дистрибуционный сертификат вместо cloud signing
(Xcode сам создаст managed-сертификат, когда `.p12`-секретов нет).

## 3. Запуск

Actions → **TestFlight** → *Run workflow*. Что делает воркфлоу:

- `xcodegen generate` → `xcodebuild archive` (Release, устройство) с
  `-allowProvisioningUpdates` — Xcode по API-ключу сам регистрирует
  App ID, App Group, capabilities и профили для обоих таргетов
  (Chumpy + ChumpyTunnel);
- номер сборки (`CURRENT_PROJECT_VERSION`) = номер запуска воркфлоу —
  каждый аплоад уникален, руками ничего бампать не надо;
  `MARKETING_VERSION` из `project.yml` меняется только для новой
  версии;
- `xcodebuild -exportArchive` с `destination: upload` заливает IPA в
  App Store Connect (символы прилагаются).

Через 15–30 минут билд появится в *TestFlight*.

## 4. Тестеры

- **Internal** (до 100): тестеры — пользователи App Store Connect с
  любой ролью; добавляются в TestFlight-вкладке приложения, билд
  доступен сразу, **бета-ревью не нужен**. Самый быстрый путь.
- **External** (до 10 000, публичная ссылка или e-mail): первый билд
  каждой версии проходит **Beta App Review**. Для VPN-клиента
  понадобятся: privacy policy URL, описание что делает приложение,
  ответы на вопросы о приватности (сбор данных — «нет», если клиент
  ничего не телеметрит).

## Если что-то падает

- **«No signing certificate»** на archive — cloud signing не создал
  сертификат: создай дистрибуционный сертификат и положи его в
  `DIST_CERT_P12_BASE64` (+ пароль).
- **«Your account has reached the maximum number of certificates»**
  на archive — раньше означало, что CI наштамповал «Xcode Managed
  Distribution» до лимита (каждый раннер — чистая VM с пустой связкой
  ключей, поэтому cloud signing выпускает новый сертификат на каждый
  запуск). Теперь воркфлоу сам отзывает старые Xcode-managed серты
  перед архивом (`.github/scripts/prune_distribution_certs.py`,
  руками созданные не трогает). Если упало и после этого — остаток
  лимита занят сертификатами, созданными вручную: отзови лишний в
  *Certificates, Identifiers & Profiles → Certificates* или запини
  один в `DIST_CERT_P12_BASE64` + `DIST_CERT_PASSWORD` (тогда новые
  вообще не создаются) и нажми **Re-run failed jobs**.
- **«No app found with bundle id»** — приложение не создано в ASC
  (шаг 1.3) или bundle ID в `project.yml` не совпадает.
- **Профиль не собирается на App Group** — зарегистрируй
  `group.slop.miho.chumpy.swift` руками в *Identifiers → App Groups*
  и добавь его в оба App ID.
- Логи упавшего запуска — артефакт `testflight-logs`.
