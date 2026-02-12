# USB-C Monitor Debugging Guide

## Quick Debug Steps

### 1. Run the capture script

```bash
sudo bash docs/capture-usbc-debug.sh
```

This captures firmware info, DMUB traces, DTN state, connector status, link settings, and filtered dmesg in a single run. Output goes to `/tmp/usbc-monitor-debug-<timestamp>/`.

### 2. Manual debugging

```bash
# Enable DRM driver-level debug (0x02 avoids vblank/ioctl flood)
sudo su -c 'echo 0x02 > /sys/module/drm/parameters/debug'

# Stream logs in real-time (important: don't snapshot, stream!)
sudo dmesg -w | tee /tmp/monitor-debug.log

# Plug in USB-C cable, wait for green screen

# Filter key messages
grep -iE "detect_link|retrieve_link|EDID|link_encoder_(enable|disable)|dc_stream_log|dc_commit|link_set_dpms|Validation|ERROR" /tmp/monitor-debug.log
```

## What to Look For

### Link rate fallback (the main issue)

Check link settings after connecting:
```bash
cat /sys/kernel/debug/dri/0/DP-1/link_settings
```

```
Current:  4  0x0a  0     ← HBR2 (5.4 Gbps) = too slow for 4K@60 RGB 10bpc
Reported: 4  0x14  16    ← HBR3 (8.1 Gbps) = what monitor supports
```

Link rate values: `0x06`=RBR (1.62G), `0x0a`=HBR2 (5.4G), `0x14`=HBR3 (8.1G)

### Green screen = link trained too slow

If current link rate < reported, the driver couldn't train at full speed. Repeated `link_encoder_enable`/`link_encoder_disable` cycles in dmesg confirm failed training attempts.

**Fix:** Two kernel patches (see `cherimoya/default.nix`):
1. `amdgpu-dpia-same-rate-retry` — retries DPIA link training up to 3 times at the same rate before falling back (e.g. gives HBR3 multiple chances instead of immediately dropping to HBR2)
2. `amdgpu-dpia-link-training-retry` — retries on post-training link loss and falls back to non-LTTPR mode if the repeater keeps failing

### LTTPR repeater issues

```
is_lttpr_present = 1
lttpr_mode_override chose LTTPR_MODE = 2
REG_WAIT taking a while: 2ms in get_channel_status
```

If you see LTTPR mode 2 (non-transparent) and many slow `REG_WAIT` messages (~32 per training), the AUX channel is routing through the USB-C repeater. Training is intermittent — often succeeds on the second or third attempt.

**Fix:** The `amdgpu-dpia-same-rate-retry` patch retries up to 3 times at the same link rate before falling back, and `amdgpu-dpia-link-training-retry` falls back to non-LTTPR mode if the repeater keeps causing link loss. See `cherimoya/default.nix`.

### EDID read failure

```
*ERROR* EDID err: 2, on connector: DP-1
```

First EDID read often fails on hotplug; driver retries ~1s later and succeeds. Not a problem if second attempt works.

### DMCUB firmware errors

```
dc_dmub_srv_log_diagnostic_data: DMCUB error
```

**Fix:** Downgrade DMCUB firmware to 20241210 version. See `cherimoya/default.nix` for the NixOS override.

Check loaded firmware version:
```bash
cat /sys/kernel/debug/dri/0/amdgpu_firmware_info | grep DMCUB
```
- `0x08004800` = old/working version
- `0x08005700` = broken version

## Force link rate via debugfs (temporary, resets on reboot)

```bash
# Force HBR2 with 4 lanes
sudo sh -c 'echo "4 0x14" > /sys/kernel/debug/dri/0/DP-1/link_settings'
# Then replug USB-C cable

# Reset to default
sudo sh -c 'echo "0 0x0" > /sys/kernel/debug/dri/0/DP-1/link_settings'
```

## Useful Commands

### Check current display config
```bash
wlr-randr
```

### Check amdgpu parameters
```bash
cat /sys/module/amdgpu/parameters/dcdebugmask
cat /sys/module/amdgpu/parameters/dcfeaturemask
cat /sys/module/amdgpu/parameters/forcelongtraining
```

### Check connector status
```bash
cat /sys/class/drm/card1-DP-1/status
cat /sys/class/drm/card1-DP-1/enabled
```

