# cs-template

Canonical source for shared AI instruction files, GitHub workflow templates, and project configuration for C# projects.

## Build Status

| Branch  | Status                                                |
|---------|-------------------------------------------------------|
| main    | [![Build: Pre-Release][pre-release-img]][pre-release] |
| release | [![Build: Release][release-img]][release]             |

## Familiar install

[`familiar/`](familiar) holds the files for a familiar install. Copy them into the install directory (`~/familiar`) next to a `.env`, which is not kept in this repository:

- [`.env.example`](familiar/.env.example): the variables `docker-compose.yaml` reads. Copy it to `.env` and fill it in.
- [`docker-compose.yaml`](familiar/docker-compose.yaml): runs the familiar broker, which starts the agent and MCP-server containers itself.
- [`update`](familiar/update): pulls the images, runs the broker's deploy check, then brings the stack up.
- [`reset`](familiar/reset): pulls the images, then stops, removes and recreates the containers.
- [`systemd/familiar-update.service`](familiar/systemd/familiar-update.service) and [`systemd/familiar-update.timer`](familiar/systemd/familiar-update.timer): run `update` hourly, at half past the hour. Install them by running `./install` from a clone of this repository (it uses `sudo`): it copies both units into `/etc/systemd/system/`, reloads systemd, and enables and restarts the timer.

## Changelog

View [changelog][changelog].

## Contributing

See [contributing guidelines][contributing].

## Security

See [security policy][security].

## Licence

This project is licensed under the [MIT Licence][licence].

[changelog]: CHANGELOG.md
[contributing]: CONTRIBUTING.md
[licence]: LICENSE
[pre-release-img]: https://github.com/credfeto/cs-template/actions/workflows/build-and-publish-pre-release.yml/badge.svg
[pre-release]: https://github.com/credfeto/cs-template/actions/workflows/build-and-publish-pre-release.yml
[release-img]: https://github.com/credfeto/cs-template/actions/workflows/build-and-publish-release.yml/badge.svg
[release]: https://github.com/credfeto/cs-template/actions/workflows/build-and-publish-release.yml
[security]: SECURITY.md
