fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios attach_groups

```sh
[bundle exec] fastlane ios attach_groups
```

Привязать уже загруженный build к beta-группам

### ios upload_only

```sh
[bundle exec] fastlane ios upload_only
```

Загрузить уже собранный IPA в TestFlight

### ios build_and_testflight

```sh
[bundle exec] fastlane ios build_and_testflight
```

Собрать IPA и загрузить в TestFlight

### ios check

```sh
[bundle exec] fastlane ios check
```



### ios push_status

```sh
[bundle exec] fastlane ios push_status
```

Проверить / найти APNs Auth Key и Push capability у приложения

### ios team_info

```sh
[bundle exec] fastlane ios team_info
```

Показать Team ID и Bundle ID (нужно для APNs)

### ios who_am_i

```sh
[bundle exec] fastlane ios who_am_i
```

Проверить App Store Connect users

### ios promote_internal

```sh
[bundle exec] fastlane ios promote_internal
```

Найти или создать внутреннюю группу и засунуть туда актуальный build + email разработчика

### ios expire_old

```sh
[bundle exec] fastlane ios expire_old
```

Expire all builds except the latest

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
