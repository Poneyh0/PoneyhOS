#!/bin/bash

set -ouex pipefail

### NVIDIA driver, open kernel modules built at image build time with akmods
## The deployment is immutable, so the module cannot be built on the target:
## it is compiled here, against the kernel shipped in the image, and the build
## fails if it is not there. Requires the RPMFusion repositories (see build.sh).

KERNEL_VERSION="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"

# kernel-devel is pinned to the image kernel, otherwise dnf takes the newest one.
dnf5 install -y "kernel-devel-${KERNEL_VERSION}" akmods

## RPMFusion picks open or proprietary modules from the build host's lspci,
## and the container sees the host GPU. The open flavour is forced instead:
## it is the only one supporting Blackwell, whatever machine builds the image.
printf '%s\n' '%_with_kmod_nvidia_open 1' >/etc/rpm/macros.nvidia-kmod

## The %post of akmod-nvidia calls akmods-ostree-post, which on an ostree image
## builds the module as root. akmodsbuild refuses to run as root, the scriptlet
## fails and dnf exits 1. It is stubbed for the install only: akmods builds the
## module properly below, as its own unprivileged user.
cp -a /usr/sbin/akmods-ostree-post /tmp/akmods-ostree-post
printf '#!/bin/sh\nexit 0\n' >/usr/sbin/akmods-ostree-post
dnf5 install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
cp -a /tmp/akmods-ostree-post /usr/sbin/akmods-ostree-post

# --kernels: build for the image kernel, not for the build host's `uname -r`.
akmods --force --kernels "${KERNEL_VERSION}" --kmod nvidia

## akmods is not trusted to fail on its own: the modules themselves are checked,
## with the build log printed if they are missing.
NVIDIA_VERSION="$(rpm -q --queryformat '%{VERSION}' akmod-nvidia)"
NVIDIA_MODULE_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra/nvidia"

if ! modinfo "${NVIDIA_MODULE_DIR}"/nvidia{,-drm,-modeset,-uvm}.ko.xz >/dev/null; then
	echo "NVIDIA modules were not built for ${KERNEL_VERSION}" >&2
	cat /var/cache/akmods/nvidia/*"-for-${KERNEL_VERSION}".*log >&2 || true
	exit 1
fi

# Every NVIDIA piece must be the same version: a module built against one
# version with a userspace from another loads nothing at boot.
module_version="$(modinfo -F version "${NVIDIA_MODULE_DIR}/nvidia.ko.xz")"
driver_version="$(rpm -q --queryformat '%{VERSION}' xorg-x11-drv-nvidia)"
if [ "${module_version}" != "${NVIDIA_VERSION}" ] || [ "${driver_version}" != "${NVIDIA_VERSION}" ]; then
	echo "NVIDIA version mismatch: module ${module_version}, driver ${driver_version}," \
		"akmod ${NVIDIA_VERSION}" >&2
	exit 1
fi

# Dual MIT/GPL is what tells the open modules apart from the proprietary ones.
module_license="$(modinfo -F license "${NVIDIA_MODULE_DIR}/nvidia.ko.xz")"
if [ "${module_license}" != "Dual MIT/GPL" ]; then
	echo "NVIDIA module licence is ${module_license}, expected the open modules" >&2
	exit 1
fi

# akmods leaves its lock behind, and /run is a tmpfs on the deployed system.
rm -rf /run/akmods
