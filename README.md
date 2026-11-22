# cs-template

Canonical source for shared AI instruction files, GitHub workflow templates, and project configuration for C# projects.

## Build Status

| Branch  | Status                                                |
|---------|-------------------------------------------------------|
| main    | [![Build: Pre-Release][pre-release-img]][pre-release] |
| release | [![Build: Release][release-img]][release]             |

## Familiar install

The git clone of this repository is the install directory (`~/familiar`), so there is nothing to copy. Clone it there, copy `.env.example` to `.env` (which is not kept in this repository) and fill it in, then run `./install` to set up the hourly update, or run `./update` to deploy by hand. To upgrade the install, `git pull` in the clone. These are the files an install uses:

- [`.env.example`][env-example]: the variables `docker-compose.yaml` reads. Copy it to `.env` and fill it in.
- [`docker-compose.yaml`][docker-compose]: runs the familiar broker, which starts the agent and MCP-server containers itself.
- [`update`][update]: pulls the images, then exits without touching the containers if they and the resolved compose configuration (`docker-compose.yaml` with `.env` applied) are unchanged since the last deploy and the broker is running, so a change to `.env` or `docker-compose.yaml` is deployed even when no image has changed. Only a SHA-256 hash of the configuration is recorded, never the configuration itself, since it holds the secrets from `.env`; the first run after upgrading from a version that did not record it redeploys once. If the broker is not running, it skips the deploy check. Otherwise it runs the broker's deploy check, each attempt limited to 30 seconds, and retries it up to 20 times, 5 seconds apart, while the check reports busy, inconclusive, timed out or failed. After each attempt that is not busy it re-checks the broker, and goes straight on if the broker has stopped. If the check never reports safe, `update` fails, after about 13 minutes at worst. It then brings the stack up, confirms the broker is running and records the deployed images and the configuration hash.
- [`busy`][busy]: runs the broker's deploy check to show whether turns are in flight.
- [`reset`][reset]: pulls the images, then stops, removes and recreates the containers, even when the images are unchanged. Before stopping anything it runs the same deploy check as `update`, with the same limits and retries, and skips it when the broker is not running; if the check never reports safe, `reset` fails without touching the containers. Once the broker is back up it records the deployed images and the configuration hash, so the next `update` does nothing when neither has changed.
- [`systemd/familiar-update.service`][service-unit] and [`systemd/familiar-update.timer`][timer-unit]: run `update` hourly, at half past the hour. systemd stops a run that takes longer than 45 minutes, so a hung `docker compose pull` or `up -d` cannot keep the timer from firing again. Install them by running `./install` from the clone (it uses `sudo`): it copies both units into `/etc/systemd/system/`, reloads systemd, and enables and restarts the timer.

The tests for `update`, `busy`, `reset` and `install` live in [`test/`][test] and run with `bats test/`. They put stub `docker`, `sudo`, `systemctl` and `timeout` commands first on `PATH`, so they never touch the real containers or systemd.

## Changelog

View [changelog][changelog].

## Contributing

See [contributing guidelines][contributing].

## Security

See [security policy][security].

## Licence

This project is licensed under the [MIT Licence][licence].

[busy]: busy
[changelog]: CHANGELOG.md
[contributing]: CONTRIBUTING.md
[docker-compose]: docker-compose.yaml
[env-example]: .env.example
[licence]: LICENSE
[pre-release-img]: https://github.com/credfeto/cs-template/actions/workflows/build-and-publish-pre-release.yml/badge.svg
[pre-release]: https://github.com/credfeto/cs-template/actions/workflows/build-and-publish-pre-release.yml
[release-img]: https://github.com/credfeto/cs-template/actions/workflows/build-and-publish-release.yml/badge.svg
[release]: https://github.com/credfeto/cs-template/actions/workflows/build-and-publish-release.yml
[reset]: reset
[security]: SECURITY.md
[service-unit]: systemd/familiar-update.service
[test]: test
[timer-unit]: systemd/familiar-update.timer
[update]: update
