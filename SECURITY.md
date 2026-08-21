# Security Policy

## Supported Versions

Only the latest release of ZenOS is actively maintained. Security fixes will not be backported to older versions.

| Version | Supported |
|---------|-----------|
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a Vulnerability

If you discover a security vulnerability in ZenOS, **please do not open a public GitHub issue.** Instead, report it privately so it can be addressed before any public disclosure.

**To report a vulnerability:**

1. Go to the [Security Advisories](https://github.com/AnthonyGress/zen_ui.koplugin/security/advisories) page on GitHub.
2. Click **"Report a vulnerability"** and fill in the details.

Please include:

- A clear description of the vulnerability and its potential impact
- Steps to reproduce, if applicable
- Any relevant file paths, code references, or log output

## Response

Reported vulnerabilities will be reviewed and responded to as promptly as possible. Once a fix is ready, a new release will be published and the advisory will be made public.

## Scope

ZenOS is a client-side KOReader plugin written in Lua. It does not run a server or handle account authentication. It works with local library files and can download release assets and catalog content. The primary security surface is:

- The built-in ZenOS updater and ZenPM installer, which download and unpack release files over HTTPS
- Custom icon-pack ZIP validation and extraction
- File operations performed through the file browser patches

Out-of-scope reports (e.g. vulnerabilities in KOReader itself, or in the underlying device OS) should be directed to the appropriate upstream project.
