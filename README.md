# PoneyhOS

This repository contains the source code for PoneyhOS.
It is a custom bootc image,
which is my personal Fedora-Kinoite I use as my daily driver.
It is based on the project
[ublue-os/image-template](https://github.com/ublue-os/image-template).

---

## Work in progress ⚙️ — 2026-09-06

Migration of the base image from `ghcr.io/ublue-os/bazzite` to
`quay.io/fedora/fedora-kinoite:44`.
**The image does not build yet.**
Do not expect a working artifact from this branch.

### Verified by a real local build

- Base image `quay.io/fedora/fedora-kinoite:44`, digest-pinned.
  Ships kernel `7.1.13-200.fc44.x86_64`.
- `dnf` is present and is dnf5,
  so there is no need to fall back to `rpm-ostree` in `build.sh`.
- `RUN rm /opt && mkdir /opt` in the
`Containerfile` it is **required**:

  -`mullvad-vpn` installs into `/opt/Mullvad VPN`
  - rpm cannot create it while `/opt` is a symlink
    to the not-yet-existing `/var/opt`.
  - Without it the transaction dies with `cpio: mkdir failed`.
- RPMFusion free + nonfree and the Mullvad repo install correctly;
  `zsh` and `mullvad-vpn` install.
- The NVIDIA version pin works:
  we have every NVIDIA package resolve to `595.58.03`.
  (`akmod-nvidia`, `akmod-nvidia-open`, `xorg-x11-drv-nvidia{,-libs,-power}`,
  `nvidia-modprobe`, `nvidia-settings`).
  This matters because `rpmfusion-nonfree-updates` carries `610.57.04`
  for the proprietary flavour only,
  and a 610 userspace against a 595 module loads nothing at boot.

### Blocker

The akmod `%post` scriptlet compiles the module immediately, via `akmodsbuild`,
which refuses to run as root — the only thing we are inside a container build:

```shell
Building /usr/src/akmods/nvidia-kmod-595.58.03-2.fc44.src.rpm for kernel 7.1.13-200.fc44.x86_64
ERROR: Not to be used as root; start as user or 'akmodsbuild' instead.
[RPM] %post(akmod-nvidia-3:595.58.03-2.fc44.x86_64) scriptlet failed, exit status 1
Transaction failed: Rpm transaction failed.
```

`build.sh` already installs `akmod-nvidia-open` with
`--setopt=tsflags=noscripts` to dodge this, but the fix is incomplete:
**`akmod-nvidia` (proprietary) is pulled in as a dependency of
`xorg-x11-drv-nvidia`**, in the earlier transaction where scriptlets are still
enabled.
Its `%post` fires and fails there.

### Next step to try

Reorder the NVIDIA transactions,
so that no `akmod-*` package is ever installed with scriptlets on:

- `dnf install akmods kernel-devel-${KERNEL_VERSION}` — **normal scriptlets**.
Required: the `akmods` `%post` is what creates the `akmods` user and group,
without which the build cannot run.
- `dnf install --setopt=tsflags=noscripts akmod-nvidia akmod-nvidia-open` —
  both flavours, so the dependency is already satisfied
  by the time userspace is installed.
- `dnf install xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs` —
  scriptlets, so the systemd units for `nvidia-powerd`,
  suspend, hibernate and resume are still wired up.
- `akmods --force --kernels "${KERNEL_VERSION}"` then `depmod`.

Still unverified: whether `akmods --force` itself succeeds as root,
or whether it hits the same `akmodsbuild` refusal.
If it does, the fallback is to invoke `akmodsbuild` directly
as the `akmods` user.
The `find … -name 'nvidia.ko*'` guard proves the module was actually produced.
It has never been reached yet.

### Also not done

- The initramfs is not regenerated with the NVIDIA modules.
  Not fatal, since the module loads from `/usr` afterwards,
  but it may cause a resolution flash or an ugly Plymouth at boot.
- Secure Boot is off on the target machine, so module signing is not set up.
  It would be required before enabling it.

### Local gotcha, not a code issue

After an interrupted build,
the `--mount=type=cache,dst=/var/cache` in the `Containerfile` can end up
holding zero-filled RPMs, producing a misleading `... : not a rpm` on the next
run.
Clear it with `rm -rf /var/tmp/buildah-cache-$(id -u)`.
CI always starts cold and is unaffected.

## How to use the image

### From a bootc system

Run the following command and restart your system:

```bash
sudo bootc switch ghcr.io/Poneyh0/PoneyhOS:latest
```

### From an iso

You can retrieve an iso for installation on a physical machine.
It is available in the build artifacts section.
