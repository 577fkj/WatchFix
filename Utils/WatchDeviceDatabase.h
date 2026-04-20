#pragma once

#import <Foundation/Foundation.h>

// ===========================================================================
// WatchDeviceDatabase — 设备型号 → 资源名称 全流程说明
// ===========================================================================
//
// 从 Watch 型号字符串（如 "Watch7,11"）到最终资源文件名
// （如 "WatchBlank-M14-502h@2x.png"）共经过 4 个转换步骤：
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ Step 1 │ 解析 product type 字符串                                       │
// │        │                                                                 │
// │        │  "Watch7,11"  ──regex──►  family="Watch"  major=7  minor=11    │
// │        │                                                                 │
// │        │  格式：^([A-Za-z]+)(\d+),(\d+)$                               │
// │        │  仅处理 family == "Watch"，其余型号返回 nil/0                  │
// └─────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ Step 2 │ major × minor  →  NanoRegistry size（NR size，1–9）            │
// │        │                                                                 │
// │        │  函数：WatchDeviceNRSizeForWatchMajorMinor(major, minor)        │
// │        │                                                                 │
// │        │  Watch7（Series 9 / Ultra 2 / Series 10）：                     │
// │        │    minor  1,3 → 5   (S9  41mm)                                 │
// │        │    minor  2,4 → 6   (S9  45mm)                                 │
// │        │    minor  5   → 7   (Ultra 2 49mm)                             │
// │        │    minor  8,10→ 8   (S10 42mm)                                 │
// │        │    minor  9,11→ 9   (S10 46mm)   ← Watch7,11 = NR 9           │
// │        │                                                                 │
// │        │  Watch6（S6 / S7 / SE2 / S8 / Ultra 1）：                      │
// │        │    minor  1,3       → 4  (S6  40mm 系列)                       │
// │        │    minor  2,4       → 3  (S6  44mm 系列)                       │
// │        │    minor  6,8       → 5  (S7  41mm 系列)                       │
// │        │    minor  7,9       → 6  (S7  45mm 系列)                       │
// │        │    minor  10,12     → 4  (SE2 40mm 系列)                       │
// │        │    minor  11,13     → 3  (SE2 44mm 系列)                       │
// │        │    minor  14,16     → 5  (S8  41mm 系列)                       │
// │        │    minor  15,17     → 6  (S8  45mm 系列)                       │
// │        │    minor  18        → 7  (Ultra 1 49mm)                        │
// │        │                                                                 │
// │        │  Watch5（SE1 第一代）：                                         │
// │        │    minor  9,11  → 4  (40mm)                                    │
// │        │    minor  10,12 → 3  (44mm)                                    │
// └─────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ Step 3 │ NR size  →  bridge/PBB size（规范化编号，1–21）                │
// │        │                                                                 │
// │        │  函数：WatchDeviceBridgeSizeForNRSize(nrSize)                   │
// │        │                                                                 │
// │        │   NR 1 → bridge  1  (Regular / ~38mm)                          │
// │        │   NR 2 → bridge  2  (Compact / ~40mm)                          │
// │        │   NR 3 → bridge  7  (448h / S4–S6 44mm)                        │
// │        │   NR 4 → bridge  8  (394h / S4–S6 40mm)                        │
// │        │   NR 5 → bridge 14  (430h / S7/S8/S9 41mm)                     │
// │        │   NR 6 → bridge 13  (484h / S7/S8/S9 45mm)                     │
// │        │   NR 7 → bridge 19  (502h / Ultra 1 & 2 49mm)                  │
// │        │   NR 8 → bridge 20  (446h / S10 42mm)                          │
// │        │   NR 9 → bridge 21  (496h / S10 46mm)   ← Watch7,11           │
// │        │                                                                 │
// │        │  注：bridge size 还存在 behavior 变体（+1/+2 偏移），           │
// │        │      WatchDeviceNormalizeBridgeSize() 将所有变体归一化          │
// │        │      到上表中的基准值：{1,3,5}→1, {7,9,11}→7 …               │
// └─────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ Step 4 │ bridge size  →  资源名称                                        │
// │        │                                                                 │
// │        │  函数：WatchDeviceAssetNameForBridgeSize(bridgeSize, prefix)    │
// │        │  内部查 kWatchDeviceAssetTable → (material, sizeAlias)          │
// │        │                                                                 │
// │        │  BridgePreferences.framework 资源命名格式：                     │
// │        │    {prefix}-{material}-{sizeAlias}[@{scale}x].png              │
// │        │                                                                 │
// │        │  bridge size 对应关系（含 iOS 16 bundle 回退）：                │
// │        │    size  1 → M3-regular                                         │
// │        │    size  2 → M3-compact                                         │
// │        │    size  7 → M3-448h                                            │
// │        │    size  8 → M3-394h                                            │
// │        │    size 13 → M3-484h                                            │
// │        │    size 14 → M3-430h                                            │
// │        │    size 19 → M14-502h  (Ultra 1)                                │
// │        │    size 19 → M14-502h  (Ultra 1/2)                                │
// │        │    size 20 → M3-430h   ← 446h 不存在，回退 S8/S9 41mm 资源         │
// │        │    size 21 → M3-484h   ← 496h 不存在，回退 S8/S9 45mm 资源         │
// │        │                                                                 │
// │        │  Watch7,11 (NR=9, bridge=21) 最终得到：                        │
// │        │    WatchBlank-M14-502h@2x.png                                  │
// └─────────────────────────────────────────────────────────────────────────┘
//
// 完整示例（Watch7,11 → WatchBlank-M14-502h）：
//
//   "Watch7,11"
//      │ Step 1: 解析
//      ▼
//   major=7, minor=11
//      │ Step 2: WatchDeviceNRSizeForWatchMajorMinor(7, 11)
//      ▼
//   NR size = 9
//      │ Step 3: WatchDeviceBridgeSizeForNRSize(9)
//      ▼
//   bridge size = 21  (原始 496h，iOS 16 无此资产)
//      │ Step 4: WatchDeviceAssetNameForBridgeSize(21, @"WatchBlank")
//      │         查表 → (M14, 502h)  ← 回退
//      ▼
//   @"WatchBlank-M14-502h"  →  文件: WatchBlank-M14-502h@2x.png
//
// ===========================================================================

