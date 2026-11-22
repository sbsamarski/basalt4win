# Porting the pin-cap / vision-threads patch from Basalt v0.4.0-25-g6809edfa to v0.5.5

Scope: this is a read-only research report. No files under `D:\Sergey\Basalt` were changed. All git
operations below ran in a separate throwaway clone at `D:\Sergey\Development\TMP\basalt-versions`.

## 1. What the local patch does (recap)

Five tracked files, 76 insertions, 2 deletions, against base commit `6809edfa` (`git describe` =
`v0.4.0-25-g6809edfa`):

| File | Role |
|---|---|
| `include/basalt/core/ram_load.hpp` | Declares `pin_cap_bytes()` / `set_pin_cap()` |
| `src/core/ram_load.cpp` | Implements the cap: reads `BASALT_PIN_CAP_GIB` once at load, `set_pin_cap()` overrides it from the CLI, `RamAllocation::allocate()` only takes the host-VMM (page-locked) path when the arena fits under the cap, and `pin_ram(const RamAllocation&...)` registers/maps only the capped prefix of an over-cap arena, logging the split |
| `src/program/cli/arguments.cpp` | Adds the `--pin-cap-gib N` flag, parses it, calls `set_pin_cap()` |
| `src/program/cli/help.cpp` | Adds the `--pin-cap-gib` line to `basalt --help` |
| `serve/engine/vision.py` | Reads `BASALT_VISION_THREADS` and passes `--threads N` to the vision sidecar process if it is a plain positive integer |

The problem it solves: on Windows, page-locked (pinned) host memory that a GPU can map is charged
against that GPU adapter's shared-memory budget, which Windows caps at half of physical RAM. Basalt's
engine page-locks the whole expert arena through host VMM, so a big arena can exceed that budget. The
patch lets the user keep only the first N GiB page-locked (GPU-visible) and leaves the rest as plain,
unregistered RAM that the CPU tier reads.

## 2. What upstream shipped since v0.4.0-25

Release notes (from `https://api.github.com/repos/jesdga95/basalt/releases`), summarized:

### v0.4.1 (2026-11-16)
- Qwen3.8-27B: second-card prompt line / layer split, YaRN past 262,144 tokens, `--kv-resident N`.
- "Flash-Next's RAM plan leaves room for what the engine takes after it again" — a RAM-sizing fix
  (`kPostPlanHostBytes`, restoring a 2 GiB post-plan allowance that 0.3.1 had dropped, issue #339).
  This is about leaving free RAM headroom after sizing the tier, **not** about the GPU-shared-memory
  pinning budget.
- "Engine crashes, Windows memory figures and runtime errors reach the log and the console (#377,
  @giveen)" — a logging/visibility fix, not a budget fix.
- Container cgroup RAM/shared-memory accounting fix. No Windows pin-budget content.

### v0.5.0 (2026-11-19)
- New model: Tencent Hy4-flash (512 routed experts/layer, MLA attention, 1M context).
- New shared-engine memory features: **per-layer expert-tier copies** (`ExpertTierSpec::layer_weights`),
  **bounded lend** (`ExpertTierSpec::lend_segment`, a long prompt borrows only its chunk instead of the
  whole arena), **partial reclaim**. These all govern how much of the **GPU-resident** expert-copy tier
  a model gets and how prompts borrow it — a layer above the RAM-side pinning code the patch touches.
- No mention of host VMM, page-locking, or a Windows shared-memory budget cap.

### v0.5.5 (2026-11-21)
- New model: Thinking Machines Lab's Inkling 2 Mini (looped MoE, 128 routed experts/layer, up to
  1,048,576 tokens). Its memory feature is "experts in RAM when the context needs the room" — again a
  GPU-tier/KV-cache elasticity feature, not a pinning-budget feature.
- Shared engine changes: vision encoder class-token towers, kernel/launch refinements (PDL, FP4 prefill,
  `bf16_rows_dot`, MMQ changes). No pin-budget content.

**Conclusion from the release notes alone: none of the three releases mentions page-locked memory, host
VMM, a GPU shared-memory budget, or anything resembling `--pin-cap-gib`.** The only Windows-memory item in
this window is the #377 logging fix in v0.4.1.

