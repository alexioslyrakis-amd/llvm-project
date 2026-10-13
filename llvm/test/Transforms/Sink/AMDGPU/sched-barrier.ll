; RUN: opt -mtriple=amdgcn-amd-amdhsa -mcpu=gfx950 -passes=sink -amdgpu-sched-barrier-blocks-code-motion -S < %s | FileCheck %s
; RUN: opt -mtriple=amdgcn-amd-amdhsa -mcpu=gfx950 -passes=sink -S < %s | FileCheck %s --check-prefix=DEFAULT

; By default (option off) sched_barrier only constrains machine scheduling and
; Sink behaves as before.
; DEFAULT-LABEL: @fenced(
; DEFAULT:       use:
; DEFAULT-NEXT:    %sum = fadd float %a, %b

; llvm.amdgcn.sched.barrier(0) forbids moving instructions across it. Sink must
; not carry a computation from above it into a successor block (which would move
; it past the barrier, e.g. to the other side of an s_barrier).

declare void @llvm.amdgcn.sched.barrier(i32 immarg)
declare void @llvm.amdgcn.s.barrier()

; CHECK-LABEL: @fenced(
; CHECK:       entry:
; CHECK-NEXT:    %sum = fadd float %a, %b
; CHECK-NEXT:    call void @llvm.amdgcn.sched.barrier(i32 0)
; CHECK-NEXT:    call void @llvm.amdgcn.s.barrier()
; CHECK:       use:
; CHECK-NEXT:    store float %sum
define void @fenced(float %a, float %b, i1 %c, ptr addrspace(1) %p) {
entry:
  %sum = fadd float %a, %b
  call void @llvm.amdgcn.sched.barrier(i32 0)
  call void @llvm.amdgcn.s.barrier()
  br i1 %c, label %use, label %exit
use:
  store float %sum, ptr addrspace(1) %p
  br label %exit
exit:
  ret void
}

; Below the barrier, sinking is still allowed.
; CHECK-LABEL: @after_fence(
; CHECK:       entry:
; CHECK-NEXT:    call void @llvm.amdgcn.sched.barrier(i32 0)
; CHECK-NEXT:    br i1
; CHECK:       use:
; CHECK-NEXT:    %sum = fadd float %a, %b
define void @after_fence(float %a, float %b, i1 %c, ptr addrspace(1) %p) {
entry:
  call void @llvm.amdgcn.sched.barrier(i32 0)
  %sum = fadd float %a, %b
  br i1 %c, label %use, label %exit
use:
  store float %sum, ptr addrspace(1) %p
  br label %exit
exit:
  ret void
}

; Without the sched_barrier (s_barrier alone), behavior is unchanged: sunk.
; CHECK-LABEL: @no_fence(
; CHECK:       use:
; CHECK-NEXT:    %sum = fadd float %a, %b
define void @no_fence(float %a, float %b, i1 %c, ptr addrspace(1) %p) {
entry:
  %sum = fadd float %a, %b
  call void @llvm.amdgcn.s.barrier()
  br i1 %c, label %use, label %exit
use:
  store float %sum, ptr addrspace(1) %p
  br label %exit
exit:
  ret void
}

; A sched_barrier with a non-zero mask (some instructions may cross) does not
; block sinking.
; CHECK-LABEL: @partial_mask(
; CHECK:       use:
; CHECK-NEXT:    %sum = fadd float %a, %b
define void @partial_mask(float %a, float %b, i1 %c, ptr addrspace(1) %p) {
entry:
  %sum = fadd float %a, %b
  call void @llvm.amdgcn.sched.barrier(i32 2)
  br i1 %c, label %use, label %exit
use:
  store float %sum, ptr addrspace(1) %p
  br label %exit
exit:
  ret void
}