__BEGIN_DECLS

/// 内部 size 变体编号 → 规范化 bridge size（消除 behavior 差异）
/// 例：{1,3,5}→1, {7,9,11}→7, {19,24}→19；未识别返回 0
NSInteger WatchDeviceNormalizeBridgeSize(NSInteger size);

/// 规范化 bridge size → 显示名称，例如 @"484h"、@"Regular"
/// 未知 size 返回 @"Generic"
NSString *WatchDeviceDisplayNameForBridgeSize(NSInteger bridgeSize);

/// Watch 系列 (major=5/6/7) major × minor → NanoRegistry size（1-9），未知返回 0
NSInteger WatchDeviceNRSizeForWatchMajorMinor(NSInteger major, NSInteger minor);

/// NanoRegistry size → 规范化 bridge/PBB size，未知返回 0
NSInteger WatchDeviceBridgeSizeForNRSize(NSInteger nrSize);

/// NR size × behavior → 内部 size 编号（behavior=0/1/2）
NSInteger WatchDeviceInternalSizeForNRSizeAndBehavior(NSInteger nrSize, NSInteger behavior);

/// BridgePreferences.framework 内每个 pbb bridge size 对应的资源组件
/// material: @"M3" 或 @"M14"
/// sizeAlias: @"484h" / @"502h" 等（bundle 内实际存在的 size 名）
/// 446h / 496h 在 iOS 16 bundle 内不存在，统一回退到 M14-502h
BOOL WatchDeviceAssetComponentsForBridgeSize(NSInteger bridgeSize,
                                              NSString * __autoreleasing *outMaterial,
                                              NSString * __autoreleasing *outSizeAlias);

/// 生成完整资源名，例如 @"WatchBlank-M3-484h"
/// prefix 传入 @"WatchBlank" / @"WatchPairingRestore" 等
/// bridgeSize 未知时返回 nil
NSString *WatchDeviceAssetNameForBridgeSize(NSInteger bridgeSize, NSString *prefix);

/// bridge size 对应的 fallback 材质整数
/// 特殊 size（Ultra 系列）返回 14（M14），正常 size 返回 0
NSInteger WatchDeviceFallbackMaterialForBridgeSize(NSInteger bridgeSize);

/// CLHS 值 → 修补材质，未知返回 0
NSInteger WatchDevicePatchedMaterialForCLHSValue(NSInteger clhs);

/// 材质 M 类型覆盖值，未知返回 0
NSInteger WatchDeviceMMaterialOverrideValue(NSInteger material);

/// 材质 E 类型覆盖值，未知返回 0
NSInteger WatchDeviceEMaterialOverrideValue(NSInteger material);

__END_DECLS
