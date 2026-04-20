#import <Foundation/Foundation.h>
#import "WatchDeviceDatabase.h"
#import "utils.h"

// 完整流程："WatchX,Y" → NR size → bridge size → 资源名
// 详见 WatchDeviceDatabase.h 顶部注释

// ---------------------------------------------------------------------------
// 1. 内部 size 变体 → 规范化 bridge size
//
// bridge size 因 behavior 不同存在三套编号（详见 Section 5）：
//   behavior 0（基准）: 1,2,7,8,13,14,19,20,21
//   behavior 1（+偏移）: 3,4,9,10,15,16,22,23,24
//   behavior 2（+偏移）: 5,6,11,12,17,18（部分与基准重叠）
//
// 归一化规则：
//   {1,3,5}→1   {2,4,6}→2
//   {7,9,11}→7  {8,10,12}→8
//   {13,15,17}→13  {14,16,18}→14
//   {19,24}→19  {20,22}→20  {21,23}→21
// ---------------------------------------------------------------------------

NSInteger WatchDeviceNormalizeBridgeSize(NSInteger size) {
    switch (size) {
        case 1: case 3: case 5:    return 1;
        case 2: case 4: case 6:    return 2;
        case 7: case 9: case 11:   return 7;
        case 8: case 10: case 12:  return 8;
        case 13: case 15: case 17: return 13;
        case 14: case 16: case 18: return 14;
        case 19: case 24:          return 19;
        case 20: case 22:          return 20;
        case 21: case 23:          return 21;
        default:                   return 0;
    }
}

// ---------------------------------------------------------------------------
// 2. 规范化 bridge size → 显示名称
//
// 名称来自屏幕分辨率高度，与 BridgePreferences 资源文件名一致：
//   size  1 → "Regular"  (第一代 38mm)         340h
//   size  2 → "Compact"  (旧款 42mm / S1–S3)
//   size  7 → "448h"     (S4–S6 44mm)           368×448
//   size  8 → "394h"     (S4–S6 40mm)           324×394
//   size 13 → "484h"     (S7/S8/S9 45mm)        396×484
//   size 14 → "430h"     (S7/S8/S9 41mm)        352×430
//   size 19 → "502h"     (Ultra 1/2 49mm)        410×502
//   size 20 → "446h"     (S10 42mm)             374×446
//   size 21 → "496h"     (S10 46mm)             416×496
// ---------------------------------------------------------------------------

NSString *WatchDeviceDisplayNameForBridgeSize(NSInteger bridgeSize) {
    switch (bridgeSize) {
        case 1:  return @"Regular";
        case 2:  return @"Compact";
        case 7:  return @"448h";
        case 8:  return @"394h";
        case 13: return @"484h";
        case 14: return @"430h";
        case 19: return @"502h";
        case 20: return @"446h";
        case 21: return @"496h";
        default: return @"Generic";
    }
}

// ---------------------------------------------------------------------------
// 3. Watch 系列 major × minor → NanoRegistry size
//
// NR size 是 NanoRegistry 内部对屏幕尺寸的编号（取値 1–9）：
//   5 = S7/S8/S9 41mm        6 = S7/S8/S9 45mm
//   8 = S10 42mm             9 = S10 46mm
//   7 = Ultra 1/2 49mm
//
// kWatch7NRSizeTable  (minor 1–11, Watch7)：
//   index: 1   2   3   4   5   6   7   8   9  10  11
//   NR  :  5   6   5   6   7   -   -   8   9   8   9
//   对应： S9/41 S9/45 S9/41 S9/45 U2/49  无  无 S10/42 S10/46 S10/42 S10/46
//
// kWatch6NRSizeTable  (minor 1–18, Watch6)：
//   index: 1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18
//   NR  :  4   3   4   3   -   5   6   5   6   4   3   4   3   5   6   5   6   7
//   对应： S6/40 S6/44 S6/40 S6/44  无 S7/41 S7/45 S7/41 S7/45 SE2/40 SE2/44 SE2/40 SE2/44 S8/41 S8/45 S8/41 S8/45 U1/49
//
// kWatch5NRSizeTable  (minor 9–12, Watch5 = SE1 第一代)：
//   index: 9  10  11  12
//   NR  :  4   3   4   3
//   对应： 40mm 44mm 40mm 44mm
// ---------------------------------------------------------------------------
// 按 minor 1-based 索引（0 = 无效型号）

static const int8_t kWatch7NRSizeTable[] = { 5, 6, 5, 6, 7, 0, 0, 8, 9, 8, 9 };           // minor 1-11
static const int8_t kWatch6NRSizeTable[] = { 4, 3, 4, 3, 0, 5, 6, 5, 6, 4, 3, 4, 3, 5, 6, 5, 6, 7 }; // minor 1-18
static const int8_t kWatch5NRSizeTable[] = { 4, 3, 4, 3 };                                  // minor 9-12

