# AGENTS.md

PoneyhOS is a custom image [bootc](https://github.com/bootc-dev/bootc),
built on [fedora-kinoite 44](https://quay.io/fedora/fedora-kinoite:44)
and published to [ghcr.io](https://ghcr.io).
It derives from
[ublue-os/image-template](https://github.com/ublue-os/image-template).

## Markdown

All Markdown here follows [Semantic Line Breaks](https://sembr.org/).
Break after a sentence, or after an independent clause;
never wrap mid-clause just to fit a column.
Instead, you should evaluate if the line break is necessary.

The 80-character limit in `.rumdl.toml` is a guide, not a hard wrap.
A line carrying a link or a code span may exceed it, and that is fine.
A line break must never alter the rendered output,
so an inline link has to keep its `](` on one line —
splitting it there silently turns the link into plain text.

`rumdl` enforces this and runs from pre-commit. pre-commit lives in a dedicated
toolbox, not on the host.

## Commands

Everything goes through `just`.
Do not call `podman build` directly,
instead use the corresponding `just` recipe.
The `build` recipe attaches the OCI and ArtifactHub labels,
and reads the image name and tag from `image-template.env`.

| Command | What it does |
| --- | --- |
| **just** | Lists every available recipe |
| **just build** | Builds the image with podman, labels included |
| **just lint** | Runs shellcheck on every *.sh* |
| **just format** | Runs shfmt, in place, on every *.sh* |
| **just check** | Checks Justfile syntax **only**, not the shell scripts |
| **just fix** | Reformats the Justfile in place |
| **just build-iso**, **just run-vm** | Builds a disk image and boots it locally |

Read the `Justfile` before adding a build step.
It is the interface for this repository, and it already covers rechunking,
tagging, ISO and VM builds.

## Verify instead of recalling

Package names, versions and repository layouts drift.
Query the real image rather than trusting memory:

```shell
podman run --rm quay.io/fedora/fedora-kinoite:44 dnf list --available 'akmod-nvidia*'
```

This costs seconds and has already caught several wrong assumptions.

## Local build gotcha

After an interrupted build,
the `--mount=type=cache,dst=/var/cache` in the `Containerfile` can hold
zero-filled RPMs, which surface as a misleading `... : not a rpm` on the next
run.
Clear it with `rm -rf /var/tmp/buildah-cache-$(id -u)`.
CI always starts cold and is unaffected.

## Image invariants

These are the things that fail silently, or fail far away from their cause.

- The base image is pinned by digest and updated by Renovate.
  Keep the `@sha256:` when changing the tag.
- `dnf` is present and so is dnf5 so there is no need
to fall back to `rpm-ostree` in [build.sh](./build_files/build.sh).
- `/opt` must stay a real directory.
  `RUN rm /opt && mkdir /opt` in the `Containerfile` is not decoration:
  `mullvad-vpn` installs into `/opt/Mullvad VPN`,
  and rpm cannot create that path while `/opt` is a symlink to `/var/opt`.
- Every NVIDIA package must be the same version (userspace and kernel module).
  A mismatch builds cleanly
  but loads nothing at boot with [build.sh](./build_files/build.sh) asserting
  this, so do not remove the check.
- Kernel modules are compiled at image build time, never at boot.
  The deployment is immutable and `/usr` is read-only,
  so akmods cannot rebuild anything on the target machine.
- Kernel arguments belong in
  [system_files/usr/lib/bootc/kargs.d/](./system_files/usr/lib/bootc/kargs.d/)
  with new configuration added as *.toml* files.
  `grubby` does not work on a bootc system.
- [system_files/](./system_files/) is copied to `/` by
  [build.sh](./build_files/build.sh).
  A new subdirectory there stays untracked until you `git add` it explicitly,
  CI will happily build without it.
