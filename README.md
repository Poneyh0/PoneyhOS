# PoneyhOS

This repository contains the source code for PoneyhOS.
It is a custom bootc image,
which is my personal Fedora-Kinoite I use as my daily driver.
It is based on the project
[ublue-os/image-template](https://github.com/ublue-os/image-template).

---

## How to use the image

> [!IMPORTANT]
> PoneyhOS only supports machines with Secure Boot disabled, for now.
> Its NVIDIA kernel modules are not signed with a key the firmware trusts.
> Under Secure Boot, the kernel refuses to load them.
>
> It also targets the Ada Lovelace and Blackwell generations only,
> meaning the RTX 40 and RTX 50 series.
> The image installs the open kernel modules alone
> and never the proprietary ones,
> so anything older than Turing cannot work at all.
> Turing and Ampere would load the driver, they are simply not tested here.

### From a bootc system

Run the following command and restart your system:

```bash
sudo bootc switch ghcr.io/poneyh0/poneyhos:latest
```

### From an iso

You can retrieve an iso for installation on a physical machine.
It is available in the build artifacts section.

## Repositories

The image ships more than Fedora's own repositories,
and arranges them so that one source cannot quietly replace another.

| Repository | Priority | Note |
| --- | --- | --- |
| NVIDIA CUDA | 10 | wins over everything else for the driver |
| Fedora, RPMFusion | 99 | the default |
| Terra, Claude Desktop | 100 | available, never preferred |

RPMFusion additionally excludes every package whose name contains `nvidia`.
The driver comes from NVIDIA alone,
and the two package the same userspace libraries: a mix resolves cleanly,
then breaks at runtime.

Only the base `terra` repository is enabled.
`terra-source`, and anything else Terra ships beside it, is left disabled.
Enable one by setting `enabled=1` in its file under `/etc/yum.repos.d/`.

> [!NOTE]
> Priorities and exclusions are not written in `/etc/yum.repos.d/*.repo`. dnf5
> keeps them in a separate file,
> `/etc/dnf/repos.override.d/99-config_manager.repo`.
> Reading only the `.repo` files gives the impression that no policy applies.
