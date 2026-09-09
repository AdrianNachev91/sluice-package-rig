# sluice-package-rig

A verification rig for [Sluice](https://github.com/AdrianNachev91/sluice) installers.

Sluice is built and signed elsewhere. This repository holds no source code. What it holds is a
GitHub Actions workflow, a smoke-test script, and the packages under test, published here as
releases.

The job is the part that cannot be done from a developer machine: take a built package, install it
on a clean runner, launch it, and report what happened. macOS is the reason the repository is
public, because standard GitHub-hosted runners are free and unlimited on public repositories.

Nothing here is meant for end users. If you are looking for Sluice itself, follow the link above.