NSInteger WatchDeviceNRSizeForWatchMajorMinor(NSInteger major, NSInteger minor) {
    switch (major) {
        case 7: {
            if (minor < 1 || minor > (NSInteger)(sizeof(kWatch7NRSizeTable))) return 0;
            return kWatch7NRSizeTable[minor - 1];
        }
        case 6: {
            if (minor < 1 || minor > (NSInteger)(sizeof(kWatch6NRSizeTable))) return 0;
            return kWatch6NRSizeTable[minor - 1];
        }
        case 5: {
            if (minor < 9 || minor > 12) return 0;
            return kWatch5NRSizeTable[minor - 9];
        }
        default:
            return 0;
    }
}

// ---------------------------------------------------------------------------
// 4. NanoRegistry size → bridge/PBB size
//
// bridge size 是 BridgePreferences.framework 内部对资源的索引编号：
//   NR 1 → bridge  1   NR 2 → bridge  2
//   NR 3 → bridge  7   NR 4 → bridge  8
//   NR 5 → bridge 14   NR 6 → bridge 13
//   NR 7 → bridge 19   NR 8 → bridge 20   NR 9 → bridge 21
// ---------------------------------------------------------------------------

NSInteger WatchDeviceBridgeSizeForNRSize(NSInteger nrSize) {
    switch (nrSize) {
        case 1: return 1;
        case 2: return 2;
        case 3: return 7;
        case 4: return 8;
        case 5: return 14;
        case 6: return 13;
        case 7: return 19;
        case 8: return 20;
        case 9: return 21;
        default: return 0;
    }
}

// ---------------------------------------------------------------------------
// 5. NR size × behavior → 内部 size 编号
//
// behavior 是 WatchApp 内部标志，影响动画、布局等行为；引入不同 size 变体：
//   behavior 0 (默认): NR 直接映射到 bridge 基准序列
//   behavior 1 (变体 A): 奇数偏移，如 NR1→3, NR3→9, NR7→24
//   behavior 2 (变体 B): 偶数偏移，如 NR1→5, NR3→11, NR7→19
// ---------------------------------------------------------------------------

NSInteger WatchDeviceInternalSizeForNRSizeAndBehavior(NSInteger nrSize, NSInteger behavior) {
    switch (behavior) {
        case 1:
            switch (nrSize) {
                case 1: return 3;
                case 2: return 4;
                case 3: return 9;
                case 4: return 10;
                case 5: return 16;
                case 6: return 15;
                case 7: return 24;
                case 8: return 22;
                case 9: return 23;
                default: return 0;
            }
        case 2:
            switch (nrSize) {
                case 1: return 5;
                case 2: return 6;
                case 3: return 11;
                case 4: return 12;
                case 5: return 18;
                case 6: return 17;
                case 7: return 19;
                case 8: return 20;
                case 9: return 21;
                default: return 0;
            }
        default:
            switch (nrSize) {
                case 1: return 1;
                case 2: return 2;
                case 3: return 7;
                case 4: return 8;
                case 5: return 14;
                case 6: return 13;
                case 7: return 19;
                case 8: return 20;
                case 9: return 21;
                default: return 0;
            }
    }
}

// ---------------------------------------------------------------------------
// 6. BridgePreferences.framework 资源组件（asset 映射表）
//
// 资源文件命名格式：  {prefix}-{material}-{sizeAlias}[@{scale}x].png
// 例如：  WatchBlank-M3-430h@2x.png
//
// BridgePreferences 材质编号含义：
//   M3  = 基础 OLED 系列（Series 4 及以后所有常规型号，包含 S10）
//   M14 = Ultra 系列（分辨率高于常规型号）
//
// iOS 16 bundle 内实际存在的 size：
//   regular, compact, 394h, 430h, 448h, 484h (材质 M3)
//   502h (材质 M14 / Ultra 1)
//
// 不存在的 size（iOS 16 无对应资产）：
//   446h (size=20, S10 42mm) → 回退 M3-430h（S8/S9 41mm 同材质近似尺寸）
//   496h (size=21, S10 46mm) → 回退 M3-484h（S8/S9 45mm 同材质近似尺寸）
// ---------------------------------------------------------------------------

typedef struct {
    NSInteger   bridgeSize;
    const char *material;
    const char *sizeAlias;
} WatchDeviceAssetEntry;

