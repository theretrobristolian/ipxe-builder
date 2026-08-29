# ipxe-builder

Reproducible iPXE boot-file staging and BIOS build tooling.

The project is designed around a simple rule:

- **Use official upstream iPXE release files wherever possible**, especially for UEFI and Secure Boot.
- **Build only the legacy BIOS/non-EFI binary locally** when extra features are needed.

This keeps the trusted Secure Boot path aligned with upstream iPXE while still allowing a customised BIOS build with menu/console support.

## Output

A successful build creates a ready-to-stage TFTP tree under:

```text
output/TFTP/
```

The builder currently targets iPXE 2.0.0 and stages the official `ipxeboot.tar.gz` release contents before replacing only the legacy BIOS `non-efi/ipxe.pxe` with the locally compiled version.

## Quick Start

```bash
git clone https://github.com/theretrobristolian/ipxe-builder.git
cd ipxe-builder
bash build.sh
```

To discard tracked local changes, sync to `origin/main`, and rebuild while keeping the download/build cache:

```bash
bash build.sh --refresh
```

## Build Design

### UEFI / Secure Boot

The builder preserves the official upstream release payloads. These are the preferred files for UEFI and Secure Boot deployments.

Example DHCP/TFTP targets:

```text
BIOS            non-efi/ipxe.pxe
x86 UEFI        i386/ipxe.efi
x64 Secure Boot x86_64-sb/shimx64.efi
```

Additional architectures included by upstream are staged automatically.

### Legacy BIOS

The BIOS image is compiled locally from the matching iPXE source tag. The local build enables the command/console functionality used by the Gattaca iPXE menu while retaining PXE/UNDI compatibility.

The resulting file replaces:

```text
output/TFTP/non-efi/ipxe.pxe
```

## autoexec.ipxe

`autoexec.ipxe` is copied to the root of the staged TFTP tree. Edit the repository copy to chain to your real menu or place your complete menu there.

The supplied starter file simply confirms the boot environment and drops to the iPXE shell until you customise it.

## Repository Layout

```text
.
├── autoexec.ipxe
├── build.sh
├── config/
│   └── local/
│       └── general.h
├── cache/          # generated / ignored
├── output/         # generated / ignored
├── source/         # generated / ignored
└── README.md
```

## Why upstream binaries?

Secure Boot depends on trusted signed binaries. The official iPXE release bundle is therefore treated as authoritative for the signed UEFI paths. Locally compiled binaries are intentionally limited to the legacy BIOS path where code signing is not required.

---

Created by **The Retro Bristolian**  
https://github.com/theretrobristolian/ipxe-builder
