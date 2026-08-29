# ipxe-builder

Reproducible iPXE boot-file staging and legacy BIOS build tooling.

The project follows one simple rule:

- **Use official upstream iPXE release files wherever possible**, especially for UEFI and Secure Boot.
- **Build only the legacy BIOS/non-EFI image locally** when extra console and framebuffer features are needed.

This keeps the UEFI/Secure Boot path aligned with the signed upstream release while still providing a customised BIOS loader with graphical console support.

The builder currently targets **iPXE 2.0.0**.

## What the builder produces

A successful build creates a ready-to-stage TFTP tree under:

```text
output/TFTP/
```

The builder downloads the official iPXE `ipxeboot.tar.gz` release bundle and extracts it into that directory. It then replaces only:

```text
output/TFTP/non-efi/ipxe.pxe
```

with a locally compiled `undionly.kpxe`-based BIOS image.

Everything else in the staged tree remains the official upstream iPXE 2.0.0 release content.

## Quick start

```bash
git clone https://github.com/theretrobristolian/ipxe-builder.git
cd ipxe-builder
bash build.sh
```

To update the repository from `origin/main` and rebuild while retaining the local download/build cache:

```bash
bash build.sh --refresh
```

On Debian/Ubuntu systems the builder will install the required compiler/build dependencies automatically if they are missing.

## Recommended deployment

The simplest deployment model is to copy the contents of:

```text
output/TFTP/
```

into the root of your TFTP server.

The resulting tree contains the official upstream architecture folders and Secure Boot payloads, plus the customised legacy BIOS loader.

Example boot targets include:

```text
Legacy BIOS       non-efi/ipxe.pxe
32-bit x86 UEFI   i386/ipxe.efi
x86-64 UEFI       x86_64/ipxe.efi
x86-64 Secure Boot x86_64-sb/shimx64.efi
AArch64 UEFI      arm64/ipxe.efi
AArch64 Secure Boot arm64-sb/shimaa64.efi
```

Use the filename appropriate to the client architecture in DHCP/PXE configuration.

> Secure Boot files are not rebuilt or re-signed by this project. They come directly from the official iPXE release bundle.

## Legacy BIOS design

The legacy BIOS image is compiled from the matching upstream iPXE source tag as:

```text
bin/undionly.kpxe
```

and published as:

```text
non-efi/ipxe.pxe
```

The rename allows existing DHCP environments that already reference `non-efi/ipxe.pxe` to continue working unchanged.

The local BIOS build enables:

- iPXE console commands
- framebuffer console support
- PNG image support
- HTTPS downloads
- useful diagnostic commands such as `ping`, `nslookup`, `ntp`, `reboot` and `poweroff`

The BIOS build uses the firmware PXE/UNDI networking stack rather than compiling the much larger all-driver `bin/ipxe.pxe` image.

## Portable embedded bootstrap

The customised BIOS image contains a deliberately tiny embedded script from:

```text
embed.ipxe
```

The embedded script does **not** contain a hard-coded TFTP server address.

Instead it obtains the TFTP server from DHCP using iPXE's `${next-server}` setting and then looks for an editable `autoexec.ipxe` script.

The lookup order deliberately mirrors the useful behaviour of the iPXE 2.0.0 release:

```text
1. tftp://${next-server}/non-efi/autoexec.ipxe
2. tftp://${next-server}/autoexec.ipxe
```

So a deployment can either keep a BIOS-specific script alongside the BIOS loader:

```text
TFTP/
└── non-efi/
    ├── ipxe.pxe
    └── autoexec.ipxe
```

or use one shared script from the TFTP root:

```text
TFTP/
├── autoexec.ipxe
└── non-efi/
    └── ipxe.pxe
```

The second layout is particularly convenient because the same root `autoexec.ipxe` can be used as the common entry point for multiple architectures.

If the TFTP server address changes, update DHCP's `next-server`; the BIOS image does not need to be rebuilt.

## Why embed only the bootstrap?

Embedding the complete boot menu would make every menu change require a new iPXE binary.

Instead this project embeds only enough logic to find the external `autoexec.ipxe` reliably. The normal boot menu remains an ordinary editable script on the TFTP server.

The resulting BIOS flow is:

```text
PXE firmware
    ↓
non-efi/ipxe.pxe
    ↓
embedded embed.ipxe
    ↓
DHCP / ${next-server}
    ↓
local autoexec.ipxe, then root autoexec.ipxe
    ↓
your normal iPXE menu / boot scripts
```

This also avoids a common chainloading loop where a newly started iPXE client receives the same `non-efi/ipxe.pxe` DHCP filename again and simply reloads itself.

## UEFI and Secure Boot

UEFI and Secure Boot files are intentionally left untouched.

The official iPXE 2.0.0 release introduced dedicated Secure Boot support and automatically downloads and boots `autoexec.ipxe` when one is available. The upstream release bundle is therefore treated as authoritative for these architectures.

In practical terms, the project is designed so that the complete generated TFTP tree can be staged together:

```text
output/TFTP/
├── arm32/
├── arm64/
├── arm64-sb/
├── i386/
├── loong64/
├── non-efi/       # official tree, with ipxe.pxe replaced by our BIOS build
├── riscv32/
├── riscv64/
├── x86_64/
├── x86_64-sb/
├── autoexec.ipxe
└── ...other upstream files
```

Exactly which UEFI/Secure Boot filename should be handed out by DHCP depends on the architecture and firmware mode of the client.

Secure Boot also depends on the target firmware trusting the signing chain used by the upstream iPXE release. Hardware/firmware-specific Secure Boot limitations are therefore outside the scope of this builder.

## autoexec.ipxe

`autoexec.ipxe` is the editable entry point for the environment.

The repository includes a simple starter file. Replace it with your own menu or have it chain to a larger menu hosted over TFTP, HTTP or HTTPS.

Because the BIOS binary contains only the bootstrap, normal changes to `autoexec.ipxe` do **not** require recompiling iPXE.

## Repository layout

```text
.
├── autoexec.ipxe
├── embed.ipxe
├── build.sh
├── config/
│   └── local/
│       ├── console.h
│       └── general.h
├── cache/          # generated / ignored
├── output/         # generated / ignored
├── source/         # generated / ignored
└── README.md
```

## Why upstream binaries?

Secure Boot depends on trusted signed binaries. The official iPXE release bundle is therefore treated as authoritative for the signed UEFI paths.

Locally compiled binaries are intentionally limited to the legacy BIOS path where code signing is not required.

This gives the project a useful balance:

```text
Legacy BIOS  → customised where useful
UEFI         → official upstream binaries
Secure Boot  → official signed upstream binaries
Boot menu    → external and easily editable
```

## Upstream

This project builds on the excellent work of the iPXE project:

- https://ipxe.org/
- https://github.com/ipxe/ipxe

The official iPXE 2.0.0 network boot bundle used by the builder is published by the upstream project as `ipxeboot.tar.gz`.

---

Created by **The Retro Bristolian**  
https://github.com/theretrobristolian/ipxe-builder
