# Cursor Chapter Marker

OBS Studio plugin that creates chapter markers in recordings triggered by hotkeys (or a foot pedal recognised as keyboard input), automatically embedding the mouse cursor position.

## Features

- **Press hotkey** → adds a marker: `+ Cursor X:1234 Y:567`
- **Release hotkey** → adds a marker: `- Cursor`
- Marker text is fully customisable (`%X` / `%Y` are substituted with cursor coordinates)
- Settings accessible via **Tools → Cursor Chapter Marker Settings**
- Settings persist per OBS scene collection
- Compatible with OBS 30+ chapter markers (embedded in recordings)
- Cross-platform: Windows, macOS, Linux

## Requirements

- OBS Studio ≥ 30.0 (requires `obs_frontend_recording_add_chapter`)
- CMake ≥ 3.16
- Qt 6 (bundled with OBS deps)
- Visual Studio 2022 (Windows) / Xcode / GCC

## Building (Windows)

### Prerequisites

1. Clone [OBS Studio](https://github.com/obsproject/obs-studio) and follow its Windows build guide to get the pre-built dependencies (`obs-deps` + `qt6`).
2. Set the `OBS_CMAKE_PREFIX_PATH` or `CMAKE_PREFIX_PATH` to the directory containing `libobs`, `obs-frontend-api`, and Qt 6.

The easiest approach is to build inside the OBS source tree:

```batch
# Inside your obs-studio clone
cd plugins
git clone https://github.com/<your-repo>/cursor-chapter-marker
```

Then add to `plugins/CMakeLists.txt`:

```cmake
add_subdirectory(cursor-chapter-marker)
```

Rebuild OBS and the plugin will be included.

### Standalone build

```batch
cmake --preset windows-x64 ^
  -DCMAKE_PREFIX_PATH="C:/path/to/obs-deps;C:/path/to/obs-studio/build"
cmake --build --preset windows-x64
```

The built DLL ends up in `build_x64/obs-plugins/64bit/cursor-chapter-marker.dll`.

### Installing

Copy to your OBS plugin directory (usually `C:\Program Files\obs-studio\obs-plugins\64bit\`) and restart OBS.

## Usage

1. Open **Settings → Hotkeys** in OBS and search for "Cursor Chapter".
2. Bind **Cursor Chapter: Press** to your foot pedal's down key.
3. Bind **Cursor Chapter: Release** to your foot pedal's up key.
4. Optionally customise the marker text via **Tools → Cursor Chapter Marker Settings**.
5. Start a recording — press your pedal to stamp markers with cursor position.

## Marker format

| Token | Replaced with |
|-------|--------------|
| `%X`  | Cursor X position (pixels from screen left) |
| `%Y`  | Cursor Y position (pixels from screen top) |

Default press format: `+ Cursor X:%X Y:%Y`  
Default release format: `- Cursor`

## License

GPL-2.0-or-later
