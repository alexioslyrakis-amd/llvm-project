# LLVM contribution recovery notes

Saved on 2026-10-13, before reformatting the development laptop.

Repository: <https://github.com/alexioslyrakis-amd/llvm-project>

The PR account has no push permission on `llvm/llvm-project`. These branches
live in the author's fork. No new pull requests were opened for this archive.

## Branches

| Branch | Contents | State |
| --- | --- | --- |
| `alyr/remat-invariant-lds-loads` | Invariant LDS rematerialization, including the paired-read pseudo and tests | Prototype; split the basic support and paired-read extension before upstream review |
| `alyr/waitcnt-invariant-lds-dma` | Avoid waiting for LDS DMA before an invariant LDS read | Prototype; synchronization assumptions need review |
| `alyr/sched-barrier-code-motion` | Make `sched_barrier(0)` block IR Sink and MachineSink | Experiment; disabled by default because of a spill regression |
| `alyr/fmha-llvm-experiments-backup` | Exact original combined FlyDSL experiment | Historical backup; includes superseded approaches |
| `alyr/llvm-contribution-notes` | This document, source patches, review snapshot and archive manifest | Recovery reference |
| `alyr/cvt-pk-fp8-dead-old` | Current FP8/BF8 PR branch | PR #231556; review changes deferred |
| `alyr/cvt-pk-fp8-instcombine-backup` | Original IR implementation and all six commits before squashing | Historical backup |
| `alyr/cvt-pk-fp8-sifold-backup` | Machine instruction implementation reviewed by Matt | Historical backup |

The first three branches are independent, one-commit patches on the original
upstream base `e2a39f504fee`. They have not been rebased onto current main.
The remat and waitcnt changes match their saved source patches byte for byte.
The scheduler changes were isolated from the combined experiment. Their two
`SIInstrInfo.cpp` additions were copied verbatim; all other scheduler files
match the original experiment exactly.

Full commit IDs, trees, file lists and archive verification are in
[manifest.json](archive/manifest.json). The original commits are also saved as
mailbox patches under [archive](archive), including their original descriptions.

## 1. Invariant LDS rematerialization

When an invariant LDS-loaded value is live across high register pressure, the
allocator may spill it to scratch. The prototype lets it issue another LDS read
at the use instead. The source commit is `626c7b2501f5`.

The prototype has three parts:

- `SIInstrInfo.cpp` allows plain invariant LDS reads to be rematerialized. It
  rejects volatile/ordered accesses, stores, GDS and instructions reading M0.
  It also adjusts handling of the implicit EXEC operand.
- `SIFormInvariantLDSReadPairs` combines two suitable `ds_read_b128` definitions
  and their 256-bit `REG_SEQUENCE` into `DS_READ_B256_INVARIANT_PSEUDO`. This
  gives the allocator one definition it can rematerialize for a wide MFMA input.
- After register allocation, the pseudo expands back to two `ds_read_b128`
  instructions. Expansion preserves the address if its physical register
  overlaps the low half of the destination.

The recorded gfx950 FP8 FMHA hd256 experiment reduced scratch usage from 44 to
12 bytes and ran approximately 8% faster. This is a historical result from the
source commit description, not a new measurement or an isolated measurement of
the basic remat part.

Controls:

- `-amdgpu-remat-invariant-lds-loads=false`
- `-amdgpu-form-invariant-lds-read-pairs=false`

Tests included in the branch:

- `llvm/test/CodeGen/AMDGPU/form-invariant-lds-read-pairs.mir`
- `llvm/test/CodeGen/AMDGPU/expand-ds-read-b256-invariant-pseudo.mir`
- Pipeline checks in `llvm/test/CodeGen/AMDGPU/llc-pipeline.ll`

Before submission: split basic rematerialization from the read-pair extension,
revisit EXEC/liveness correctness and profitability, add direct remat coverage,
and support the new pass manager. The prototype registers the new pass only in
the legacy pipeline.

The kernel experiment marked reads invariant only for the varlen Q tile, whose
LDS region was written once and then kept unchanged. The dense path rewrites
that region and retained its original loads. Do not mark a reused tile buffer
invariant just to enable this optimization.

## 2. Invariant LDS reads and DMA waits

`SIInsertWaitcnts.cpp` can wait for all in-flight global-to-LDS DMA before an LDS
read when alias information is unavailable, including `inttoptr` addressing.
The prototype skips this wait for an invariant load. Source: `e95f5833b057`.

The recorded gfx950 FP8 FMHA result was approximately 4% faster, with an
`s_waitcnt vmcnt(0)` for the next tile's DMA removed from each loop iteration.
This is a historical prototype result; do not add it to the remat percentage.

- Disable with `-amdgpu-waitcnt-invariant-lds-skip-dma=false`.
- Test: `llvm/test/CodeGen/AMDGPU/lds-dma-waitcnt-invariant-load.ll`.
- Before submission, establish when `!invariant.load` is sufficient to remove
  synchronization, including initialization, memory lifetimes, aliasing and
  ordered accesses. The prototype's invariant check is not a completed
  correctness argument.

## 3. Scheduling barriers and code motion

Source: the scheduling changes in combined experiment `9f10b1e85ac0`.

`sched_barrier(0)` constrains machine scheduling, but code sinking between
basic blocks can move computations across its position earlier in the
pipeline. This experiment adds a TTI query for the IR Sink pass and a check in
AMDGPU's `isSafeToSink` for MachineSink.