For context, the host-VMM pinning path itself (the thing the patch is capping) was introduced well before
the user's base commit, in v0.4.0's "Fixes and platforms": *"Windows: the expert RAM is backed by a host
VMM allocation where CUDA host registration fails under WDDM (#297) ... by @LesterLyu."* That mechanism is
untouched in 0.4.1/0.5.0/0.5.5.

## 3. Commit-level check against the five patched files

In the clone, `git log --oneline 6809edfa..v0.5.5 -- <path>` for each file:

```
=== include/basalt/core/ram_load.hpp ===
63cb68ad qwen4exp: the RAM copy takes its RAM as the start's pass reads into it and is pinned once read
afcdb9c0 load: one loader for every model; a start plans everything, announces its total once and places it in one pass
867526ce qwen4exp: the RAM plan leaves the host memory the engine takes after it, beside the reserve (#339)

=== src/core/ram_load.cpp ===
afcdb9c0 load: one loader for every model; a start plans everything, announces its total once and places it in one pass

=== src/program/cli/arguments.cpp ===
(no commits — file is byte-identical between 6809edfa and v0.5.5 for this path)

=== src/program/cli/help.cpp ===
55a7ef35 model: --route-tail-skip and --route-prior are flags any MoE model can take
30ad84a8 help: --spec names the DFly2 drafter beside DSpark

=== serve/engine/vision.py ===
85b51d1a serve: remove the vision work folder at shutdown (#439)
```

`git diff --stat 6809edfa..v0.5.5` for the same paths:

```
include/basalt/core/ram_load.hpp | 87 ++++++++--------------------------------
 1 file changed, 16 insertions(+), 71 deletions(-)
src/core/ram_load.cpp | 196 +-------------------------------------------------
 1 file changed, 1 insertion(+), 195 deletions(-)
src/program/cli/arguments.cpp -> (empty diff)
src/program/cli/help.cpp | 21 ++++++++++-----------
 1 file changed, 10 insertions(+), 11 deletions(-)
serve/engine/vision.py | 13 ++++++++++---
 1 file changed, 10 insertions(+), 3 deletions(-)
```

The large deletions in `ram_load.hpp`/`ram_load.cpp` look alarming by line count but are **not** touching
the patch's logic. Commit `afcdb9c0` ("one loader for every model") is a big refactor that moved the
*blob-reading* machinery — `RamRun`, `RamGrid`, `add_ram_blob`, `ram_arena_runs`, `ram_layer_runs`,
`RamLoad`, `RamLoadStats`, `read_ram_runs` — out of `ram_load.hpp`/`.cpp` and into the new
`include/basalt/core/loader.hpp` / `src/core/loader.cpp`. That is a file reorganisation of code the patch
never touches. The functions the patch *does* touch — `RamAllocation::allocate()`, `pin_ram(void*...)`,
`pin_ram(const RamAllocation&...)`, `RamPin`, `host_pin_budget()` — are still in `ram_load.hpp`/`.cpp` in
v0.5.5, and a byte-for-byte diff of just those functions between 6809edfa and v0.5.5 shows **zero
changes**. Confirmed by extracting v0.5.5's `RamAllocation::allocate()` and `pin_ram(const
RamAllocation&...)` from `src/core/ram_load.cpp` and comparing them directly against the base version:
identical text.

`grep -rn "BASALT_PIN_CAP_GIB\|pin-cap-gib\|pin_cap"` across the whole v0.5.5 tree: **zero matches.**
`grep -rln "page-locked\|host VMM\|resident_pin\|resident_headroom"`: matches only pre-existing files
(`ram_load.hpp`, `vmm.hpp`, `host_plan.hpp`, docs, etc.) with no new cap-related code.

## 4. Per-file verdict

| File | Verdict | Detail |
|---|---|---|
| `include/basalt/core/ram_load.hpp` | **Applies with a mechanical offset, no edits needed.** `git apply --check` succeeds; the one hunk lands 69 lines higher than before because the unrelated `RamRun`/`RamLoad` declarations above it were moved to `loader.hpp`. Content is identical. |
| `src/core/ram_load.cpp` | **Applies with small edits.** `git apply --check` fails on this file as a raw patch, for two cosmetic reasons, not a logic conflict: (1) the file's top-of-file comment changed from "the shared RAM expert loader: unbuffered reads on a thread pool, then the pin." to "the RAM tier's memory: allocation, pinning and registration." (upstream renamed the file's purpose after moving the blob-reading code out) — the patch's `#include` hunk anchors on the old comment text; (2) the hunk that inserts the `pin_cap_from_env()` / `g_pin_cap` block anchors its trailing context on `void add_ram_blob(...)`, a function upstream moved to `loader.cpp`. Both fixes are mechanical: re-anchor the include-insertion hunk to the new top-of-file text, and insert the `pin_cap_from_env`/`g_pin_cap`/`pin_cap_bytes`/`set_pin_cap` block directly after `namespace basalt::core {` (confirmed by patch-testing a hand-adjusted copy: once those two anchors are fixed, all five hunks apply, including the two in `RamAllocation::allocate()` and `pin_ram(const RamAllocation&...)`, which land with only a line-number offset since their content is unchanged). |
| `src/program/cli/arguments.cpp` | **Applies unchanged.** The file has zero upstream commits touching it between 6809edfa and v0.5.5; `git apply --check` reports no error for this file at all. |
| `src/program/cli/help.cpp` | **Applies unchanged (1-line offset).** Two unrelated commits (`--route-tail-skip`/`--route-prior`, and a `--spec` help-text tweak) shifted line numbers elsewhere in the file by one line; `git apply` auto-adjusts and succeeds with no manual edit. |
| `serve/engine/vision.py` | **Applies unchanged (1-line offset).** Upstream's only change to this file in the window (#439, removing the vision work folder at shutdown) is elsewhere in the file. The exact line the patch replaces (`args = [cfg["vision_bin"], "--model", cfg["model"]] + (["--gpu"] if cfg.get("gpu") else [])`) is byte-identical in v0.5.5. `git apply --check` succeeds with a 1-line offset. |