static const WatchDeviceAssetEntry kWatchDeviceAssetTable[] = {
    {  1, "M3",  "regular" },   // 第一代–Series 3 38mm    272×340
    {  2, "M3",  "compact" },   // 第一代–Series 3 42mm    312×390
    {  7, "M3",  "448h"    },   // S4/S5/SE1/S6 44mm      368×448
    {  8, "M3",  "394h"    },   // S4/S5/SE1/S6 40mm      324×394
    { 13, "M3",  "484h"    },   // S7/SE2/S8/S9 45mm      396×484
    { 14, "M3",  "430h"    },   // S7/SE2/S8/S9 41mm      352×430
    { 19, "M14", "502h"    },   // Ultra 1 & Ultra 2 49mm  410×502
    { 20, "M3",  "430h"    },   // S10 42mm — 446h 不在 iOS 16 bundle，回退 M3-430h
    { 21, "M3",  "484h"    },   // S10 46mm — 496h 不在 iOS 16 bundle，回退 M3-484h
};

static const NSUInteger kWatchDeviceAssetTableCount =
    sizeof(kWatchDeviceAssetTable) / sizeof(kWatchDeviceAssetTable[0]);

BOOL WatchDeviceAssetComponentsForBridgeSize(NSInteger bridgeSize,
                                              NSString * __autoreleasing *outMaterial,
                                              NSString * __autoreleasing *outSizeAlias) {
    for (NSUInteger i = 0; i < kWatchDeviceAssetTableCount; i++) {
        if (kWatchDeviceAssetTable[i].bridgeSize == bridgeSize) {
            if (outMaterial)  *outMaterial  = @(kWatchDeviceAssetTable[i].material);
            if (outSizeAlias) *outSizeAlias = @(kWatchDeviceAssetTable[i].sizeAlias);
            return YES;
        }
    }
    return NO;
}

NSString *WatchDeviceAssetNameForBridgeSize(NSInteger bridgeSize, NSString *prefix) {
    if ([prefix length] == 0) {
        return nil;
    }
    NSString *material  = nil;
    NSString *sizeAlias = nil;
    if (!WatchDeviceAssetComponentsForBridgeSize(bridgeSize, &material, &sizeAlias)) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@-%@-%@", prefix, material, sizeAlias];
}

// ---------------------------------------------------------------------------
// 7. Fallback 材质
//
// 当 iOS 16 bundle 不包含对应 size 的资源时，返回备用材质编号：
//   size 19 (Ultra 1/2 49mm) → fallback M14
//   size 20/21 (S10 42/46mm) → 表中已指定 M3 回退尺寸，无需额外 fallback
//   其余 size 均在 M3 bundle 中直接存在，返回 0 (无需 fallback)
// ---------------------------------------------------------------------------

NSInteger WatchDeviceFallbackMaterialForBridgeSize(NSInteger bridgeSize) {
    switch (bridgeSize) {
        case 19:
            return 14;  // M14（Ultra 1/2 49mm）
        default:
            return 0;   // 正常 size 或已在表中处理，无需 fallback
    }
}

// ---------------------------------------------------------------------------
// 8. CLHS 値 → 修补材质
//
// CLHS (Color/Luminance/Hue/Saturation) 是 Watch 表盘颜色等级内部编号。
// 部分 CLHS 値需要映射到特定材质编号才能匹配正确资源：
//   18→16, 22→17, 23→23, 26→18, 27→19
//   31→21, 32→22, 34→24, 36→25, 38→38, 39→29
// ---------------------------------------------------------------------------

NSInteger WatchDevicePatchedMaterialForCLHSValue(NSInteger clhs) {
    switch (clhs) {
        case 18: return 16;
        case 22: return 17;
        case 23: return 23;
        case 26: return 18;
        case 27: return 19;
        case 31: return 21;
        case 32: return 22;
        case 34: return 24;
        case 36: return 25;
        case 38: return 38;
        case 39: return 29;
        default: return 0;
    }
}

// ---------------------------------------------------------------------------
// 9. 材质 M / E 覆盖値
//
// WatchDeviceMMaterialOverrideValue: 返回材质对应的 M-override 内部编号
//   38→26, 29→27（其余材质返回 0 表示无覆盖）
//
// WatchDeviceEMaterialOverrideValue: 返回材质对应的 E-override 切换开关
//   返回 1：材质 5,7,13,17
//   返回 3：材质 10,11,14,15,23,25,29,38
//   返回 0：无需 E-override
// ---------------------------------------------------------------------------

NSInteger WatchDeviceMMaterialOverrideValue(NSInteger material) {
    switch (material) {
        case 38: return 26;
        case 29: return 27;
        default: return 0;
    }
}

NSInteger WatchDeviceEMaterialOverrideValue(NSInteger material) {
    switch (material) {
        case 5: case 7: case 13: case 17:
            return 1;
        case 10: case 11: case 14: case 15:
        case 23: case 25: case 29: case 38:
            return 3;
        default:
            return 0;
    }
}