#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Third-party repositories

# RPMFusion (free + nonfree). Not present by default on Fedora Atomic images,
# unlike the ublue main images. Required for the nvidia packages below.
# Package list: https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/44/x86_64/repoview/index.html&protocol=https&redirect=1
dnf install --assumeyes \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Mullvad VPN
dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo

### Install packages

# Packages can be installed from any enabled yum repo on the image.
dnf install --assumeyes \
    zsh \
    mullvad-vpn

### NVIDIA — open kernel modules
## Blackwell (RTX 50xx) is only supported by the open kernel modules, so the
## proprietary akmod-nvidia is not an option on this hardware.
##
## RPMFusion ships nvidia-open at 595.58.03 in rpmfusion-nonfree, while the
## proprietary flavour has moved on to 610.57.04 in rpmfusion-nonfree-updates.
## The NVIDIA userspace and the kernel module must be the exact same version,
## so this transaction is resolved against the base repo only — otherwise the
## userspace would silently be pulled at 610 and nothing would load at boot.
NVIDIA_VERSION="595.58.03"
KERNEL_VERSION="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"

dnf install --assumeyes --disablerepo=rpmfusion-nonfree-updates \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-libs

dnf install --assumeyes "kernel-devel-${KERNEL_VERSION}"

## The akmod packages ship a %post that compiles the module immediately. It calls
## akmodsbuild, which refuses to run as root — which is all we are inside a
## container build — so the scriptlet exits 1 and drags the whole rpm transaction
## down with it. Install them without scriptlets and drive the build ourselves.
dnf install --assumeyes --disablerepo=rpmfusion-nonfree-updates \
    --setopt=tsflags=noscripts \
    akmod-nvidia-open

# Every NVIDIA piece must be the exact same version: a 595 module against a 610
# userspace (or the reverse) loads nothing at boot, and the failure would only
# show up on the deployed machine.
for pkg in akmod-nvidia-open xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs; do
    installed="$(rpm -q --queryformat '%{VERSION}' "${pkg}")"
    if [ "${installed}" != "${NVIDIA_VERSION}" ]; then
        echo "NVIDIA version mismatch: ${pkg} is ${installed}, expected ${NVIDIA_VERSION}" >&2
        exit 1
    fi
done

## On an image-based system, modules cannot be built at boot time on the target:
## the deployment is immutable and /usr is read-only. They are compiled here, at
## image build time, against the exact kernel shipped in the base image.
akmods --force --kernels "${KERNEL_VERSION}"
depmod --all "${KERNEL_VERSION}"

# Fail early and loudly if the module did not actually get built, rather than
# shipping an image that boots to a black screen.
find "/usr/lib/modules/${KERNEL_VERSION}/extra" -name 'nvidia.ko*' | grep -q .

# Use a COPR Example:
#
# dnf -y copr enable ublue-os/staging
# dnf -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket
