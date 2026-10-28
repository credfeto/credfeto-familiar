# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
Please ADD ALL Changes to the UNRELEASED SECTION and not a specific release
-->

## [Unreleased]
### Security
### Added
- Familiar install files: docker-compose.yaml, the update and reset scripts, and the hourly familiar-update systemd service and timer, and a .env.example listing the variables docker-compose.yaml reads
### Fixed
### Changed
- familiar-update timer runs at half past the hour (plus up to 10 minutes of random delay) instead of on the hour, so it no longer clashes with hourly jobs that run on the hour
- SDK - Updated DotNet SDK to 10.0.403
### Deprecated
### Removed
### Deployment Changes

<!--
Releases that have at least been deployed to staging, BUT NOT necessarily released to live.  Changes should be moved from [Unreleased] into here as they are merged into the appropriate release branch
-->

## [0.0.0] - Project created