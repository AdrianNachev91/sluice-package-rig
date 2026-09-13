# sluice-package-rig

A verification rig for [Sluice](https://github.com/AdrianNachev91/sluice) installers.

Sluice is built and signed elsewhere. This repository holds no source code. What it holds is two
GitHub Actions workflows, the scripts they run, and the packages under test, published here as
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

Each archive holds `heif-dec`, the `heif-convert` name Sluice invokes, the shared libraries the tool
loads and their licence texts. Nothing a compiler would read.

The Windows archive also carries Microsoft's C runtime, which is not part of Windows and arrives
with the Visual C++ redistributable. Without it the tool cannot start on a machine that has never
installed a program needing it. Each workflow run checks that claim rather than trusting it: every
binary's dependencies have to be either the operating system's own or present in the archive.

## Verifying a package

`.github/workflows/verify-package.yml` takes the packages off a release in this repository,
installs each one on a clean runner, and launches it. `smoke-test.sh` is what it runs there, and it
is an ordinary bash script that works on a developer machine too.

```
gh workflow run verify-package.yml --repo AdrianNachev91/sluice-package-rig --ref main \
  -f release_tag=sluice-0.1.0 -f expected_version=0.1.0 -f machines=all
```

macOS gets the archive marked as downloaded before it is unpacked, so Gatekeeper is asked the
question a user's own first launch asks. Windows installs the MSIX, which is the same path the
update channel runs through. Linux installs the deb.

Every check runs and the failures are counted, rather than the first one ending the job. A macOS
run takes long enough that answering one question per dispatch is its own cost.

## Releases in this repository

Two unrelated things are released here, and only one of them may carry GitHub's Latest label.

Sluice's own packages are built and signed elsewhere and published here as `sluice-<version>`.
Every URL baked into them resolves through `releases/latest/download`, so the Latest release is
what an installed copy reads as its update feed.

The decoder archives are published as `libheif-<version>` with that label explicitly refused. A
decoder release holding the label would leave every installed copy reading an update feed with no
application in it. Nothing on the machine would report an error. It would simply stop being offered
updates.

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
