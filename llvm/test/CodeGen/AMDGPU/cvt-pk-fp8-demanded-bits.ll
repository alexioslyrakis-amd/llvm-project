; RUN: llc -global-isel=1 -mtriple=amdgpu9.50 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=1 -mtriple=amdgpu11.70 -mattr=-real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=1 -mtriple=amdgpu11.70 -mattr=+real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=0 -mtriple=amdgpu9.50 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=0 -mtriple=amdgpu11.70 -mattr=-real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=0 -mtriple=amdgpu11.70 -mattr=+real-true16 -verify-machineinstrs < %s | FileCheck %s

; RUN: llc -global-isel=0 -mtriple=amdgpu12.50 -mattr=-real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=1 -mtriple=amdgpu12.50 -mattr=-real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=0 -mtriple=amdgpu12.50 -mattr=+real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=1 -mtriple=amdgpu12.50 -mattr=+real-true16 -verify-machineinstrs < %s | FileCheck %s

declare i32 @llvm.amdgcn.cvt.pk.fp8.f32(float, float, i32, i1 immarg)
; CHECK-LABEL: mask:
; CHECK-NOT: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
; CHECK: v_cvt_pk_fp8_f32
define i32 @mask(float %a, float %b, float %c, float %d) {
 %x = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 %y = and i32 %x, 65535
 ret i32 %y
}
; CHECK-LABEL: trunc:
; CHECK-NOT: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
; CHECK: v_cvt_pk_fp8_f32
define i32 @trunc(float %a, float %b, float %c, float %d) {
 %x = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 %y = trunc i32 %x to i16
 %z = zext i16 %y to i32
 ret i32 %z
}
; CHECK-LABEL: pair:
; CHECK-NOT: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
; CHECK: v_cvt_pk_fp8_f32
define i32 @pair(float %a, float %b, float %c, float %d) {
 %x = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 %y = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %c, float %d, i32 %x, i1 true)
 ret i32 %y
}

; Different kinds of users all discard the preserved high half.
; CHECK-LABEL: mixed_users:
; CHECK-NOT: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
; CHECK: v_cvt_pk_fp8_f32
; CHECK-NOT: v_cvt_pk_fp8_f32
; CHECK: s_set{{_?}}pc
define <2 x i32> @mixed_users(float %a, float %b) {
 %x = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 %y = and i32 %x, 65535
 %t = trunc i32 %x to i8
 %z = zext i8 %t to i32
 %v = insertelement <2 x i32> poison, i32 %y, i32 0
 %w = insertelement <2 x i32> %v, i32 %z, i32 1
 ret <2 x i32> %w
}

; An unknown full-width consumer must keep the old high half.
; CHECK-LABEL: full_width:
; CHECK: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
define i32 @full_width(float %a, float %b) {
 %x = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 ret i32 %x
}

; The opposite direction preserves the low half, which this mask discards.
; CHECK-LABEL: high_mask:
; CHECK-NOT: v_mov_b{{(16|32)}}{{.*}}, 7
; CHECK: v_cvt_pk_fp8_f32
define i32 @high_mask(float %a, float %b) {
 %x = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 7, i1 true)
 %y = and i32 %x, -65536
 ret i32 %y
}

; A mask that reads the preserved half must keep its initialization.
; CHECK-LABEL: preserve_mask:
; CHECK: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
define i32 @preserve_mask(float %a, float %b) {
 %x = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 %y = and i32 %x, -65536
 ret i32 %y
}

; A variable mask may observe every bit of the intermediate.
; CHECK-LABEL: variable_mask:
; CHECK: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
define i32 @variable_mask(float %a, float %b, i32 %mask) {
 %x = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 %y = and i32 %x, %mask
 ret i32 %y
}

; Inline assembly changing EXEC prevents inferring lane equivalence.
; CHECK-LABEL: exec_change:
; CHECK: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
define i32 @exec_change(float %a, float %b, float %c, float %d) {
 %x = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 call void asm sideeffect "s_mov_b64 exec, 1", "~{exec},~{memory}"()
 %y = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %c, float %d, i32 %x, i1 true)
 ret i32 %y
}

; The PHI observes the complete result on the path without a second conversion.
; CHECK-LABEL: divergent_use:
; CHECK: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
define amdgpu_kernel void @divergent_use(float %a, float %b, float %c, float %d, i1 %cond, ptr addrspace(1) %out) {
entry:
 %x = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 br i1 %cond, label %convert, label %merge
convert:
 %y = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %c, float %d, i32 %x, i1 true)
 br label %merge
merge:
 %z = phi i32 [%x, %entry], [%y, %convert]
 store i32 %z, ptr addrspace(1) %out
 ret void
}
