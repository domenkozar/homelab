# USB-C DP Alt Mode: Link training falls back to HBR, causing YUV422 6-bpc green screen

## System Information

| Component | Value |
|-----------|-------|
| **Laptop** | Lenovo Yoga Slim 7 14APU8 |
| **CPU/GPU** | AMD Ryzen 7 7840S / Radeon 780M Graphics (Phoenix, device 1002:15bf) |
| **Kernel** | 6.18.6 |
| **Firmware** | linux-firmware 20260110 (DMCUB downgraded to 20241210 version 0x08004800) |
| **Monitor** | Samsung M7 Smart Monitor (S32BM702) connected via USB-C (DP Alt Mode) |
| **Distro** | NixOS 25.11 |

## Description

When connecting a 4K monitor via USB-C DisplayPort Alt Mode, the display shows a solid green screen. Link training repeatedly fails at HBR2 (5.4 Gbps/lane) and falls back to HBR (2.7 Gbps/lane), which provides insufficient bandwidth for 4K@60Hz RGB. The driver then degrades to YUV422 6-bpc, which the Samsung monitor misinterprets as green.

## Root Cause

Three independent issues contribute to the failure:

1. **DMCUB firmware regression** (fixed) — newer DMCUB firmware (0x08005700) causes AUX channel failures, preventing DPCD and EDID reads. Fixed by downgrading to 20241210 version (0x08004800).

2. **Unreliable LTTPR repeater** (fixed) — the USB-C DP Alt Mode path contains an LTTPR (Link Training Tunable PHY Repeater) with an unreliable AUX channel. Each AUX transaction takes ~2ms through the repeater (32+ slow reads per training attempt = ~64ms overhead). The VBIOS forces LTTPR_MODE_NON_TRANSPARENT (mode 2), routing all traffic through this broken repeater. Fixed by kernel patch that sets `lttpr_mode_override = LTTPR_MODE_NON_LTTPR` for DCN 3.1.4, bypassing the repeater entirely.

3. **Link training rate fallback** (fixed) — even with LTTPR skipped, abbreviated link training can still fail at HBR2 over USB4 tunneling. The driver falls back to HBR (2.7 Gbps/lane), providing only 8.64 Gbps — not enough for 4K@60 RGB 8-bpc (~12 Gbps). Fixed by `amdgpu.forcelongtraining=1` which forces full training patterns (TPS1-TPS4).

All three fixes are required. Testing showed: DMCUB downgrade alone fixes DPCD/EDID reads but not training. LTTPR skip alone improves reliability but still intermittently fails (~1 in 4 plugs). `forcelongtraining` alone still routes through the broken LTTPR. Only the combination of all three produces reliable 4K@60 RGB.

## Symptoms

1. Monitor detected, hotplug works
2. Display shows solid green (no image)
3. Occasionally works on replug, then fails again

## Debug Timeline (captured via `docs/capture-usbc-debug.sh`)

```
[1044.097] link=1 is now Disconnected                     # unplug
[1044.223] link_set_dpms_off SAMSUNG signal=20             # Samsung off

[1048.307] DP Alt mode state on HPD: 1 Link=1             # first hotplug
[1048.344] retrieve_link_cap: MST_Support: no              # DPCD read OK
[1048.352] Rx Caps:                                        # capabilities read
[1048.374] *ERROR* EDID err: 2, on connector: DP-1        # EDID fails first time
[1048.395] *ERROR* No EDID read.
[1048.640] link=1 is now Connected (empty EDID)
[1048.662] link=1 is now Disconnected                      # bounces

[1049.397] DP Alt mode state on HPD: 1 Link=1             # second hotplug
[1049.435] retrieve_link_cap: MST_Support: no              # DPCD read OK
[1049.481] SAMSUNG: [Block 0] [Block 1]                   # EDID succeeds
[1049.482] manufacturer_id=2D4C display_name=SAMSUNG

[1049.483-1049.661] link_encoder enable/disable × 4       # link training attempts (pre-commit)
[1049.691] dc_commit_streams: 2 streams
           pixel_encoding:YUV422, color_depth:6-bpc        # degraded mode committed
[1049.710] link_set_dpms_on SAMSUNG
[1049.715-1051.011] link_encoder enable/disable × 8       # more training attempts (post-commit)
[1051.011] link_encoder_enable (finally sticks)            # trained at HBR (0x0a)
```

**Link settings after training:**
```
Current:  4 lanes  0x0a (HBR=2.7Gbps)    ← trained here (too slow)
Reported: 4 lanes  0x14 (HBR2=5.4Gbps)   ← monitor supports this
```

## Fix Applied

Three workarounds in NixOS config (`cherimoya/default.nix`):

1. **DMCUB firmware downgrade** — replace `dcn_3_1_4_dmcub.bin` with version from linux-firmware 20241210
2. **Kernel patch: skip LTTPR on DCN 3.1.4** — bypasses the unreliable USB-C repeater, avoids slow AUX channel and intermittent training failures
3. **Force full link training** — `amdgpu.forcelongtraining=1` kernel parameter, ensures HBR2 link training succeeds instead of falling back to HBR

## Workarounds Tested

| Workaround | Result |
|------------|--------|
| `amdgpu.dcdebugmask=0x10` | No change |
| Lower resolution (2560x1440) | Works — fits within HBR bandwidth |
| HDMI connection | Works — bypasses USB-C DP Alt path |
| Downgrade DMCUB firmware to 20241210 | Fixes DPCD/EDID reads, but link training still falls back |
| Kernel patch: skip LTTPR on DCN 3.1.4 | Fixes LTTPR issues, still intermittent (~1 in 4) without forcelongtraining |
| `amdgpu.forcelongtraining=1` alone | Improves training but LTTPR still causes failures (~1 in 4) |
| **All three fixes combined** | **Reliable 4K@60 RGB** |
| Force HBR2 via debugfs (`echo "4 0x14"`) | Confirms HBR2 works when forced |

## Related Issues

- **[Issue #3913](https://gitlab.freedesktop.org/drm/amd/-/issues/3913): "DMCUB error" when hotplugging USB-C monitor** — DMCUB firmware bug
- [Bug 201139](https://bugzilla.kernel.org/show_bug.cgi?id=201139): "enabling link 1 failed: 15" (similar link training failure)
- [Issue #2924](https://gitlab.freedesktop.org/drm/amd/-/issues/2924): "DP alt mode displays fail link training if plugged during cold boot"
- [GitHub AOSC #9425](https://github.com/AOSC-Dev/aosc-os-abbs/issues/9425): Fixed by reverting DMCUB firmware

## How to Reproduce

1. Connect Samsung M7 (S32BM702) to Lenovo Yoga Slim 7 14APU8 via USB-C
2. Without the fix, monitor shows green screen
3. Check dmesg for link training failures and `link_settings` for current rate

## Debug Information

Use the capture script for full diagnostics:
```bash
sudo bash docs/capture-usbc-debug.sh
```

## File at

https://gitlab.freedesktop.org/drm/amd/-/issues
