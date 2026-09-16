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

## RPMFusion must never provide an nvidia package: the driver comes from NVIDIA's
## own repository further down, and the two package the same userspace libraries.
## Priorities cannot express this. They only arbitrate between repositories that
## offer the same package name, and akmod-nvidia exists in RPMFusion alone, so
## there would be nothing to arbitrate. The exclusion is what makes the separation
## a property of the build rather than an accident of ordering. The loop also
## covers rpmfusion-nonfree-nvidia-driver, shipped disabled by the base image.
for repo in $(dnf repolist --all --quiet | awk '$1 ~ /^rpmfusion/ {print $1}'); do
    dnf config-manager setopt "${repo}.excludepkgs=*nvidia*"
done

# Mullvad VPN
dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo

# Claude Desktop, unofficial packaging
dnf config-manager addrepo \
    --from-repofile=https://pkg.claude-desktop-debian.dev/rpm/claude-desktop-unofficial.repo
dnf config-manager setopt claude-desktop-unofficial.priority=100

### Install packages

# Packages can be installed from any enabled yum repo on the image.
dnf install --assumeyes \
    zsh \
    mullvad-vpn \
    vim \
    dkms \
    gcc-c++ \
    claude-desktop-unofficial

### Terra
## Terra (Fyra Labs) also ships its own builds of packages Fedora already
## provides. Every Terra repository is therefore demoted rather than disabled:
## it stays available for its own tools, here and when layering on the deployed
## machine, but can never replace a Fedora, RPMFusion or NVIDIA package. dnf
## prefers the repository with the lowest priority number whatever the versions,
## and the default is 99.
##
## terra-release is bootstrapped from the repository itself, as upstream
## documents, but not blindly: --nogpgcheck would let a compromised repository
## run arbitrary root scriptlets during the build, and the key that package ships
## cannot authenticate the package carrying it.
##
## The key is fetched, its fingerprint compared to the one pinned below, and only
## then imported. Pinning the fingerprint is what adds trust: the key is served by
## the same host as the packages, so fetching it over TLS proves nothing on its
## own. A repository serving a different key now fails the build.
TERRA_EXPECTED_FINGERPRINT="AE09157A4DE88B497EA1D5D300CDAB43DE226D6F"

curl --fail --silent --show-error --location \
    --output /tmp/terra-key.asc \
    "https://repos.fyralabs.com/terra$(rpm -E %fedora)/key.asc"

## gpg insists on creating its home directory, and /root is a dangling symlink to
## /var/roothome during the build, so it is given a temporary one instead.
## Without this it dies, the fingerprint comes out empty, and the comparison below
## fails on a perfectly good key.
terra_gnupg_home="$(mktemp -d)"
terra_fingerprint="$(GNUPGHOME="${terra_gnupg_home}" \
    gpg --show-keys --with-colons /tmp/terra-key.asc |
    awk -F: '/^fpr:/ { print $10; exit }')"
rm -rf "${terra_gnupg_home}"
if [ "${terra_fingerprint}" != "${TERRA_EXPECTED_FINGERPRINT}" ]; then
    echo "Terra key fingerprint is ${terra_fingerprint}," \
        "expected ${TERRA_EXPECTED_FINGERPRINT}" >&2
    exit 1
fi
rpmkeys --import /tmp/terra-key.asc

## The repository is declared on its own and terra-release is then installed by
## name, so no URL is ever handed to `dnf install`. The bootstrap definition is
## dropped immediately after: left in place it would sit beside the terra.repo
## that terra-release installs, declaring the same packages twice.
## $releasever is left for dnf to expand, not the shell.
# shellcheck disable=SC2016
dnf config-manager addrepo --id=terra-bootstrap \
    --set=baseurl='https://repos.fyralabs.com/terra$releasever' \
    --set=gpgcheck=1
dnf install --assumeyes --repo=terra-bootstrap terra-release
rm -f /etc/yum.repos.d/terra-bootstrap.repo
## Only the base terra repository is enabled. Anything terra-release ships beside
## it, terra-extras and the like, is left in place but disabled: it stays one
## enabled=1 away in /etc/yum.repos.d for whoever wants it, without being part of
## what this image resolves against.
for repo in $(dnf repolist --all --quiet | awk '$1 ~ /^terra/ {print $1}'); do
    dnf config-manager setopt "${repo}.priority=100"
    [ "${repo}" = "terra" ] || dnf config-manager setopt "${repo}.enabled=0"
done
dnf install --assumeyes \
    ghostty \
    vicinae \
    zed

### NVIDIA — upstream repository
## NVIDIA's own Fedora repository ships the open kernel modules and CUDA, and
## tracks upstream more closely than RPMFusion. It must never be combined with
## the RPMFusion nvidia packages: both package the same userspace libraries, and
## mixing them produces a driver that resolves cleanly and breaks at runtime.
dnf config-manager addrepo \
    --from-repofile=https://developer.download.nvidia.com/compute/cuda/repos/fedora44/x86_64/cuda-fedora44.repo
dnf config-manager setopt cuda-fedora44-x86_64.priority=10

## Only the open kernel modules are ever installed. They are the only flavour that
## supports Blackwell, and the proprietary one sits in the same repository under
## kmod-nvidia-latest-dkms, one distracted edit away from being pulled in as a
## dependency. Excluding it makes the choice a property of the build.
dnf config-manager setopt cuda-fedora44-x86_64.excludepkgs='kmod-nvidia-latest-dkms'

## The driver version is pinned rather than taken as whatever is newest that day.
## The repository currently holds 610.43.02, 610.57.04 and 615.71.09: without a pin
## a rebuild changes the driver with no diff to show for it, and the day a display
## bug appears there is nothing to bisect. This is the single place the version is
## written, so a Renovate custom manager can watch this line.
NVIDIA_VERSION="615.71.09"

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
    "nvidia-driver-${NVIDIA_VERSION}" \
    "nvidia-driver-cuda-${NVIDIA_VERSION}"

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
# shipping an image that boots to a black screen. The file existing proves little,
# so its own metadata is read instead: this is the artifact the kernel will load,
# and it carries both the version and the licence. Dual MIT/GPL is what tells the
# open modules apart from the proprietary ones, which do not support this hardware.
# -print -quit rather than a pipe to head: under pipefail, head closing the pipe
# would make find fail with SIGPIPE.
NVIDIA_MODULE="$(find "/usr/lib/modules/${KERNEL_VERSION}/extra" -name 'nvidia.ko*' -print -quit)"
if [ -z "${NVIDIA_MODULE}" ]; then
    echo "NVIDIA module was not built for ${KERNEL_VERSION}" >&2
    exit 1
fi

module_version="$(modinfo -F version "${NVIDIA_MODULE}")"
if [ "${module_version}" != "${NVIDIA_VERSION}" ]; then
    echo "NVIDIA module is ${module_version}, expected ${NVIDIA_VERSION}" >&2
    exit 1
fi

module_license="$(modinfo -F license "${NVIDIA_MODULE}")"
if [ "${module_license}" != "Dual MIT/GPL" ]; then
    echo "NVIDIA module licence is ${module_license}, expected the open modules" >&2
    exit 1
fi

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

# dnf also leaves per-repository `countme` counters and a lock file under
# /var/lib/dnf. /var is not image content on a bootc system, and these are the
# files `bootc container lint` reports as a warning. dnf recreates them on the
# deployed machine whenever it is used.
rm -rf /var/lib/dnf
