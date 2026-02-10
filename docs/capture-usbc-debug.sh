#!/usr/bin/env bash
# Capture amdgpu debug data during USB-C monitor hotplug
# Run as root: sudo bash docs/capture-usbc-debug.sh
set -euo pipefail

OUT="/tmp/usbc-monitor-debug-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo "==> Output directory: $OUT"

# Find the DRI debug directory (card0 or card1)
DRI_DIR=""
for d in /sys/kernel/debug/dri/*; do
    if [ -f "$d/amdgpu_firmware_info" ] 2>/dev/null; then
        DRI_DIR="$d"
        break
    fi
done
if [ -z "$DRI_DIR" ]; then
    echo "ERROR: Could not find amdgpu debugfs directory"
    exit 1
fi
echo "==> Using debugfs: $DRI_DIR"

# --- Phase 1: Baseline state before plug ---
echo ""
echo "=== Phase 1: Capturing baseline state ==="

echo "  Firmware info..."
cat "$DRI_DIR/amdgpu_firmware_info" > "$OUT/01-firmware-info.txt" 2>&1

echo "  DTN log (pre-plug)..."
cat "$DRI_DIR/amdgpu_dm_dtn_log" > "$OUT/02-dtn-pre-plug.txt" 2>&1

echo "  Connector status..."
for conn in /sys/class/drm/card*-DP-*; do
    name=$(basename "$conn")
    echo "--- $name ---" >> "$OUT/03-connectors-pre.txt"
    cat "$conn/status" >> "$OUT/03-connectors-pre.txt" 2>&1
    echo "" >> "$OUT/03-connectors-pre.txt"
done

echo "  amdgpu module params..."
for p in dcdebugmask dcfeaturemask; do
    val=$(cat "/sys/module/amdgpu/parameters/$p" 2>/dev/null || echo "N/A")
    echo "$p = $val" >> "$OUT/04-module-params.txt"
done

echo "  Current dmesg snapshot..."
dmesg > "$OUT/05-dmesg-baseline.txt"

# --- Phase 2: Enable debug tracing ---
echo ""
echo "=== Phase 2: Enabling debug tracing ==="

# Use 0x02 (DRM_UT_DRIVER) only - avoids vblank/ioctl flood from 0x1ff
echo "  DRM debug = 0x02 (driver messages only)..."
echo 0x02 > /sys/module/drm/parameters/debug

echo "  DMUB trace mask = 0xffff..."
echo 0xffff > "$DRI_DIR/amdgpu_dm_dmub_trace_mask" 2>/dev/null || echo "  (dmub_trace_mask not available)"

echo "  DMUB trace events = on..."
echo 1 > "$DRI_DIR/amdgpu_dm_dmcub_trace_event_en" 2>/dev/null || echo "  (dmcub_trace_event_en not available)"

# Clear ring buffer and start streaming dmesg to file in real-time
dmesg -C
dmesg -w > "$OUT/06-dmesg-hotplug.txt" 2>&1 &
DMESG_PID=$!
echo "  dmesg streaming (PID $DMESG_PID)..."

# --- Phase 3: Wait for hotplug ---
echo ""
echo "=== Phase 3: Waiting for USB-C hotplug ==="
echo ""
echo "  >>> UNPLUG THE USB-C CABLE IF CONNECTED <<<"
echo ""
read -r -p "  Press ENTER when cable is unplugged (or was already unplugged)... "
echo ""
echo "  >>> NOW PLUG IN THE USB-C CABLE <<<"
echo "  >>> Wait until you see the green screen (or display output) <<<"
echo ""
read -r -p "  Press ENTER after the monitor shows something (green or working)... "

# --- Phase 4: Stop streaming and capture post-plug state ---
echo ""
echo "=== Phase 4: Capturing post-plug data ==="

# Give a moment for final messages to flush
sleep 2
kill $DMESG_PID 2>/dev/null || true
wait $DMESG_PID 2>/dev/null || true
echo "  dmesg streaming stopped."

echo "  DTN log (post-plug)..."
cat "$DRI_DIR/amdgpu_dm_dtn_log" > "$OUT/07-dtn-post-plug.txt" 2>&1

echo "  DMUB trace buffer..."
cat "$DRI_DIR/amdgpu_dm_dmub_tracebuffer" > "$OUT/08-dmub-tracebuffer.txt" 2>/dev/null || echo "(not available)" > "$OUT/08-dmub-tracebuffer.txt"

echo "  Connector status (post-plug)..."
for conn in /sys/class/drm/card*-DP-*; do
    name=$(basename "$conn")
    echo "--- $name ---" >> "$OUT/09-connectors-post.txt"
    cat "$conn/status" >> "$OUT/09-connectors-post.txt" 2>&1
    echo "" >> "$OUT/09-connectors-post.txt"
done

echo "  Link settings..."
for ls in "$DRI_DIR"/DP-*/link_settings; do
    if [ -f "$ls" ]; then
        name=$(basename "$(dirname "$ls")")
        echo "--- $name ---" >> "$OUT/10-link-settings.txt"
        cat "$ls" >> "$OUT/10-link-settings.txt" 2>&1
        echo "" >> "$OUT/10-link-settings.txt"
    fi
done

# --- Phase 5: Extract key messages ---
echo ""
echo "=== Phase 5: Extracting key messages ==="

grep -iE "aux|dpcd|lttpr|link.train|link.loss|dmcub|dmcu|dpia|bandwidth|validation|yuv|bpc|pixel_encod|hotplug|HPD|hpd_irq|connector.*(connected|disconnected)|link_rate|lane_count|dc_link|signal|retrieve_link|create_validate|dc_stream|perform_link|link_res|ERROR" \
    "$OUT/06-dmesg-hotplug.txt" > "$OUT/11-filtered-hotplug.txt" 2>/dev/null || true

# --- Phase 6: Disable debug tracing ---
echo ""
echo "=== Phase 6: Disabling debug tracing ==="

echo 0 > /sys/module/drm/parameters/debug
echo 0 > "$DRI_DIR/amdgpu_dm_dmcub_trace_event_en" 2>/dev/null || true

# --- Summary ---
echo ""
echo "========================================="
echo "  Capture complete: $OUT"
echo "========================================="
echo ""
echo "Files captured:"
ls -lh "$OUT/"
echo ""

LINES=$(wc -l < "$OUT/06-dmesg-hotplug.txt")
FILTERED=$(wc -l < "$OUT/11-filtered-hotplug.txt" 2>/dev/null || echo 0)
echo "Total dmesg lines captured: $LINES"
echo "Filtered interesting lines:  $FILTERED"
echo ""

if [ "$FILTERED" -gt 0 ]; then
    echo "Filtered hotplug messages:"
    echo "-----------------------------------------"
    head -100 "$OUT/11-filtered-hotplug.txt"
else
    echo "WARNING: No link training / hotplug messages found!"
    echo "Showing last 50 lines of raw dmesg:"
    echo "-----------------------------------------"
    tail -50 "$OUT/06-dmesg-hotplug.txt"
fi
echo ""
echo "To share: tar czf /tmp/usbc-debug.tar.gz -C /tmp $(basename "$OUT")"
