# Zen UI KOReader Plugin

Zen UI is a modular KOReader plugin that unifies this repository's user patches into a single, centralized plugin with:

- one settings source of truth
- progressive migration from legacy patch settings
- feature toggles for each UI behavior
- localization scaffolding for multiple languages
- a safe mode to recover quickly from hook conflicts

## Current status

Implemented in this pass:

- plugin entrypoint and metadata: [main.lua](main.lua), [_meta.lua](_meta.lua)
- centralized config manager: [config/manager.lua](config/manager.lua)
- schema defaults: [config/defaults.lua](config/defaults.lua)
- legacy settings migration (initial): [config/migrate.lua](config/migrate.lua)
- module registry and module loaders: [modules/registry.lua](modules/registry.lua), [modules](modules)
- unified settings menu (first version): [settings/menu.lua](settings/menu.lua)
- localization scaffolding: [locales](locales)

The first implementation wraps existing patch files through module loaders, so behavior remains close to current patches while internals are migrated to native module code.

## Architecture

Core folders:

- [config](config): centralized schema, persistence, migration
- [common](common): shared utility and loader code
- [modules](modules): feature modules (currently legacy-backed wrappers)
- [settings](settings): unified settings UI integration
- [locales](locales): gettext catalogs

## Feature toggles

Current toggle groups in `zen_ui_config`:

- `features.navbar`
- `features.quick_settings`
- `features.disable_default_koreader_menu_sections`
- `features.titlebar`
- `features.hide_pagination`
- `features.disable_top_menu_swipe_zones`
- `features.browser_hide_up_folder`
- `features.reader_header_clock`
- `zen.safe_mode`

Always-on (not user-toggleable in Zen settings):

- `features.browser_folder_cover`
- `features.browser_hide_underline`

## Legacy migration

The plugin currently maps legacy keys into the new feature namespace on load:

- `bottom_navbar` -> `features.navbar`
- `quick_settings_panel` -> `features.quick_settings`
- `custom_status_bar` -> `features.titlebar`
- `filemanager_hide_up_folder` -> `features.browser_hide_up_folder`
- `filemanager_hide_empty_folder` -> `features.browser_hide_up_folder`
- `folder_hide_underline` -> `features.browser_hide_underline`

This is the first migration step and will be expanded to full nested setting import.

## Locales

Scaffolded locales:

- `en`, `it`, `es`, `fr`, `nl`, `pt_BR`, `pt_PT`, `ro`, `ru`, `zh_CN`, `zh_TW`

See [locales/README.md](locales/README.md).

## Next implementation steps

1. Replace legacy wrappers with native module code (starting with navbar and statusbar).
2. Build dedicated unified settings screen with grouped sections.
3. Implement Zen filebrowser context menu replacement.
4. Add cover mosaic styling controls (radius, read state, read percent).
5. Add updater integration for GitHub Releases.
