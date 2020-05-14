# μget

Simple utility to help CI guys do their job in constrained environments to
download and run binaries in `/tmp`. Size of μget is around 5Kb.

## Features

* Could be used as `curl` or `wget` replacement. In my case it's convenient to
  PUT binary to S3 bucket and then run it on device

* Supports only `HTTP` (we need deal with size), no redirects yet

* No fancy error messages inside binary, returns only exit codes from defined
  preset (see `Error codes` section).

## Usage

* As `curl` replacement: `uget ifconfig.me`

* Ad-hoc utility to download and run binary:

```sh
$ ./uget run openipc.s3-eu-west-1.amazonaws.com/ipc_chip_info
```

## Transferring to device using telnet

```sh
# on your Linux workstation
$ ./bin2sh uget > demo.sh
# login via telnet to embedded device, copy-paste text from demo.sh
# target binary will reside in /tmp
$ ./uget example.com
```

## Error codes

|Error code|Description|
|---|---|
| 0 | everything is ok |
| 1 | general error code |
| 2 | socket creation error |
| 3 | DNS resolution error |
| 4 | connection error |
| 5 | send error |
| 6 | incorrect command line options |

* HTTP response codes other than 2XX are transformed from `XYZ` number to `XZ` exit
  code (so `44` means `404`, or `52` means `502`)
