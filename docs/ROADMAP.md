# Roadmap

What is left between the current state of the repository
and the day PoneyhOS replaces Kinoite as the main system.
Each entry fits in a commit or a small PR,
and carries a verifiable completion criterion rather than an intention.

Two conditions govern this document: a green CI, and the tooling ready.
Anything serving neither is listed at the end of the file, out of scope,
so that it does not creep back into the critical path.

Effort: `XS` under half an hour, `S` an hour, `M` half a day.
Status: `todo`, `in progress`, `done`.

## The driver comes from NVIDIA, not from RPMFusion

This reverses the first approach.
The README still describes the old one and is wrong until `N25`.

RPMFusion builds the module through `akmod-nvidia`,
whose `%post` calls `akmodsbuild`, which refuses to run as root —
the only thing we are inside a container build.
Working around it means creating the `akmods` account by hand,
installing every akmod without scriptlets,
and hoping that `akmods --force` does not hit the same refusal.
That last point was never verified.

NVIDIA publishes its own repository for Fedora 44.
It ships the open kernel modules as a dkms package,
and CUDA beside them. dkms builds as root and takes the target kernel
as an argument, which is exactly what an image build needs.

The two sources must never be mixed: both package the same userspace libraries,
and a mix resolves cleanly then breaks at runtime.

The pinned version is `615.71.09`.
The machine runs `610.57.04` today, from RPMFusion,
and shows an occasional display blackout
that nothing in the kernel log accounts for.
Moving up is a deliberate attempt at it, not a requirement:
`610.57.04` is in the same repository
and `bootc rollback` makes the round trip cheap.

## Critical path

Six strictly sequential steps, each blocked by the previous one.
The rest of the document can move in parallel, these cannot.

1. `N1` — pin the version, and keep RPMFusion away from the nvidia packages
1. `N2` — install the dkms toolchain with its scriptlets
1. `N3` — build the module with dkms, against the kernel of the image
1. `N5` — a complete green local build
1. `N9` — first green CI on the PR
1. `N18` — switch over with `bootc switch` on the real machine

## Phase 0 — Unblock the build

Nothing else can move while the module is not built.

### N1 — Pin the version, and keep RPMFusion away from the nvidia packages

Status: done · Effort: `S` · Depends on: —

`build.sh` installs `nvidia-driver` with the following version of nvidia driver:
`615.71.09`.
We manually update the driver when nvidia push a new version.

RPMFusion free and nonfree stay enabled for everything else.
An `excludepkgs` on every one of them makes the separation a property of the
build rather than an ordering accident.
The pattern matches anything containing `nvidia`:
a narrower one let `xorg-x11-drv-nvidia` through,
since its name ends on `nvidia` and carries no trailing separator.

Done when: the version appears in exactly one place in `build.sh`,
and every nvidia package on the built image carries it.
Two legitimate exceptions, confirmed on the image:
`nvidia-gpu-firmware` comes from Fedora and follows its own dates,
and `nvidia-driver-selinux` is built from its own source rpm at `0.1`.
The exclusion itself is proven by querying the repositories rather than reading
their configuration: `dnf repoquery` against RPMFusion must return nothing for
`*nvidia*`, with a control package such as `ffmpeg` still resolving, otherwise
an unsupported glob would make the check pass by selecting no repository at all.

### N2 — Install the dkms toolchain with its scriptlets

Status: done · Effort: `XS` · Depends on: —

`kmod-nvidia-open-dkms` requires `dkms >= 3.1.8`,
`gcc-c++` and `nvidia-kmod-common`,
and it arrives as a dependency of `nvidia-driver`.

The `noscripts` approach was dropped:
the flag applies to a whole transaction rather than to the package named on the
command line, so it also skipped the scriptlets of every dependency pulled
alongside.
What the scriptlet actually had to be stopped from doing is regenerating the
initramfs, which Fedora's dkms triggers through `dracut --regenerate-all`.
A `post_transaction=""` override in `/etc/dkms/framework.conf.d` disables
that hook alone, and is removed once the module is built.

Done when: `dkms build` and `dkms install` run against the kernel of the image
and the module lands in `/usr/lib/modules/<kver>/extra`.

### N3 — Build the module with dkms, against the kernel of the image

Status: done · Effort: `M` · Depends on: `N1`, `N2`

