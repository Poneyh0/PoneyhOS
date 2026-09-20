# PoneyhOS

This repository build my own custom [bootc](https://github.com/bootc-dev/bootc)
image. It is based on u-blue/Aurora with some custom packages on top of it.

## Community

- [Universal Blue Forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)

## How to Use

From your bootc system, run the following command:

```bash
sudo bootc switch ghcr.io/poneyh0/poneyhos
```

This should queue the image for the next reboot.

## Justfile Documentation

The `Justfile` contains various commands and configurations for building and
managing container images and virtual machine images using Podman and other
utilities. It is also used inside Github Actions.

### Required Utilities

Container build:

- [just](https://just.systems/man/en/introduction.html)
- [podman](https://docs.podman.io/en/latest)
- [jq](https://jqlang.org)

These are usually preinstalled on Universal Blue's Bootc Images.

Linting:

- shfmt
- shellcheck

### Environment Variables

These are all sourced from the `image-template.env` file.

- `image_name`: The name of the image (default: "poneyhos").
- `default_tag`: The default tag for the image (default: "latest").
- `bib_image`: The Bootc Image Builder (BIB) image (default: "quay.io/centos-bootc/bootc-image-builder:latest").

### Building The Image

All these recipes will work (with default values) without supplying any
arguments to them, e.g. `just build`

#### `just build`

Builds a container image using Podman.

```bash
just build $target_image $tag
```

Arguments:

- `$target_image`: The tag you want to apply to the image (default: `$image_name`).
- `$tag`: The tag for the image (default: `$default_tag`).

#### Rechunking

We can flatten the layers of container images to make sure there isn't a
single huge layer when your image gets published.
This does not make your image faster to download, just provides better resumability.

##### `just ostree-rechunk`

Rechunks the existing Image with [rpm-ostree](https://coreos.github.io/rpm-ostree/build-chunked-oci/)

```bash
just ostree-rechunk $target_image $tag
```

##### `just rechunk`

Rechunks the existing Image with [chunkah](https://github.com/coreos/chunkah),
this is probably gonna be the default here at some point, try it out, it's cool.

```bash
just rechunk $target_image $tag
```

#### Switching to the locally built image for testing

The image has to be in the containers-storage owned by root, to be able to
rebase to it, see the `_rootful_load_image` recipe.

`sudo just build` and `sudo just ostree-rechunk` builds directly as root and
allows you to skip the transfer to the root containers-storage.

You can rebase to all the images that are in your containers-storage:

```bash
sudo podman image list --filter=label=containers.bootc=1
```

See [man bootc switch](https://bootc.dev/bootc/man/bootc-switch.8.html) for more info.

```bash
sudo bootc switch --transport containers-storage localhost/myimage:latest
```

and reboot your system!

### Building and Running Virtual Machines and ISOs

The below commands all build QCOW2 images. To produce or use a different type
of image, substitute in the command with that type in the place of `qcow2`.
The available types are `qcow2`, `iso`, and `raw`.

#### `just build-qcow2`

Builds a QCOW2 virtual machine image.

```bash
just build-qcow2 $target_image $tag
```

#### `just rebuild-qcow2`

Rebuilds a QCOW2 virtual machine image.

```bash
just rebuild-vm $target_image $tag
```

#### `just run-vm-qcow2`

Runs a virtual machine from a QCOW2 image.

```bash
just run-vm-qcow2 $target_image $tag
```

#### `just spawn-vm`

Runs a virtual machine using systemd-vmspawn.

```bash
just spawn-vm rebuild="0" type="qcow2" ram="6G"
```

### File Management

#### `just check`

Checks the syntax of all `.just` files and the `Justfile`.

#### `just fix`

Fixes the syntax of all `.just` files and the `Justfile`.

#### `just clean`

Cleans the repository by removing build artifacts.

#### `just lint`

Runs shell check on all Bash scripts.

#### `just format`

Runs shfmt on all Bash scripts.

## Additional resources

For additional driver support, ublue maintains a set of scripts and container
images available at [ublue-akmod](https://github.com/ublue-os/akmods). These
images include the necessary scripts to install multiple kernel drivers within
the container (Nvidia, OpenRazer, Framework...). The documentation provides
guidance on how to properly integrate these drivers into your container image.
