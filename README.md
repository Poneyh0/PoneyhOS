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

### From a bootc system

Run the following command and restart your system:

```bash
sudo bootc switch ghcr.io/poneyh0/poneyhos:latest
```

### From an iso

You can retrieve an iso for installation on a physical machine.
It is available in the build artifacts section.
