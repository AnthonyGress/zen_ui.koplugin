---
title: Contributing
category: Contributing
summary: Report bugs, request features, or open a pull request against the dev branch.
settingsPath: ''
order: 90
---

<!-- Documentation current through ZenOS v3.0.0. -->

Contributions that keep it clean, minimal, and performant are most welcome.

> **Open all [pull requests](https://github.com/AnthonyGress/zen_ui.koplugin/pulls) against the `dev` branch.** PRs are tested and reviewed on `dev` before being merged. PRs opened against `main` will be asked to retarget.

## Ways to contribute

| Type | How |
| --- | --- |
| Bug report | Open an [Issue](https://github.com/AnthonyGress/zen_ui.koplugin/issues) describing what went wrong |
| Feature request | Open an [Issue](https://github.com/AnthonyGress/zen_ui.koplugin/issues) with your idea |
| Translation | Add or improve a `.po` file in `locales/` — see [Translations](/zen-os/docs/translations) |
| Code | Fork, branch, change, and open a Pull Request to `dev` |
| Documentation | Improve the README or add inline comments |

## Reporting a bug

Open an [Issue](https://github.com/AnthonyGress/zen_ui.koplugin/issues) and include:

- A clear description of what happened and what you expected.
- Your KOReader version (**Zen Settings > About > Device > KOReader**).
- Your device model (e.g. Kobo Libra 2, Kindle Paperwhite 5).
- Steps to reproduce the problem, if you can.

If the bug causes a crash, attach the KOReader log (`crash.log` in the KOReader folder).

## Suggesting a feature

Open an [Issue](https://github.com/AnthonyGress/zen_ui.koplugin/issues) describing the feature and why it would be useful. Keep ZenOS's philosophy in mind — features should reduce clutter or add something genuinely useful. Screenshots or mockups are welcome.

## Contributing code

ZenOS is a standard KOReader plugin written in Lua. No build system or compilation step is required — the plugin runs directly from source.

To test changes:

1. Copy the `zenos.koplugin` folder to the `plugins/` directory on your device or the KOReader emulator.
2. Restart KOReader to reload the plugin.

The [KOReader emulator](https://github.com/koreader/koreader/blob/master/doc/Building.md) is the fastest way to iterate without a physical device.

Run the repository checks from the plugin root when your change touches the related area:

```sh
./spec/run lua
./spec/run smoke
./spec/run package-check
```

### Building

To generate a production-ready build, run the build script from the plugin root:

```sh
./build.sh
```

This produces the canonical `zenos.koplugin.zip` and the legacy updater bridge
`zen_ui.koplugin.zip`. Their payloads are identical except for the root folder.

### Linting

ZenOS uses [LuaCheck](https://github.com/mpeterv/luacheck) for static analysis. Install it once with `luarocks install luacheck`, then run from the plugin root:

```sh
luacheck -q _meta.lua main.lua common config modules
```

### Making a change

1. [Fork](https://github.com/AnthonyGress/zen_ui.koplugin/fork) the repository.
2. Create a branch for your change: `git checkout -b fix/my-bug-description`.
3. Make your changes.
4. Wrap any new user-visible strings in `_()` so they can be translated:
   ```lua
   text = _("Something went wrong.")
   ```
5. Add new strings to `locales/en.po` with an empty `msgstr ""`.
6. Run `./build.sh` to generate the production-ready build and verify it works.
7. Commit with a clear message describing what changed and why.
8. Push your branch and **open a Pull Request against the `dev` branch**.

## Pull request checklist

- One feature or fix per PR.
- The change works on a real device or the KOReader emulator.
- Any new UI strings are wrapped in `_()` and added to `locales/en.po`.
- `./build.sh` runs successfully and produces a working build.
- The commit message clearly describes the change.
- No debug logging or commented-out code is left in.
- The PR targets the `dev` branch.
