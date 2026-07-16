# ATHM Animation Making Tool

Flutter-приложение для подготовки разметки анимации диалогов мода
Ashes: Hard Reset. Основная целевая платформа — Windows.

## Требования

- Flutter stable с поддержкой Windows desktop;
- Visual Studio с workload **Desktop development with C++**;
- включённый Windows Developer Mode (нужен Flutter-плагинам);
- `ffmpeg` в `PATH` для чтения и конвертации OGG и других аудиоформатов.

На Windows путь к Flutter SDK не должен содержать пробелы: native-assets hooks
новых версий Dart некорректно обрабатывают такие пути. Для этой машины проект
настроен на junction `D:\flutter_sdk`.

## Запуск

```powershell
flutter pub get
flutter run -d windows
```

## Проверка и сборка

```powershell
flutter analyze
flutter test
flutter build windows
```

Готовая сборка появляется в `build/windows/x64/runner/Release`.
