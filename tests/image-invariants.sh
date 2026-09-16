#!/usr/bin/env bash
# Verify the invariants of a built image, from inside it.
#
# Run it through `just verify`, not directly: it expects to be executed in a
# container started from the image under test, and it reads the expected NVIDIA
# version from the environment rather than hardcoding a second copy of the pin.
#
# Every check queries the image instead of reading its configuration files.
# That distinction is not academic: an excludepkgs line looked correct while
# `xorg-x11-drv-nvidia` still resolved from RPMFusion, and only a repoquery
# showed it.
set -euo pipefail

expected_nvidia="${EXPECTED_NVIDIA_VERSION:?expected NVIDIA version not provided}"
failures=0

fail() {
    echo "FAIL  $*" >&2
    failures=$((failures + 1))
}

pass() {
    echo "ok    $*"
}

# /opt must be a real directory. As a symlink to /var/opt, rpm cannot create
# subdirectories in it and packages such as mullvad-vpn fail to install.
if [ -d /opt ] && [ ! -L /opt ]; then
    pass "/opt is a real directory"
else
    fail "/opt is a symlink or missing, mullvad-vpn cannot install into it"
fi

# Kernel arguments are read by bootc from this directory, grubby does not work.
kargs_file=/usr/lib/bootc/kargs.d/00-nvidia.toml
# Both argument names matter and neither substitutes for the other:
# rd.driver.blacklist only covers the initramfs, modprobe.blacklist applies once
# the real root is up. The value is matched, not merely the module name, so that
# an unrelated argument ending on the same word cannot satisfy the check.
for karg in rd.driver.blacklist modprobe.blacklist; do
    for module in nouveau nova-core; do
        if grep -qE "${karg}=[^\"]*\b${module}\b" "${kargs_file}" 2>/dev/null; then
            pass "${karg} blacklists ${module}"
        else
            fail "${karg} does not blacklist ${module} in ${kargs_file}"
        fi
    done
done

# The module is what the kernel actually loads. Its metadata carries both the
# version and the licence, and Dual MIT/GPL is what tells the open modules apart
# from the proprietary ones, which do not support the targeted hardware.
kernel_version="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
module_path="$(find "/usr/lib/modules/${kernel_version}/extra" -name 'nvidia.ko*' -print -quit)"

if [ -z "${module_path}" ]; then
    fail "no nvidia module built for ${kernel_version}"
else
    pass "nvidia module present for ${kernel_version}"

    module_version="$(modinfo -F version "${module_path}")"
    if [ "${module_version}" = "${expected_nvidia}" ]; then
        pass "module version is ${module_version}"
    else
        fail "module version is ${module_version}, expected ${expected_nvidia}"
    fi

    module_license="$(modinfo -F license "${module_path}")"
    if [ "${module_license}" = "Dual MIT/GPL" ]; then
        pass "module licence is ${module_license}, the open flavour"
    else
        fail "module licence is ${module_license}, expected Dual MIT/GPL"
    fi
fi

# Userspace and kernel module are versioned in lockstep. A mix resolves cleanly
# and loads nothing at boot, so the failure would only appear on the machine.
while read -r name version; do
    [ -n "${name}" ] || continue
    # nvidia-driver-selinux is a small policy module packaged beside the driver
    # and versioned on its own, 0.1 at the time of writing. It is not part of the
    # set that has to move in lockstep with the kernel module.
    if [ "${name}" = "nvidia-driver-selinux" ]; then
        continue
    fi
    if [ "${version}" = "${expected_nvidia}" ]; then
        pass "${name} is ${version}"
    else
        fail "${name} is ${version}, expected ${expected_nvidia}"
    fi
done < <(rpm -qa --queryformat '%{NAME} %{VERSION}\n' 'nvidia-driver*' 'kmod-nvidia*' 'nvidia-kmod-common')

# RPMFusion must not be able to provide any nvidia package at all. The driver
# comes from NVIDIA alone, and both package the same userspace libraries.
# No `|| true` and no redirection: repoquery exits 0 whether it matches or not,
# and non-zero only when it cannot run. Swallowing that would turn a broken query
# into a silent pass, which is the failure mode this whole script exists to avoid.
rpmfusion_nvidia="$(dnf repoquery --quiet --disablerepo='*' --enablerepo='rpmfusion*' '*nvidia*')"
if [ -z "${rpmfusion_nvidia}" ]; then
    pass "RPMFusion provides no nvidia package"
else
    fail "RPMFusion still provides: $(echo "${rpmfusion_nvidia}" | tr '\n' ' ')"
fi

# The proprietary kernel module lives in the same repository as the open one.
proprietary="$(dnf repoquery --quiet --repo=cuda-fedora44-x86_64 'kmod-nvidia-latest-dkms')"
if [ -z "${proprietary}" ]; then
    pass "the proprietary kernel module is not reachable"
else
    fail "kmod-nvidia-latest-dkms is reachable: ${proprietary}"
fi

# Only the base terra repository is enabled, the rest stays one enabled=1 away.
enabled_repos="$(dnf repolist --quiet | awk 'NR > 1 {print $1}')"
if grep -qx 'terra' <<<"${enabled_repos}"; then
    pass "terra is enabled"
else
    fail "terra is not enabled"
fi
if grep -qx 'terra-source' <<<"${enabled_repos}"; then
    fail "terra-source is enabled, it should ship disabled"
else
    pass "terra-source is disabled"
fi

# Priority is what stops Terra replacing a Fedora, RPMFusion or NVIDIA package.
# dnf prefers the repository with the lowest priority number whatever the
# versions: measured on this image, matugen resolves to fedora 3.1.0 at priority
# 99 even though terra offers 4.2.0 at priority 100. Enabled is not enough, the
# number is the containment, so it is asserted rather than assumed.
repo_priority() {
    dnf repoinfo --quiet "$1" 2>/dev/null |
        awk -F: '/^ *Priority/ { gsub(/ /, "", $2); print $2; exit }'
}

terra_priority="$(repo_priority terra)"
if [ "${terra_priority}" = "100" ]; then
    pass "terra is demoted to priority ${terra_priority}"
else
    fail "terra priority is '${terra_priority}', expected 100"
fi

nvidia_priority="$(repo_priority cuda-fedora44-x86_64)"
if [ "${nvidia_priority}" = "10" ]; then
    pass "the NVIDIA repository leads at priority ${nvidia_priority}"
else
    fail "NVIDIA repository priority is '${nvidia_priority}', expected 10"
fi

# A COPR left enabled would silently feed later installs on the machine.
if grep -qi 'copr' <<<"${enabled_repos}"; then
    fail "a COPR is still enabled: $(grep -i copr <<<"${enabled_repos}" | tr '\n' ' ')"
else
    pass "no COPR is enabled"
fi

echo
if [ "${failures}" -eq 0 ]; then
    echo "All invariants hold."
else
    echo "${failures} invariant(s) broken." >&2
    exit 1
fi