The most uncertain point of the whole effort.

The `%post` of the dkms package builds against `uname -r`,
which inside a container build is the kernel of the build host
and not the one shipped in the image.
That is the reason we drive dkms ourselves rather than letting the scriptlet do
it.
The sources land in `/usr/src/nvidia-${NVIDIA_VERSION}`, verified on the rpm.

Plan A: `dkms add` then `dkms autoinstall --kernelver ${KERNEL_VERSION}`.
Plan B, if `autoinstall` ignores a kernel it is not running on:
`dkms build` and `dkms install` with an explicit `-m nvidia -v -k`.
Also to confirm on the first run:
that dkms installs under `/usr/lib/modules/<kver>/extra`,
where the guard at the end of `build.sh` looks for the module.

Done when: the `find … -name 'nvidia.ko*'` guard passes for the first time.

### N4 — Derive the version assertion from what is installed

Status: done · Effort: `S` · Depends on: `N3`

Closed as superseded rather than implemented in `build.sh`.

The original complaint no longer holds: the version is a constant since `N1`,
so `nvidia-driver` is compared to the pin and not to itself.
What remained — a list of package names
that a new nvidia package could slip past —
is covered by `tests/image-invariants.sh`,
which builds the list from `rpm -qa` and is run by `just verify`,
in CI after the rechunk.

The loop in `build.sh` stays as a fast guard on the three packages that matter,
close to where they are installed.
Note the epoch for whoever touches either check:
`nvidia-kmod-common` carries `3:`,
so `%{VERSION}` is the right field and `%{EVR}` would never match.

Done when: superseded by `N11`.

### N5 — A complete green local build

Status: done · Effort: `S` · Depends on: `N1` to `N4`

The consequence of the previous four: `just build` runs to completion,
`bootc container lint` included.

Done when: a local image exists, `bootc container lint` reports no warning,
and the module answers the pinned version.
Query it by path, not by name: `modinfo nvidia` resolves against `uname -r`,
which inside a container is the kernel of the host and not the one in the image.

## Phase 1 — An image that actually boots

Compiling is not loading.
These checks catch the black screen before it happens.

### N6 — Blacklist nova_core alongside nouveau

Status: todo · Effort: `XS` · Depends on: —

The machine boots today with `rd.driver.blacklist=nouveau,nova_core`
and the matching `modprobe.blacklist`, set locally rather than by the image.
`system_files/usr/lib/bootc/kargs.d/00-nvidia.toml` now carries both names in
both lists, and `tests/image-invariants.sh` fails the build if either is
missing.
What is left is the proof on a real deployment, which belongs to `N15`.

Nothing breaks today.
Fedora 44 builds its kernel with `# CONFIG_NOVA_CORE is not set`,
so the module does not exist and the second name blacklists nothing.
`nova_core` is the Rust NVIDIA driver being written upstream,
and RPMFusion already hardcodes the pair in the `ConditionKernelCommandLine` of
its `nvidia-fallback.service`, which is why its procedure has you append both.

The day Fedora enables the option,
a deployment that only names `nouveau` changes behaviour on its own,
and the symptom lands far from the cause.
One word now, or a black screen later on a build that was green.

Done when: on the deployed image `/proc/cmdline` blacklists both names,
and `lsmod` shows no `nouveau`.

### N7 — Check the built module against the latest nvidia pinned version

Status: done · Effort: `XS` · Depends on: `N5`

The `find` proves a `.ko` was produced, nothing more.
Add `modinfo -F version nvidia` and compare it to the pin:
this is the check that catches the scenario described in
[AGENTS.md](../AGENTS.md), a module built against one version paired with a
userspace from another, the one that compiles cleanly and loads nothing at boot.

What this does not prove is that the module loads.
`modinfo` reads the metadata of the `.ko` file and never inserts it,
and nothing in a container build can do better:
there is no running kernel matching the one shipped in the image.
That proof belongs to `N18`, on the real machine, where `nvidia-smi` answers.

Done when: the build fails if the module and the userspace diverge.

### N8 — Regenerate the initramfs with the nvidia modules

Status: todo · Effort: `S` · Depends on: `N5`

Without it the module only loads after the pivot,
which gives a resolution change and an ugly Plymouth.
A `dracut --force --kver ${KERNEL_VERSION}` at the end of `build.sh`,
with the four modules passed to `--add-drivers`.

