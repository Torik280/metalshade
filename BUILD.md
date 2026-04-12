# MetalShade — как собрать

> **Нужен Mac** — Swift + Metal компилируются только на macOS.  
> Минимум: macOS 13 Ventura + Xcode 15 (или только Command Line Tools).

---

## Способ 1 — одна команда (без Xcode)

```bash
./build.sh
open MetalShade.app
```

Скрипт делает:
1. `swift build -c release` (universal binary: arm64 + x86_64)
2. Пакует в `MetalShade.app`
3. Подписывает ad-hoc через `codesign`

---

## Способ 2 — Xcode проект (удобнее для разработки)

```bash
brew install xcodegen          # один раз
xcodegen generate              # создаёт MetalShade.xcodeproj
open MetalShade.xcodeproj
```

Дальше в Xcode: ⌘R — и готово.

---

## Первый запуск — разрешение на запись экрана

macOS спросит сам. Если нет — вручную:

> **System Settings → Privacy & Security → Screen Recording → MetalShade → ON**

Перезапусти приложение после выдачи разрешения.

---

## Как пользоваться

- Плавающая панель появляется без иконки в Dock
- Главный тогл **Post-Processing** включает оверлей
- Включай эффекты, регулируй интенсивность ползунком
- Работает с **любым** приложением на экране (игры, браузер, что угодно)
- Панель перетаскивается за фон
- ✕ закрывает приложение

---

## Свои шейдеры

Открой `Sources/MetalShade/Rendering/BuiltinShaders.swift`  
и добавь MSL-функцию в конец строки `builtinShaderSource`:

```metal
kernel void fx_myeffect(
    texture2d<float, access::read>  inTex     [[texture(0)]],
    texture2d<float, access::write> outTex    [[texture(1)]],
    constant float&                 intensity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = inTex.get_width(), h = inTex.get_height();
    if (gid.x >= w || gid.y >= h) return;
    float4 c = inTex.read(gid);
    // ... твой код ...
    outTex.write(c, gid);
}
```

Затем в `Sources/MetalShade/Models/ShaderEffect.swift` добавь в массив `effects`:

```swift
ShaderEffect(name: "My Effect", description: "...", functionName: "fx_myeffect")
```

Пересобери — шейдер скомпилируется при запуске автоматически.

---

## Структура проекта

```
MetalShade/
├── build.sh                      ← собрать одной командой
├── project.yml                   ← spec для xcodegen
├── MetalShade.entitlements       ← права (screen capture)
└── Sources/MetalShade/
    ├── MetalShadeApp.swift       ← @main точка входа
    ├── AppDelegate.swift         ← создаёт окна, запускает захват
    ├── Models/
    │   └── ShaderEffect.swift    ← состояние шейдеров (ObservableObject)
    ├── Capture/
    │   └── CaptureEngine.swift   ← ScreenCaptureKit, 60fps
    ├── Rendering/
    │   ├── MetalRenderer.swift   ← GPU pipeline, ping-pong текстуры
    │   ├── OverlayWindow.swift   ← прозрачное окно поверх всего
    │   └── BuiltinShaders.swift  ← MSL шейдеры (Sharpen, Bloom, Vibrance…)
    └── UI/
        ├── ControlPanel.swift    ← SwiftUI панель
        └── NeonComponents.swift  ← NeonToggle, NeonSlider, GlowText
```
