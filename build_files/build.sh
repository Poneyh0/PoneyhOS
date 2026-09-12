#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Third-party repositories

# RPMFusion (free + nonfree). Not present by default on Fedora Atomic images,
# unlike the ublue main images. Required for the nvidia packages below.
# Package list: https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/44/x86_64/repoview/index.html&protocol=https&redirect=1
#
# Download to /tmp (a tmpfs during the build) and install from the local path.
# Given a URL, dnf keeps the rpm under /var/cache/libdnf5/@commandline-*, which is
# a persistent cache mount: the next local build finds a zero-filled copy there,
# appends the new download to it, and fails with a misleading `not a rpm`.
for repo in free nonfree; do
    curl --fail --silent --show-error --location \
        --output "/tmp/rpmfusion-${repo}-release.rpm" \
        "https://mirrors.rpmfusion.org/${repo}/fedora/rpmfusion-${repo}-release-$(rpm -E %fedora).noarch.rpm"
done
dnf install --assumeyes \
    /tmp/rpmfusion-free-release.rpm \
    /tmp/rpmfusion-nonfree-release.rpm

# Mullvad VPN
dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo

### Install packages

# Packages can be installed from any enabled yum repo on the image.
dnf install --assumeyes \
    zsh \
    mullvad-vpn \
    vim \
    dkms \
    gcc-c++

### NVIDIA — upstream repository
## NVIDIA's own Fedora repository ships the open kernel modules and CUDA, and
## tracks upstream more closely than RPMFusion. It must never be combined with
## the RPMFusion nvidia packages: both package the same userspace libraries, and
## mixing them produces a driver that resolves cleanly and breaks at runtime.
dnf config-manager addrepo \
    --from-repofile=https://developer.download.nvidia.com/compute/cuda/repos/fedora44/x86_64/cuda-fedora44.repo

KERNEL_VERSION="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"

dnf install --assumeyes "kernel-devel-${KERNEL_VERSION}"

## nvidia-driver requires nvidia-kmod-common, which requires kmod-nvidia-open-dkms,
## so the module sources come in with the driver and their scriptlets cannot be
## skipped separately. The %post of kmod-nvidia-open-dkms registers the sources
## with dkms, then builds against `uname -r`: inside a container build that is the
## kernel of the build host, not the one shipped in the image. Its failures are
## silenced with `|| :`, so the module is built explicitly further down.
##
## Fedora's dkms runs `dracut --regenerate-all --force` after every install. In the
## image that writes a 245 MB initramfs to /boot, which bootc ignores and lints
## against; bootc boots /usr/lib/modules/<kver>/initramfs.img instead. The NVIDIA
## packages omit their modules from the initramfs anyway (99-nvidia.conf). Disable
## the hook before the %post above can trigger it, and drop the override afterwards.
mkdir -p /etc/dkms/framework.conf.d
echo 'post_transaction=""' >/etc/dkms/framework.conf.d/99-build-no-initramfs.conf
dnf install --assumeyes \
    nvidia-driver \
    nvidia-driver-cuda

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
## The sources are already registered by the %post above. --force covers a build
## host running the image kernel, where that %post build has already succeeded.
dkms build --force -m nvidia -v "${NVIDIA_VERSION}" -k "${KERNEL_VERSION}"
dkms install --force -m nvidia -v "${NVIDIA_VERSION}" -k "${KERNEL_VERSION}"
depmod --all "${KERNEL_VERSION}"

# Fail early and loudly if the module did not actually get built, rather than
# shipping an image that boots to a black screen.
find "/usr/lib/modules/${KERNEL_VERSION}/extra" -name 'nvidia.ko*' | grep -q .

# dkms keeps its own state under /var/lib/dkms: build logs, copies of the modules,
# and a self-signed MOK key pair generated on the fly to sign them. None of it is
# used at runtime, bootc never updates /var after the first deployment, and the
# private key must not ship in a public image. The image targets Secure Boot
# disabled machines, so the signature itself is irrelevant.
rm -rf /var/lib/dkms
rm /etc/dkms/framework.conf.d/99-build-no-initramfs.conf

# Use a COPR Example:
#
# dnf -y copr enable ublue-os/staging
# dnf -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket

### Cleanup

# /run is a tmpfs on the deployed system, so anything written there during the
# build is dead weight that `bootc container lint` flags. dnf and the scriptlets
# of selinux-policy leave their scratch files behind.
rm -rf /run/dnf /run/selinux-policy