### DTN log (hardware pipe state)
```bash
sudo cat /sys/kernel/debug/dri/0/amdgpu_dm_dtn_log
```

### Force resolution change
```bash
wlr-randr --output DP-1 --mode 2560x1440
wlr-randr --output DP-1 --mode 3840x2160@30
```

## Kernel Parameters Reference

| Parameter | Effect |
|-----------|--------|
| `amdgpu.forcelongtraining=1` | Force full DP link training (TPS1-TPS4) |
| `amdgpu.dcdebugmask=0x10` | Disable PSR |
| `amdgpu.dcdebugmask=0x610` | Disable PSR, PSR-SU, Panel Replay |
| `amdgpu.dcfeaturemask=0x0` | Disable all DC features (including DSC!) |
| `amdgpu.sg_display=0` | Disable scatter/gather display |
| `amdgpu.freesync_video=0` | Disable FreeSync/VRR |
| `amdgpu.noretry=1` | Disable memory access retries |

## Bandwidth Requirements

| Resolution | Refresh | Color | Bandwidth | Fits in HBR? | Fits in HBR2? |
|------------|---------|-------|-----------|---------------|----------------|
| 4K (3840x2160) | 60Hz | RGB 8bpc | ~12 Gbps | No (8.6G) | Yes (17.3G) |
| 4K (3840x2160) | 60Hz | RGB 10bpc | ~15 Gbps | No | Yes |
| 4K (3840x2160) | 60Hz | YUV422 8bpc | ~8 Gbps | Tight | Yes |
| 4K (3840x2160) | 30Hz | RGB 8bpc | ~6 Gbps | Yes | Yes |
| 1440p (2560x1440) | 60Hz | RGB 8bpc | ~5.5 Gbps | Yes | Yes |

HBR = 4 lanes × 2.7 Gbps × 0.8 (8b/10b) = 8.64 Gbps effective
HBR2 = 4 lanes × 5.4 Gbps × 0.8 (8b/10b) = 17.28 Gbps effective

## Approaches Tried (didn't work)

| Approach | Result | Why it failed |
|----------|--------|---------------|
| Skip LTTPR entirely (`lttpr_mode_override = LTTPR_MODE_NON_LTTPR` in DCN 3.1.4 debug defaults) | No green screen, but YUV422 6-bpc | Repeater needs LTTPR training to sustain HBR3; without it link falls back to HBR2, not enough bandwidth for RGB |
| Skip LTTPR + `amdgpu.forcelongtraining=1` | Same as above | Longer training patterns don't help if the repeater isn't being trained at all |
| Skip LTTPR + DPIA post-LT link loss retry | Same as above | Retry logic doesn't help when the root cause is HBR2 bandwidth limit |
| DPIA post-LT link loss retry alone | Green screen intermittently | Only retries on post-training link loss, not on initial CR/EQ failure at HBR3 |
| DPIA same-rate retry (1 attempt) | Green screen less often | 1 retry not always enough — HBR3 sometimes needs 2-3 attempts through the LTTPR repeater |
| DSC (Display Stream Compression) | N/A | Samsung monitor doesn't advertise DSC support over DP |

## Known Issues

### Samsung M7 Smart Monitor (S32BM702)
- Known Linux compatibility issues with USB-C
- Samsung confirmed "compatibility issue with Linux" — no official support
- Workaround: Use HDMI instead of USB-C

### Kernel 6.18.x
- Known amdgpu regressions
- Consider kernel 6.17 if issues persist

## Resources

- [Arch Forums: DMCUB error fix](https://bbs.archlinux.org/viewtopic.php?id=302499)
- [Framework: Kernel 6.18.x amdgpu bugs](https://community.frame.work/t/attn-critical-bugs-in-amdgpu-driver-included-with-kernel-6-18-x-6-19-x/79221)
- [Samsung M7 Linux flickering](https://us.community.samsung.com/t5/Monitors-and-Memory/External-Monitor-Samsung-M7-Flickers-Only-on-Ubuntu-22-04-Works/td-p/3309968)
- [Kernel docs: DC debug masks](https://docs.kernel.org/gpu/amdgpu/display/dc-debug.html)
- [Melissa Wen: 15 Tips for Debugging AMD Display Driver](https://melissawen.github.io/blog/2023/12/13/amd-display-debugging-tips)
