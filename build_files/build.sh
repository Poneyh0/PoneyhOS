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

### NVIDIA — upstream repository
## NVIDIA's own Fedora repository ships the open kernel modules and CUDA, and
## tracks upstream more closely than RPMFusion. It must never be combined with
## the RPMFusion nvidia packages: both package the same userspace libraries, and
## mixing them produces a driver that resolves cleanly and breaks at runtime.
dnf config-manager addrepo \
    --from-repofile=https://developer.download.nvidia.com/compute/cuda/repos/fedora44/x86_64/cuda-fedora44.repo

KERNEL_VERSION="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"

dnf install --assumeyes "kernel-devel-${KERNEL_VERSION}"

## kmod-nvidia-open-dkms ships a %post that runs dkms against `uname -r`. Inside
## a container build that is the kernel of the build host, not the one shipped in
## the image — they differ. Skip the scriptlets and drive dkms ourselves.
dnf install --assumeyes \
    nvidia-driver \
    nvidia-driver-cuda
dnf install --assumeyes \
    --setopt=tsflags=noscripts \
    kmod-nvidia-open-dkms

NVIDIA_VERSION="$(rpm -q --queryformat '%{VERSION}' nvidia-driver)"

# Every NVIDIA piece must be the exact same version: a module built against one
# version with a userspace from another loads nothing at boot, and the failure
# would only show up on the deployed machine.
for pkg in nvidia-driver nvidia-driver-cuda kmod-nvidia-open-dkms; do
    installed="$(rpm -q --queryformat '%{VERSION}' "${pkg}")"
    if [ "${installed}" != "${NVIDIA_VERSION}" ]; then
        echo "NVIDIA version mismatch: ${pkg} is ${installed}, expected ${NVIDIA_VERSION}" >&2
        exit 1
    fi
done

## On an image-based system, modules cannot be built at boot time on the target:
## the deployment is immutable and /usr is read-only. They are compiled here, at
## image build time, against the exact kernel shipped in the base image.
## autoinstall builds every registered dkms source, so no module name is hardcoded.
dkms add "/usr/src/nvidia-${NVIDIA_VERSION}"
dkms autoinstall --kernelver "${KERNEL_VERSION}"
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
