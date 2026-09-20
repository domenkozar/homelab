# Desktop and face recording

The `cherimoya/obs` preset is for the laptop's 2944×1840 display,
integrated colour camera, and digital microphone:

- 1920×1200 at 30 fps, preserving the display's 16:10 aspect ratio.
- Desktop fitted to the canvas, with the pointer visible.
- Camera fitted inside a 384×216 box, 24 pixels from the bottom and right.
- Digital microphone on audio track 1; desktop audio is not included.
- H.264 software encoding, OBS's High Quality preset, AAC audio, MKV files
  saved under `/home/domen/Videos/Recordings`.

The camera uses its stable `/dev/v4l/by-id` path and current capture mode.
The layout preserves its aspect ratio. The microphone uses its explicit
PulseAudio-compatible PipeWire name, avoiding a stale Bluetooth default.

## Install once

OBS is included in `cherimoya/desktop.nix`; it becomes available after the
usual system deployment. Close OBS before copying these files. From the
repository root:

```bash
mkdir -p ~/.config/obs-studio/basic/profiles/DesktopAndFace
mkdir -p ~/.config/obs-studio/basic/scenes ~/Videos/Recordings
cp -n cherimoya/obs/basic.ini ~/.config/obs-studio/basic/profiles/DesktopAndFace/basic.ini
cp -n cherimoya/obs/DesktopAndFace.json ~/.config/obs-studio/basic/scenes/DesktopAndFace.json
```

These commands keep existing files. OBS needs writable copies because it saves
settings and portal restore tokens; do not symlink these files into the Nix store.

Enable **Tools → WebSocket Server Settings → Enable WebSocket server** once,
keeping password authentication enabled. The CLI reads the saved password locally;
credentials and portal restore tokens must not be committed to this repository.

Add this once to `~/.config/niri/config.kdl` to enable the stop shortcut:

```kdl
include "/etc/niri/recording.kdl"
```

## First launch and verification

```bash
obs --collection "Desktop and face" --profile "Desktop and face" --scene "Desktop"
```

Select **eDP-1** in the sharing dialog. If it does not appear, open the Desktop
capture source's properties and choose the screen there. Selection persistence
depends on the portal; a prompt may recur on later launches.

Check that the camera appears in the lower-right corner and the microphone meter
moves. Record 20 seconds, stop, and play back the file to check image, sound, and
smoothness when setting up new hardware.
If the camera is blank, open its properties and select a supported capture mode.

## Delayed recording from the terminal

The `record` command is included alongside OBS in the system configuration.
In the app launcher, choose **Record desktop and face**. The separate **OBS Studio**
entry only opens OBS and does not start recording.
With **Tools → WebSocket Server Settings → Enable WebSocket server** enabled:

```bash
record                 # Five-second desktop countdown, then start
record --delay 10       # Choose a different countdown
record --status
record --stop
```

The countdown appears as a desktop notification and in the terminal. The desktop
notification is updated in place and closed before recording starts.
It never expires during the countdown and does not play notification sounds.
Ctrl-C in the terminal cancels it before recording starts. Use `--delay 0` to
start immediately.
The command reads the local OBS WebSocket port and password from OBS's config,
connects to localhost, and leaves password authentication enabled. If OBS is closed,
`record` launches it minimized with the Desktop and face preset and waits up to
60 seconds for its API to become ready before starting the countdown. The portal
may still ask you to select a screen. If OBS is already open, it uses the currently
selected scene/profile. An existing recording is left running.
`--stop` and `--status` do not launch OBS. Startup output is logged to
`~/.local/state/obs-record-launch.log`.
`record --stop` waits for the file to finish saving, prints its path, and closes
OBS normally to release the camera and microphone. If streaming, virtual camera,
or replay buffer output is active, OBS stays open for that output.

### Stop without opening a window

**Super+S** stops, saves, and closes OBS directly from any application.
It opens no terminal or OBS window and shows no notification.
The binding is installed in `/etc/niri/recording.kdl`, included by the
main niri config. Its repository copy is `cherimoya/obs/recording.kdl`.

For MP4 delivery, use **File → Remux Recordings** in OBS.

## Development checks

Run the CLI's unit tests using Python with `websocket-client` installed:

```bash
python3 -m unittest discover -s cherimoya/obs -p 'test_*.py'
```

The repository's deployment workflow builds with `nix build -L` on `main`.

If software encoding causes excessive CPU use, test VAAPI H.264 hardware encoding
in advanced output settings. The laptop's older OBS log reports VAAPI H.264 support,
but this preset does not assume the current encoder is working.

References: [OBS launch parameters](https://obsproject.com/kb/launch-parameters),
[scene collections](https://obsproject.com/kb/scene-collections),
[profiles](https://obsproject.com/kb/profiles), and
[PipeWire source implementation](https://github.com/obsproject/obs-studio/blob/master/plugins/linux-pipewire/screencast-portal.c).
