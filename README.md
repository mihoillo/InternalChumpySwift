# InternalChumpySwift

Chumpy for iOS — нативный SwiftUI-порт [Chumpy](https://github.com/ChumpyXray/Chumpy) (Android).

**Work in progress — not ready for use.**

## Структура

```
project.yml          — спека xcodegen (Xcode-проект генерится в CI)
Packages/
  ChumpyCore/        — общее ядро (модели, парсеры, стор) + юнит-тесты (swift test)
  SwiftyXrayKit/     — вендоренный движок (Xray-core через libXray-apple XCFramework)
App/                 — SwiftUI-приложение
Tunnel/              — NetworkExtension (NEPacketTunnelProvider)
.github/workflows/   — CI: swift test + сборка под iOS Simulator
```

## Минимальные версии

- iOS 15.0 (материалы `.regularMaterial`/`.ultraThinMaterial` и SwiftyXrayKit требуют iOS 15)
- Liquid Glass (iOS 26) — позже, через `#available(iOS 26, *)` с фолбэком на материалы

## Сборка локально

```shell
brew install xcodegen
xcodegen generate
open ChumpySwift.xcodeproj   # scheme Chumpy, iOS-симулятор
```

Для запуска на устройстве нужны: Development Team + capability
`App Group (group.slop.miho.chumpy.swift)` и `Network Extension (packet-tunnel-provider)`
на обоих таргетах. CI собирает без подписи (симулятор + unsigned IPA для TrollStore);
подписанный билд в TestFlight льёт отдельный воркфлоу — см. [docs/testflight.md](docs/testflight.md).

## Дорожная карта

- [x] M0 — каркас, таргеты, CI
- [ ] M1 — портирование парсеров (vmess/vless/trojan/ss/socks, конфиги, подписки) + тесты
- [ ] M2 — рабочий туннель с выбранным профилем, routing global/bypass
- [ ] M3 — экраны: список серверов, подписки, добавление профилей
- [ ] M4 — автообновление подписок, трафик, ping
- [ ] M5 — полировка, RU/EN, Liquid Glass (iOS 26)

## Credits

- [Xray-core](https://github.com/XTLS/Xray-core) / [libXray-apple](https://github.com/dima-u/libXray-apple) / [SwiftyXrayKit](https://github.com/dima-u/SwiftyXrayKit) (Apache-2.0) — движок
- [Mango](https://github.com/Arror/Mango) — референс iOS-структуры VPN-клиента
- Chumpy (Android) — исходный клиент