Done when: `lsinitrd` lists the four modules on the image.

## Phase 2 — Green CI and published image

The first of the two switch-over conditions.

### N9 — Open the PR for the branch and make build.yml pass

Status: todo · Effort: `S` · Depends on: `N5`

CI builds, rechunks and tags.
On a PR it neither pushes nor signs: this is the first useful green.
It always starts cold, so the buildah cache trap does not apply there.

Done when: the "Build and push image" job is green on the PR.

### N10 — Verify the push and the cosign signature on main

Status: todo · Effort: `S` · Depends on: `N9`

The push, the tag and `cosign sign` only run on the default branch:
they have therefore never been executed for this image.
Confirm that `SIGNING_SECRET` really matches the `cosign.pub` in the repository.

Done when: `cosign verify --key cosign.pub` passes from another machine.

### N11 — A CI job that verifies the image invariants

Status: todo · Effort: `M` · Depends on: `N9`

[AGENTS.md](../AGENTS.md) lists the things that fail silently,
or far away from their cause.
They are all verifiable without a GPU, in a `podman run` on the produced image:
`/opt` is a real directory, the `kargs.d` files carry both blacklists,
the nvidia module is there and at the pinned version,
no nvidia package comes from RPMFusion, no COPR was left enabled.

Done when: deliberately breaking an invariant turns the CI red.

### N12 — Put the driver version under watch

Status: todo · Effort: `M` · Depends on: `N1`

The pin of `N1` is a shell constant, which nothing watches,
and a pin nobody bumps is a pin that rots.
It has to be Renovate, through a `customManager` matching the assignment in
`build.sh` and reading the package index of the NVIDIA repository.
Dependabot cannot do it:
it only understands declared ecosystems such as docker or github-actions,
and has no mechanism for an arbitrary string in a script.
The base image is deliberately not part of this: it is followed by tag,
and `renovate.json5` disables digest pinning for the `Containerfile`.

Done when: a PR opens on its own when NVIDIA publishes a new version.

### N13 — Clean up the metadata inherited from the template

Status: todo · Effort: `XS` · Depends on: —

`image-template.env` still announces `IMAGE_DESC="My Customized Bootc Image"`
and the generic keywords of the ublue template.
This ends up in the OCI labels and on ArtifactHub.

Done when: the image labels describe PoneyhOS.

## Phase 3 — Install, boot, roll back

From the local build to the real machine, with a safety net.

### N14 — First boot in a VM

Status: todo · Effort: `S` · Depends on: `N9`

`just build-iso` then `just run-vm`.
No GPU in there, so nvidia is not validated:
what is validated is that the system boots, that KDE starts,
and above all that we do not land in a dracut emergency shell.

Done when: a graphical session opens in the VM.

### N15 — Verify the kargs on a real deployment

Status: todo · Effort: `XS` · Depends on: `N6`, `N14`

`00-nvidia.toml` is written but has never been applied by bootc.
Four arguments to confirm:
`nouveau` and `nova_core` blacklisted at the initrd and modprobe levels,
then `nvidia-drm.modeset=1` for KMS.
That last one has never been set on the current machine either —
the driver defaults it to `1`, so it is untested rather than known good.

Done when: `/proc/cmdline` carries them all,
and neither `nouveau` nor `nova_core` appears in `lsmod`.

### N16 — Prefill the kickstart

Status: todo · Effort: `S` · Depends on: `N14`

`disk_config/iso.toml` enables the Anaconda modules it needs,
but preconfigures nothing: fr keyboard, Europe/Paris timezone, language,
user account.
Better to write them once than to retype them on every test reinstall.

Done when: the ISO only asks the questions whose answer genuinely depends on the
machine.

### N17 — Write the rollback runbook before needing it

Status: todo · Effort: `S` · Depends on: —

An immutable system is not repaired like a classic one,
and even less so when it boots to a black screen.
Put down in writing the GRUB entry of the previous deployment, `bootc rollback`,
how to reach a console if the driver does not load,
and how to go back to Kinoite for good.
This item is what makes `N18` safe: it comes first.

Done when: the runbook exists and has been followed once for real,
not merely written.

### N18 — Switch over with bootc switch, on the real machine

