# sluice-package-rig

A verification rig for [Sluice](https://github.com/AdrianNachev91/sluice) installers.

Sluice is built and signed elsewhere. This repository holds no source code. What it holds is a
GitHub Actions workflow, a smoke-test script, and the packages under test, published here as
releases.

The job is the part that cannot be done from a developer machine: take a built package, install it
on a clean runner, launch it, and report what happened. macOS is the reason the repository is
public, because standard GitHub-hosted runners are free and unlimited on public repositories.

That same reason gives it a second job. Sluice bundles a HEIF decoder so nobody has to install one
by hand, and nothing published covers every machine it ships to. Upstream releases source only.
Other distributions are tied to one Linux flavour, one Windows build from 2022, or Homebrew's own
prefix. So `.github/workflows/build-libheif.yml` builds that decoder here, one archive per machine,
and Sluice's packaging step reads them straight off this repository's releases.

Decode only, and dynamically linked. Sluice reads HEIC and AVIF and writes neither, so no encoder is
built. Shipping the shared library beside the tool is what lets somebody replace it, which is what
its LGPL licence is for.

Nothing here is meant for end users. If you are looking for Sluice itself, follow the link above.