Enable with `-amdgpu-sched-barrier-blocks-code-motion`. It remains off by default:
keeping a row-sum computation in its intended place extended live ranges and
introduced a Q-fragment spill that cost more than the scheduling benefit.

Tests:

- `llvm/test/Transforms/Sink/AMDGPU/sched-barrier.ll`
- `llvm/test/CodeGen/AMDGPU/machine-sink-sched-barrier.mir`

This is a design/performance experiment. Its checks cover these two sinking
passes, not every possible form of code motion. The intended semantics of the
intrinsic and the broader TTI interface need discussion before submission.

## FP8/BF8 PR and the already merged fix

- [PR #231556](https://github.com/llvm/llvm-project/pull/231556): remove redundant
  FP8/BF8 destination initialization. Current saved PR commit: `c1c659a557c0`.
  The old InstCombine version introduced LLVM IR `undef` and failed the undef
  deprecation check. The current version uses a machine operand flag in
  `SIFoldOperands`, handling the 32-bit packed forms under SelectionDAG and
  GlobalISel. True16 forms are outside that patch.
- InstCombine backup: `0a73b72eb25a`, retaining all six original commits. Its
  tree is identical to the former squashed PR commit `dbe2566e5ab8`.
- SIFold backup: `c1c659a557c0`.
- Matt (`arsenm`) reviewed **the SIFold version**, not the old IR version. His
  main request is to investigate selection patterns, with a more general
  representation of which half of a register is observed. Start at
  `Cvt_PK_F8_F32_Pat` in `VOP3Instructions.td`.
- His other comments cover the redundant destination-subregister guard in an
  SSA pass, the small lambda, the use iterator, the test split and explicit
  `-verify-machineinstrs`. Preserve checks that reject a value used through a
  conversion's source operand when considering an iterator change.
- The user deferred review changes. See the exact public review snapshot in
  [fp8-review.json](archive/fp8-review.json).
- The bot's initial PR summary still shows the old IR patch. The PR description
  now identifies it as stale. Editing that bot comment required repository
  admin rights and returned HTTP 403.
- [PR #227423](https://github.com/llvm/llvm-project/pull/227423), preventing
  LDS/scratch loads from being selected as SMEM, is already merged. Older
  experiments contain a preliminary version; use the merged upstream fix
  when rebasing, not that preliminary guard.

For `c1c659a557c0`, the local AMDGPU CodeGen, MIR and InstCombine suite recorded
5,296 passes, 5 expected failures and 1 unsupported test. The focused tests,
formatting and undef deprecation checks passed; GitHub's `code_formatter` passed.
Those results apply to that FP8 patch, not the other archived prototypes.

## Validation and experiment setup

Archiving verified source identity, isolated branch contents, whitespace checks,
and the published branch IDs. It did not rebuild these old prototypes or rerun
GPU benchmarks. The old combined-experiment lit logs list four failures:
`lto-lower-module-lds.ll`, `anyext-s16-to-s64.ll`,
`amdgpu-llvm-debuginfo-analyzer.ll` and `packed-fp64.ll`. They were not diagnosed
as part of this archive. Excerpts are in
[historical-validation.txt](archive/historical-validation.txt).

The original FlyDSL LLVM base was `3e77a0cc6451`, which adds the ROCDL/lld argv[0]
patch on top of `e2a39f504fee`. The exact combined backup retains that prerequisite.
Its recorded build used Release, assertions enabled, `X86;AMDGPU` targets,
the `mlir` project, and the ROCm clang/clang++ toolchain. Build `mlir-opt` for
kernel experiments; the small regression tests use `llc`, `opt` and `FileCheck`.

The companion kernel project's external LLVM integration is already committed
to its private GitHub remote. That remote commit was checked during archiving.
Use `FLYDSL_LLVM_DIR` at CMake configuration time, or
`FLYDSL_COMPILE_LLVM_DIR`, to point it at a build containing `bin/mlir-opt`.
The helper `ds_read_b128_invariant` supplies the annotated LDS reads. Kernel
source and the integration patch are not copied into this public LLVM fork.

## Restore after reformatting

```sh
git clone git@github.com:alexioslyrakis-amd/llvm-project.git
cd llvm-project
git remote add upstream https://github.com/llvm/llvm-project.git
git show origin/alyr/llvm-contribution-notes:LLVM-CONTRIBUTIONS.md
git switch --track origin/alyr/remat-invariant-lds-loads
```

Replace the final branch with the contribution being resumed. The three
prototype branches are independent; each contains one contribution commit
above the common base. Preserve the backup branches when creating a new branch
for rebasing or redesigning a contribution.

From the companion development workspace, builds can run through:

```sh
make dev-container-build CMD='cmake -S tmp/llvm-upstream/llvm -B tmp/llvm-backup-build -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=ON -DLLVM_TARGETS_TO_BUILD="X86;AMDGPU"'
make dev-container-build CMD='cmake --build tmp/llvm-backup-build --target llc opt FileCheck -j4'
make dev-container-build CMD='python3 tmp/llvm-backup-build/bin/llvm-lit -sv tmp/llvm-upstream/llvm/test/CodeGen/AMDGPU/form-invariant-lds-read-pairs.mir tmp/llvm-upstream/llvm/test/CodeGen/AMDGPU/expand-ds-read-b256-invariant-pseudo.mir'
```

These are restart instructions, not a record of commands rerun for the archive.
Use a separate build directory for each branch. Rebase onto current upstream,
rebuild and validate before turning a prototype into a contribution.