Status: todo · Effort: `S` · Depends on: `N17`, `N10`

The machine already runs Kinoite, so `bootc switch` is enough: no reinstall.
This is the first contact between the RTX 5080 and a driver
that comes from NVIDIA rather than from RPMFusion,
and the only test that really counts.
Do the rollback once, on purpose, to verify the safety net works.

Done when: `nvidia-smi` answers `615.71.09` on PoneyhOS,
and a rollback round trip has been done.

## Phase 4 — Parity with the current Kinoite

Switching must cost nothing day to day.

### N19 — Inventory what the current Kinoite has on top

Status: todo · Effort: `S` · Depends on: —

The item that feeds all the following ones.
`rpm-ostree status -v`, the list of flatpaks, the AppImages,
whatever lives in a toolbox.
Each entry gets a destination: in the image, flatpak, toolbox, or dropped.
The driver is no longer part of the gap, and neither is CUDA:
`nvidia-driver-cuda` comes with the image,
where the machine layers `xorg-x11-drv-nvidia-cuda` today.

Done when: the list is written, and every line has a destination.

### N20 — zsh actually the default

Status: todo · Effort: `S` · Depends on: `N19`

The package is installed, nothing designates it as the shell.
`/etc` is mutable and persists across deployments, so a `chsh` holds —
but it does not survive a clean reinstall.
Decide between the `useradd` defaults in the image and the kickstart.

Done when: a clean deployment opens a session in zsh.

### N21 — The daily terminal available without layering

Status: todo · Effort: `S` · Depends on: `N19`

Konsole ships with Kinoite.
Ghostty lives in Terra and recommends layering,
exactly what we are trying to avoid: on an image,
it is baked at build time or it becomes a flatpak.
To be decided together with `N19`.

Done when: after a clean deployment,
the daily terminal is there without any post-install command.

### N22 — Settle the Mullvad question

Status: todo · Effort: `S` · Depends on: `N18`

The historical blocker was rpm-ostree layering on the host,
with its conflict over `kernel-core` and the akmods.
In the image, the RPM installs cleanly:
the repository is already added and the `rm /opt && mkdir /opt` exists for that.
The WireGuard route may no longer be necessary.
What remains is the real need: cutting the VPN often and fast,
so no fail-closed kill switch, and a toggle within reach.

Done when: connecting and disconnecting takes one gesture from KDE,
without going through a terminal.

### N23 — Rebuild the dev toolbox on the new system

Status: todo · Effort: `M` · Depends on: `N18`

[AGENTS.md](../AGENTS.md) states that pre-commit lives in a dedicated toolbox,
not on the host.
It must be possible to recreate it with a single command on a fresh system:
pre-commit, gcc, clang, LLVM, headers, `just`.

Done when: one command recreates the toolbox,
and `pre-commit run --all-files` passes inside it.

## Phase 5 — Tooling and documentation

The second switch-over condition.

### N24 — Publish the tooling branch

Status: todo · Effort: not estimated · Depends on: —

The content of the branch is not in the repository yet:
the effort will be sized once it is in front of us.
This is half of a switch-over condition
and the only entry here with nothing behind it —
it deserves a first look early rather than late.

Done when: merged into `main`, with the CI green on it.

### N25 — Give the README back to its reader

Status: todo · Effort: `S` · Depends on: `N18`

The README currently does two jobs: a dated work log, and a user guide.
The log belongs in the PR or in the commit messages,
and it documents the RPMFusion approach we no longer take,
so it is not merely outdated, it is misleading.
What remains: what PoneyhOS is, how to install it, and how to roll back.

Done when: no more "Work in progress" section in the README on `main`.

## Out of scope

These subjects are wanted, but none of them gates the daily switch-over.
They are listed here so that they do not slip into the critical path.

- The display blackout on the current Kinoite.
  No `Xid`, no link training failure,
  nothing in the kernel log over eight boots,
  so the driver is a suspect without evidence.
  `N1` moves the version anyway; if the blackout survives the switch,
  the next place to look is the DP link and the screen itself.
- llama.cpp baked into the image, vLLM in a `uv` venv, LM Studio, CUDA Toolkit
- Ephi Inference integrated into the distro
- Secure Boot and kernel module signing (disabled on the target)
- The vision of an AI-integrated OS,
  which needs a foundation that boots first
