# USB storage did not work on S922X, and why

## The symptom

Plug a USB flash drive into the Powkiddy RGB10 Max 3 Pro on ROCKNIX and nothing
appears. No entry in `/media`, no `sd*` device in `/proc/partitions`, only
`mmcblk` and `zram`. USB itself is fine: keyboard, mouse and a Bluetooth dongle
all work on the same port.

## The cause

In `projects/ROCKNIX/devices/S922X/linux/linux.aarch64.conf`:

```
# CONFIG_SCSI is not set
```

`USB_STORAGE` depends on `SCSI`, so with SCSI off the option is not available at
all and the config carries only the dependency note where the setting would be.
No block device ever appears, so `udevil` and `95-udevil-mount.rules` have
nothing to act on.

S922X was the only platform like this. RK3326, RK3399, RK3566, RK3576, RK3588,
H700, AMD64 and the Qualcomm targets all had `CONFIG_USB_STORAGE=y`, and so did
`projects/Amlogic/linux/linux.aarch64.conf`.

## The fix

Reported on the ROCKNIX Discord in October 2026. porschemad911 confirmed it was
not deliberate, pointed at `make kconfig-menuconfig-S922X` to resolve the
dependencies properly, and opened:

<https://github.com/ROCKNIX/distribution/pull/3564>

One commit, "linux: S922X: enable SCSI and USB_STORAGE", into `next`, tested with
a SanDisk Extreme GO 64 GB on an Odroid Go Ultra, which is the same SoC. Held
until after the November monthly release because of the freeze period.

## Notes for anyone chasing something similar

- Enabling `CONFIG_SCSI` and `CONFIG_USB_STORAGE` is not quite enough on its own.
  `/dev/sd*` also needs SCSI disk support, `CONFIG_BLK_DEV_SD`. Using
  `menuconfig` rather than hand-editing the config is what pulls the dependencies
  in, and a successful test with a real drive is the proof.
- The kernel side is separate from the filesystem side. After this lands, format
  drives as exFAT or FAT32; NTFS is its own question.
- `/proc/partitions` is the quick diagnostic. If no `sd*` device shows up while a
  drive is plugged in, the problem is below the mount layer and no amount of
  udev or `/media` poking will help.
