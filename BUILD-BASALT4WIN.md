# Building Basalt4Win

Basalt4Win is a fork of [jesdga95/basalt](https://github.com/jesdga95/basalt) that carries two Windows
fixes on top of upstream `v0.4.0-25` (commit `6809edfa`). This file is the whole procedure for a clean
machine: nothing here assumes another Basalt install exists.

* Branch to build: **`patch/win-pin-cap-v4`** (one commit on top of `v0.4.0-patched-base`, which is
  upstream `6809edfa` unchanged). The five-file patch is described in
  [pull request #1](https://github.com/sbsamarski/basalt4win/pull/1).
* `main` tracks upstream and is **not** patched. Do not build `main` expecting the fixes.

## What you need installed

| Component | Used for | What this project was built with |
|---|---|---|
| Git for Windows | clone | any recent version |
| Visual Studio Build Tools with the *Desktop development with C++* workload | `cl.exe`, the MSVC libraries | Build Tools 18, MSVC 14.52.37025 |
| CMake | configure | CMake from `C:\Program Files\CMake` |
| Ninja | build | any `ninja.exe` on `PATH` is fine |
| CUDA Toolkit (nvcc) | the GPU kernels | CUDA 13.4, `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4` |
| Python 3.10 or newer | the `basalt serve` server and `tools/` | 3.14 |
| A Vulkan or CUDA-capable GPU | running anything | RTX 5070 Laptop, 8 GB |

Set the CUDA architecture for your card in the configure line below. `120` is an RTX 50-series
(Blackwell); `86` is RTX 30-series, `89` RTX 40-series. `nvidia-smi --query-gpu=compute_cap --format=csv`
prints yours.

## 1. Clone and build

```bat
git clone -b patch/win-pin-cap-v4 https://github.com/sbsamarski/basalt4win.git Basalt4Win
cd Basalt4Win
build-basalt4win.cmd
```

That script opens the MSVC developer environment and runs the configure and build. If you prefer the
commands, from a *x64 Native Tools Command Prompt*:

```bat
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CUDA_COMPILER="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.4/bin/nvcc.exe" ^
  -DCMAKE_CUDA_ARCHITECTURES=120
cmake --build build -j 12
```

The executables land in `bin\`: `basalt.exe`, `basalt-vision.exe`, `basalt-bench.exe`, `basalt-probe.exe`
and the test tools. A full build takes roughly ten minutes on 24 threads.

`bin\` and `build\` are in `.gitignore`, and GitHub rejects any file over 100 MB, so **the binaries are
never in the repository** - `basalt.exe` is about 150 MB and is produced here, by you, from the source.

## 2. Python environment (needed by `basalt serve`)

```bat
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
```

`basalt serve` starts the Python server in `serve\`; without the environment it cannot start. If you keep
your Python elsewhere, pass it explicitly: `basalt.exe serve --python D:\somewhere\.venv\Scripts\python.exe`.

## 3. FFmpeg (needed only for video input)

Per [docs/platforms.md](docs/platforms.md#ffmpeg-for-video): *"Windows: a shared FFmpeg build
(`avformat-62.dll` for 8, `avformat-63.dll` for 9, and the rest, from gyan.dev or BtbN) beside
`basalt.exe` or in a `PATH` directory; the current directory is never searched."*

Download a shared (not "static") FFmpeg build from <https://www.gyan.dev/ffmpeg/builds/> or
<https://github.com/BtbN/FFmpeg-Builds/releases>, and put these seven DLLs next to `basalt.exe` (or in a
directory on `PATH`):

```
avformat-63.dll  avcodec-63.dll  avutil-61.dll  swscale-10.dll
swresample-7.dll  avdevice-63.dll  avfilter-12.dll
```

The trailing numbers are the library's major version and follow the FFmpeg release: release 9 uses the
numbers above, release 8 uses `avformat-62.dll` and its siblings. Both gyan.dev and BtbN builds include
NVDEC, which is what GPU frame decoding needs; without NVDEC frames decode on the CPU. If you skip this
step the server prints `video off` with the reason and everything else still works.

## 4. Check the patch is in your build

```bat
bin\basalt.exe generate --help | findstr pin-cap-gib
```

You should see the `--pin-cap-gib N` line. A Windows binary that does not show it was built from `main`
rather than `patch/win-pin-cap-v4`.

## 5. Run it, and what the pin cap is for

Windows charges page-locked bytes that the GPU can address against the adapter's shared-memory budget,
which is **half of your physical RAM**. The engine page-locks its whole expert arena, so a pack with a
large routed-expert section exhausts that budget and the first prompt dies with a message that does not
look like a memory problem:

```
prefill gemm: cublasCreate: cuBLAS status 3
```

Set the cap below half your RAM, leaving headroom:

```powershell
$env:BASALT_PIN_CAP_GIB = 55          # or use --pin-cap-gib 55
.\bin\basalt.exe serve --model D:\models\my-model.basalt --port 9931 --resident-experts
```

`--pin-cap-gib N` (or the environment variable, which a launched child inherits) registers and maps only
the first N GiB of the arena; the rest stays ordinary RAM and is served by the CPU expert tier. It
changes no default: `0` means "no cap", which is upstream behaviour.

For the second fix, `BASALT_VISION_THREADS N` bounds the CPU vision encoder's thread count so an image or
video burst cannot occupy every core while a model is loaded.

Your own model configs and launcher scripts are personal and are not in this repository - see
`basalt4win-private` for those, and `tools/win/fetch-personal-config.ps1` to pull them onto a new machine.

## 6. Keeping up with upstream

```bat
git remote add upstream https://github.com/jesdga95/basalt   (first time only)
git fetch upstream --tags
git checkout -b patch/win-pin-cap-vX upstream/vX.Y.Z
git cherry-pick 83d1add4
```

The last command replays the patch commit. Expect a conflict in `src/core/ram_load.cpp` on newer
upstreams, because upstream has moved loading code around; the functions the patch clamps are still there,
and the conflict is in the surrounding code. `tools/win/` and this file are the places to note what you
had to change.