## 5. Has upstream fixed the underlying problem?

**No.** Across v0.4.1, v0.5.0 and v0.5.5:
- No release note, commit subject, or source file mentions a Windows GPU shared-memory budget, a pin
  cap, or anything playing the same role as `--pin-cap-gib` / `BASALT_PIN_CAP_GIB`.
- The memory-related changes in this window (`kPostPlanHostBytes`/`plan_reserve` in v0.4.1,
  `ExpertTierSpec::layer_weights` and `lend_segment` in v0.5.0, Inkling 2 Mini's "experts in RAM when the
  context needs the room" in v0.5.5) all govern **how much of the arena is sized or how a GPU-resident
  expert-copy tier is shared across layers/prompts** — a layer above the point where the patch acts. None
  of them change whether the arena is pinned whole through host VMM, which is the actual mechanism that
  trips the Windows shared-memory budget.
- `RamAllocation::allocate()` and `pin_ram(const RamAllocation&...)` — the two functions the patch
  modifies — are textually unchanged between the base commit and v0.5.5.
- The two call sites that route all models' RAM-tier allocation and pinning through these functions,
  `src/core/expert_source.cpp` and `src/core/expert_tier.cpp`, are unchanged choke points; both the old and
  the new models (Hy4-flash, Inkling 2 Mini) go through the same `RamAllocation`/`pin_ram` path, confirmed
  by `grep -rn "\.allocate("` and `grep -rln "pin_ram("` across `src/` and `include/`.

So the patch is still needed, and it still sits on the correct, unmoved choke point for every model
including the two new ones.

## 6. Recommended porting order and risks

Recommended order:
1. `src/program/cli/arguments.cpp` — zero-risk, no upstream change at all; copy the hunk as-is.
2. `src/program/cli/help.cpp` — zero-risk, apply as-is (auto offset).
3. `serve/engine/vision.py` — zero-risk, apply as-is (auto offset); independent of the C++ changes.
4. `include/basalt/core/ram_load.hpp` — low-risk, apply as-is (auto offset).
5. `src/core/ram_load.cpp` — do this last and by hand: apply the include-insertion hunk against the new
   top-of-file comment, insert the `pin_cap_from_env`/`g_pin_cap`/`pin_cap_bytes`/`set_pin_cap` block right
   after `namespace basalt::core {` (instead of before the now-relocated `add_ram_blob`), then let the
   remaining two hunks (inside `RamAllocation::allocate()` and `pin_ram(const RamAllocation&...)`) apply —
   their content is unchanged, only their line numbers moved.

Risks:
- The only real risk is a copy-paste slip when manually re-anchoring the one hunk in `ram_load.cpp`;
  the inserted code itself does not need to change.
- No arena-sizing rule changed in a way that would require moving the cap to a different file or
  function: the single choke point (`RamAllocation::allocate()` / `pin_ram(const RamAllocation&...)`)
  still gates every model's RAM-tier pinning, old and new.
- The two new models (Hy4-flash, Inkling 2 Mini) do not introduce a second, parallel pinning path —
  both still allocate and pin their RAM-tier arenas through the same shared functions, so
  `--pin-cap-gib`/`BASALT_PIN_CAP_GIB` will cover them automatically once ported; no per-model follow-up
  work is needed.
- Recompile and a short functional check (pin a small arena under a tight `--pin-cap-gib`, confirm the
  logged split and that decode still runs) is worth doing after the port, since this is hand-edited C++,
  not a verbatim patch apply.
- Build/runtime testing itself was out of scope for this report (read-only, no GPU work) and should be
  done separately before relying on the ported patch.
