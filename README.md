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

Each archive holds `heif-dec`, the `heif-convert` name Sluice invokes, five shared libraries and
five licence texts. Nothing a compiler would read.

## Running the build

It runs on request, never on a push, because its output only changes when a library version does.

```
gh workflow run build-libheif.yml --repo AdrianNachev91/sluice-package-rig --ref main \
  -f machines=all -f publish=true
```

While a toolchain is being fixed, name just that machine instead: `-f machines=windows.amd64`, or
several comma separated. Each one stops at its own point for its own reason, so a full run mostly
re-proves what already worked and buries the answer being waited on.

Publishing is refused unless the run built everything. A release missing an archive would fail
Sluice's packaging build on a download error rather than on anything naming the machine that was
never built.

Nothing here is meant for end users. If you are looking for Sluice itself, follow the link above.
