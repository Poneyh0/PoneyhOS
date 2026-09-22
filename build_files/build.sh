#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.

# this installs a package from fedora repos
dnf5 install -y tmux zsh

## RPMFusion (free + nonfree), not present by default on Fedora Atomic images.
# Package list: https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/44/x86_64/repoview/index.html&protocol=https&redirect=1
#
# The rpm is downloaded to /tmp rather than handed to dnf as a URL: dnf would
# keep it in the /var/cache cache mount, and the next local build fails on it
# with a misleading `not a rpm`.
for repo in free nonfree; do
	curl --fail --silent --show-error --location \
		--output "/tmp/rpmfusion-${repo}-release.rpm" \
		"https://mirrors.rpmfusion.org/${repo}/fedora/rpmfusion-${repo}-release-$(rpm -E %fedora).noarch.rpm"
done
dnf5 install -y /tmp/rpmfusion-free-release.rpm /tmp/rpmfusion-nonfree-release.rpm

## NVIDIA driver
/ctx/nvidia.sh

## Copr

dnf5 -y copr enable wezfurlong/wezterm-nightly
dnf5 -y install wezterm
dnf5 -y copr disable wezfurlong/wezterm-nightly

dnf5 -y copr enable quadratech188/vicinae
dnf5 -y install vicinae
dnf5 -y copr disable quadratech188/vicinae

#### Example for enabling a System Unit File

systemctl enable podman.socket

### Cleanup

# /run is a tmpfs on the deployed system and /var is not image content on a
# bootc system: what dnf leaves there is flagged by `bootc container lint`.
rm -rf /run/dnf /run/selinux-policy /var/lib/dnf
