# FloatMon

FloatMon is a small macOS utility that lives as a draggable floating ball.
It highlights the app using the most CPU or memory, expands into an app list, and
can jump to individual app windows when Accessibility permission is granted.

## Requirements

- macOS 14 or newer
- Xcode command line tools
- Accessibility permission for window inspection, precise window focus, and native window close actions

## Build And Run

```sh
make build
make run
```

`make run` builds a local app bundle under `dist.noindex/`, stops any existing
instance, and launches the new bundle.

## Packaging

```sh
make package
make install
```

`make package` creates `dist.noindex/FloatMon.app`. If `Resources/logo.png`
exists, it is converted into the app icon during packaging. If
`Resources/logo.png` is missing, packaging falls back to `Resources/AppIcon.icns`. If
`CODE_SIGN_IDENTITY` is set, the bundle is signed with that identity. Otherwise,
the script tries to find a local development identity and falls back to ad-hoc
signing.

Ad-hoc signing is useful for local development, but macOS may ask for
Accessibility permission again after rebuilds because the app identity changes.

## Useful Commands

```sh
make stop     # stop a running FloatMon process
make clean    # remove build/package outputs
```

## Project Layout

- `Sources/FloatMon/App`: app delegate and floating panel window
- `Sources/FloatMon/Views`: SwiftUI view hierarchy
- `Sources/FloatMon/Services`: process, app, permission, and window-control services
- `Sources/FloatMon/Models`: plain data models and sorting/resource logic
- `script/package_app.sh`: SwiftPM app-bundle packaging
- `Resources/logo.png`: source image used for the packaged app icon

## License

MIT
