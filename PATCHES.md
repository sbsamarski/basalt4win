# Patch branches, per Basalt version

One branch per upstream version, each holding exactly one patch commit on top of that version's own tag.
Build the branch that matches the upstream version you want; never build `main` expecting the fixes.

| Branch | Upstream it sits on | Patch commit | Build tested | Status |
|---|---|---|---|---|
| `patch/win-pin-cap-v4` (alias `patch/v0.4.0`) | `v0.4.0-25-g6809edfa` | `83d1add4` | yes, built and compared against a working install | in daily use |
| `patch/v0.5.5` | `v0.5.5` | not created yet | no | planned, see [PATCH-PORT-v0.5.5.md](PATCH-PORT-v0.5.5.md) |

To add a future version:

```bat
git fetch upstream --tags
git checkout -b patch/v0.6.0 upstream/v0.6.0
git cherry-pick 83d1add4
```

Fix the conflicts, build it, and add a row here. Expect `src/core/ram_load.cpp` to conflict, because
upstream moved the loading code into `loader.cpp` after v0.4.0.

## Flags each version needs

The patch adds two knobs, and both are the same on every patched version:

| knob | what it does |
|---|---|
| `--pin-cap-gib N` | the most GiB of the resident expert arena the GPU is given access to. `0` (default) = pin the whole arena, which is upstream behaviour |
| `BASALT_PIN_CAP_GIB=N` | the same number as an environment variable, for a launched child that inherits it |
| `BASALT_VISION_THREADS=N` | bounds the CPU vision encoder's threads (only matters with `--vision cpu`) |

Choose `N` from half of physical RAM minus headroom, not from the VRAM size.

### Reference run lines

Qwen3.8-Flash-Next NVFP4 pack (63.28 GiB of routed experts) on 128 GiB RAM / 8 GiB VRAM - this is the
line in daily use, and its pin cap is **55 GiB**:

```powershell
$env:BASALT_PIN_CAP_GIB = 55
D:\Sergey\Basalt4Win\bin\basalt.exe serve --model <pack>.basalt --host 127.0.0.1 --port 9931 `
  --alias qwen3.8-flash-next --kv int8 --kv-resident 20480 --prompt-cache 6 --vram-reserve-mib 256 `
  --resident-experts --vision off --max-context 360448 --rope-scaling yarn --rope-scale 1.375 `
  --yarn-orig-ctx 262144 --ram-reserve-mib 2048 --fit-max-tokens --conversation-cache-mib 10240 `
  --conversation-cache-slots 2 --pool-workers 20 --prefill-cpu-share 0.9 --expert-cache 60 --spec 7
```

For the **UD-Q4_K_XL** packs use the same line with **`$env:BASALT_PIN_CAP_GIB = 50`**; their expert
section is a different size, and 55 left too little of the adapter's half-of-RAM allowance free.

Everything about model quality, expert placement and the on-card expert cache is unchanged by the patch.
