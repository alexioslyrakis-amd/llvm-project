; RUN: llc -global-isel=0 -mtriple=amdgpu9.50 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=1 -mtriple=amdgpu9.50 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=0 -mtriple=amdgpu11.70 -mattr=-real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=1 -mtriple=amdgpu11.70 -mattr=-real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=0 -mtriple=amdgpu11.70 -mattr=+real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=1 -mtriple=amdgpu11.70 -mattr=+real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=0 -mtriple=amdgpu12.50 -mattr=+real-true16 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -global-isel=1 -mtriple=amdgpu12.50 -mattr=+real-true16 -verify-machineinstrs < %s | FileCheck %s

declare i32 @llvm.amdgcn.cvt.pk.fp8.f32(float, float, i32, i1 immarg)
declare i32 @llvm.amdgcn.cvt.pk.bf8.f32(float, float, i32, i1 immarg)

; The shared conversion must be emitted once, with no zero initialization.
define <2 x i32> @shared(float %a, float %b, float %c, float %d) {
; CHECK-LABEL: shared:
; CHECK-NOT: v_mov_b32{{.*}}, 0
; CHECK: v_cvt_pk_fp8_f32
; CHECK-NOT: v_cvt_pk_fp8_f32
; CHECK: v_cvt_pk_bf8_f32
; CHECK-NOT: v_cvt_pk_fp8_f32
; CHECK: v_cvt_pk_bf8_f32
; CHECK-NOT: v_cvt_pk
; CHECK: s_set{{_?}}pc{{.*}}
 %lo = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 0, i1 false)
 %x = call i32 @llvm.amdgcn.cvt.pk.bf8.f32(float %c, float %d, i32 %lo, i1 true)
 %y = call i32 @llvm.amdgcn.cvt.pk.bf8.f32(float %a, float %d, i32 %lo, i1 true)
 %v = insertelement <2 x i32> poison, i32 %x, i32 0
 %w = insertelement <2 x i32> %v, i32 %y, i32 1
 ret <2 x i32> %w
}

; One same-half user observes the initial high half.
define <2 x i32> @preserved(float %a, float %b, float %c, float %d) {
; CHECK-LABEL: preserved:
; CHECK: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
 %lo = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 %x = call i32 @llvm.amdgcn.cvt.pk.bf8.f32(float %c, float %d, i32 %lo, i1 true)
 %y = call i32 @llvm.amdgcn.cvt.pk.bf8.f32(float %a, float %d, i32 %lo, i1 false)
 %v = insertelement <2 x i32> poison, i32 %x, i32 0
 %w = insertelement <2 x i32> %v, i32 %y, i32 1
 ret <2 x i32> %w
}

; Reading the intermediate as an FP32 source observes all its bits.
define i32 @also_source(float %a, float %b) {
; CHECK-LABEL: also_source:
; CHECK: v_mov_b{{(16|32)}}{{.*}}, {{(7|0x70000|458752)}}
 %lo = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %a, float %b, i32 458752, i1 false)
 %f = bitcast i32 %lo to float
 %hi = call i32 @llvm.amdgcn.cvt.pk.fp8.f32(float %f, float %b, i32 %lo, i1 true)
 ret i32 %hi
}
