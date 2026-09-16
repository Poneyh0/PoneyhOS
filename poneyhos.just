# Recipes specific to PoneyhOS.
#
# They live here rather than in the Justfile so that merging upstream changes
# from ublue-os/image-template touches one import line instead of a block in the
# middle of a file the template also edits. The template already expects this:
# its `check` and `fix` recipes glob for *.just.

# Verify the invariants of a built image, from inside it
[group('Utility')]
verify $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -eou pipefail
    # The expected driver version is read from build.sh: the pin keeps one home.
    NVIDIA_VERSION=$(sed -n 's/^NVIDIA_VERSION="\(.*\)"$/\1/p' build_files/build.sh)
    if [ -z "${NVIDIA_VERSION}" ]; then
        echo "could not read NVIDIA_VERSION from build_files/build.sh" >&2
        exit 1
    fi
    podman run --rm \
        --env EXPECTED_NVIDIA_VERSION="${NVIDIA_VERSION}" \
        --volume "${PWD}/tests:/tests:z" \
        "${target_image}:${tag}" \
        bash /tests/image-invariants.sh
