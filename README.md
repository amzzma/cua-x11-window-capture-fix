# cua-x11-window-capture-fix

English | [中文](README.zh.md)

Unofficial, temporary fix for **Cua Driver** on Linux X11: window screenshots of a
window that is **covered by another window** returned the covering window instead of
the target window's own pixels.

Verified on **KWin 5.27 (X11, gl2 compositing)** against Cua Driver `0.38.0`
(main `7c465d5`) and backported to `cua-driver-rs-v0.37.0`.

> Not affiliated with Cua / trycua. This repository only carries a patch, docs and
> prebuilt release assets; upstream is <https://github.com/trycua/cua>.

## Symptom

With a compositing window manager on X11, calling `get_window_state` (or any
window-screenshot path) on a covered window produced a picture of whatever covered
it. Example: a Konsole window fully hidden behind fullscreen Chrome came back as the
Chrome page.

## Root cause (two stacked bugs)

1. **Wrong drawable**: a window manager reparents the client into a frame window, and
   the compositor redirects that **frame**. Reading the client drawable returns
   undefined pixels for covered regions (on KWin: the screen content). The fix reads
   `XCompositeNameWindowPixmap(frame)` and crops the client rectangle.
2. **InputOnly windows counted as covering popups**: the driver's own
   override-redirect `InputOnly` cursor/input windows have no pixels, but were treated
   as popups covering the target. That diverted `get_window_state` to a full-screen
   crop, so fix 1 could not take effect.

Both fixes are in this repository as patches. The existing
`MIT-SHM → XGetImage → ImageMagick` fallback chain is preserved, so environments
without a compositor keep their previous behavior.

## Compatibility

| Item | Status |
|---|---|
| X11 / XWayland (X11 apps) | ✅ the fix applies |
| Wayland-native clients | ❌ untouched (no XID; out of scope) |
| Compositor required | ✅ only effective when the compositor actually redirects the window |
| No compositor / unredirected window | falls back to previous capture path |
| Tested compositor | KWin 5.27 only; Mutter/wlroots untested |

## Use a release binary (fastest, no toolchain)

Release assets are on the [Releases](../../releases) page. The binary is built for
**linux x86_64** and is **unsigned** — verify `SHA256SUMS` before use and preferably
build from source yourself.

```sh
mkdir -p ~/cua-driver-patched && cd ~/cua-driver-patched
curl -LO https://github.com/amzzma/cua-x11-window-capture-fix/releases/download/v0.1.0/cua-driver-linux-x86_64-0.38.0-patched
chmod +x cua-driver-linux-x86_64-0.38.0-patched
./cua-driver-linux-x86_64-0.38.0-patched --version   # cua-driver 0.38.0
```

Point your MCP client at the patched binary instead of replacing the installed one,
for example in a DSH profile patch:

```yaml
- id: computer-use-cua-driver-mcp
  name: '/path/to/dsh/packages/experimental/computer-use-cua-driver-mcp/lib/index.js'
  config:
    command: /home/<user>/cua-driver-patched/cua-driver-linux-x86_64-0.38.0-patched
    args: [mcp]
```

Then restart your host. Do not overwrite the installed driver directory (upgrades
will replace it).

## Build from source

```sh
git clone --depth 1 --filter=blob:none --sparse https://github.com/trycua/cua.git
cd cua
git sparse-checkout set libs/cua-driver/rust libs/cua libs/images libs/cua-driver/wayland-helper

# main (0.38 baseline)
git apply /path/to/patches/main-combined.diff

# or the 0.37 release tag:
# git checkout cua-driver-rs-v0.37.0
# git apply /path/to/patches/v0.37-combined.diff

cd libs/cua-driver/rust
cargo build --release -p cua-driver --bin cua-driver
# artifact: target/release/cua-driver
```

Prerequisites: Rust (the crate pins `1.97.1` via `rust-toolchain.toml`), `pkg-config`,
X11 headers (`libx11-dev` / `libx11-devel`), and `at-spi2-core` at runtime.

Git users can fetch the two commits from a bundle instead of applying a diff:

```sh
git fetch /path/to/cua-x11-composite-window-capture-main.bundle \
  fix/x11-composite-window-capture:fix/x11-composite-window-capture
```

## Verify

```sh
# hermetic unit tests
cargo test -p platform-linux --lib        # 716 passed, 10 ignored on 0.38 main

# manual check: start a separate daemon socket so the installed driver is untouched
./target/release/cua-driver serve --socket /tmp/cua-test.sock --no-overlay &
./target/release/cua-driver call --socket /tmp/cua-test.sock list_windows
./target/release/cua-driver call --socket /tmp/cua-test.sock get_window_state \
  '{"pid":<pid>,"window_id":<xid>,"include_accessibility_tree":false}' \
  --screenshot-out-file /tmp/window.png
./target/release/cua-driver stop --socket /tmp/cua-test.sock
```

Open `/tmp/window.png`: it should show the target window's own content, even when it
is covered. `evidence/` holds synthetic before/after illustrations.

| Before | After |
| --- | --- |
| ![Before](evidence/before-synthetic.png) | ![After](evidence/after-synthetic.png) |

## Repository layout

| Path | Contents |
|---|---|
| `patches/0001-*.patch`, `patches/0002-*.patch` | the two commits (`git format-patch`), main baseline |
| `patches/main-combined.diff` | combined diff for main `7c465d5` / driver 0.38 |
| `patches/v0.37-combined.diff` | combined backport for `cua-driver-rs-v0.37.0` |
| `evidence/` | synthetic before/after illustrations |
| `scripts/build.sh` | convenience script to clone + apply + build |

## Limitations

- Only effective while the compositor redirects the target window. Fullscreen
  unredirect (some games/video/remote-desktop setups) falls back to old behavior.
- X11 only; Wayland-native capture is not changed.
- Frame decoration is cropped via `translate_coordinates`; verified on KWin 5.27.
- Each capture adds 1–2 X round trips.
- This is a temporary patch, not an upstream API promise. The upstream implementation
  may change; prefer tracking/talking to upstream.

## License

MIT for this repository's contents. The patches apply to
[Cua Driver](https://github.com/trycua/cua) source; keep upstream's licenses intact
when building or redistributing.
