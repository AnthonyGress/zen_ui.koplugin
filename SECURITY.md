# Security Policy

## Supported Versions

Only the latest release of Zen UI is actively maintained. Security fixes will not be backported to older versions.

| Version | Supported |
|---------|-----------|
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a Vulnerability

If you discover a security vulnerability in Zen UI, **please do not open a public GitHub issue.** Instead, report it privately so it can be addressed before any public disclosure.

**To report a vulnerability:**

1. Go to the [Security Advisories](https://github.com/AnthonyGress/zen_ui.koplugin/security/advisories) page on GitHub.
2. Click **"Report a vulnerability"** and fill in the details.

Alternatively, you can reach out directly by opening a [private issue](https://github.com/AnthonyGress/zen_ui.koplugin/issues) and marking it as confidential, or by contacting the maintainer through GitHub.

Please include:

- A clear description of the vulnerability and its potential impact
- Steps to reproduce, if applicable
- Any relevant file paths, code references, or log output

## Response

Reported vulnerabilities will be reviewed and responded to as promptly as possible. Once a fix is ready, a new release will be published and the advisory will be made public.

## Scope

Zen UI is a client-side KOReader plugin written in Lua. It does not run a server, handle authentication, or process external user data. The primary security surface is:

- The built-in updater, which downloads and unpacks files from GitHub Releases over HTTPS
- Any file operations performed through the file browser patches

Out-of-scope reports (e.g. vulnerabilities in KOReader itself, or in the underlying device OS) should be directed to the appropriate upstream project.
