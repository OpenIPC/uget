# uget

Minimal HTTP download utility for constrained embedded Linux environments
such as HiSilicon-based IP cameras. Works as a lightweight `curl`/`wget`
replacement when binary size matters.

Two variants are provided:

| Variant | Size | Description |
|---------|------|-------------|
| `uget` | ~4.7 KB | C version — portable, easy to modify |
| `uget-asm` | ~2.6 KB | ARM32 assembly — smallest possible, uses raw syscalls |

Both are functionally identical. The assembly version eliminates CRT startup
overhead and uses Linux syscalls directly, keeping only `gethostbyname` and
`mkstemp` from libc.

Pre-built binaries for all supported platforms are available on the
[Releases](https://github.com/OpenIPC/uget/releases/latest) page.

## Features

- HTTP-only (no HTTPS, no redirects) to keep the binary small
- Download to stdout, just like `curl`
- Download-and-execute mode (`uget run <url>`) for ad-hoc binary deployment
- Companion `bin2sh` tool to transfer binaries over telnet via copy-paste
- Exit codes derived from HTTP status (e.g., 404 -> exit 44)

## Usage

Download a file to stdout:

```sh
uget ifconfig.me
```

Download and run a binary from an S3 bucket:

```sh
uget run openipc.s3-eu-west-1.amazonaws.com/ipc_chip_info
```

## Transferring to device via telnet

The `bin2sh` tool converts a binary into a shell script of `printf` commands
that can be copy-pasted over a telnet session:

```sh
# On your workstation
./bin2sh uget > uget.sh

# Log in to the device via telnet, then paste the contents of uget.sh.
# The binary will be reconstructed in /tmp.

# If the target system does not support printf:
./bin2sh -echo uget > uget.sh
```

## Building from source

Requires a HiSilicon cross-compiler and `upx`. See the
[toolchains](https://github.com/OpenIPC/toolchains) repo for available
cross-compilers.

```sh
# Cross-compile both variants (default: arm-hisiv510-linux-)
make

# Cross-compile with a different toolchain
make CROSS_COMPILE=arm-hisiv500-linux-uclibcgnueabi-

# Build only the C version
make uget

# Build only the assembly version
make uget-asm

# Build bin2sh only (native, no cross-compiler needed)
make bin2sh
```

## Error codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | General error |
| 2 | Socket creation error |
| 3 | DNS resolution error |
| 4 | Connection error |
| 5 | Send error |
| 6 | Invalid command-line options |

HTTP response codes other than 2xx are compressed from three digits to two:
the first and last digit are kept (e.g., `404` -> exit `44`, `502` -> exit `52`).
