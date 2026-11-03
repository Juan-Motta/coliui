# Security policy

## Report a vulnerability

Please report security issues privately through [GitHub's private vulnerability reporting](https://github.com/Juan-Motta/coliui/security/advisories/new), not in a public issue.

Include what you found, how to reproduce it, and the ColiUI version (Settings › About › Copy diagnostics). You'll get a reply within a few days; once a fix is out, the advisory is published with credit to you unless you'd rather stay anonymous.

## Supported versions

Only the latest release gets security fixes. ColiUI updates itself, so the fix reaches you through Settings › About › Updates.

## What's in scope

- **Updates:** ColiUI installs an update only when its EdDSA signature matches the key built into the app and its Developer ID matches the installed app. A way around either check is in scope.
- **Docker access:** ColiUI talks to the Docker Engine over Colima's local Unix socket and never opens a network port. Anything that exposes that socket, or runs commands in containers you didn't ask for, is in scope.
- **Secrets on screen:** environment values that look like credentials are masked in the Environment and Inspect tabs. Ways they leak unmasked (on screen, in copied text or in exports) are in scope.

Out of scope: vulnerabilities in Colima, Docker, or the containers and images you run.
