# Husky app icon

`Husky.png` is the generated husky-face artwork selected by the owner for the
application icon. It is the source for the macOS icon's standard resolutions.

For a local development bundle, run:

```sh
python3 Tools/Packaging/package-app.py /path/to/existing.app /path/to/output/Husky.app
```

The output path must not already exist. Packaging preserves the executable,
resource bundles, and bundle identifier, and sets both macOS name fields to
`Husky`. This keeps the existing app's preferences and backend configuration.
The tool is intended for unsigned development bundles; modifying a signed
bundle invalidates its signature. Release signing/notarization must happen
after packaging through the release workflow.
