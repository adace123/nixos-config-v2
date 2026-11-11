// SPDX-License-Identifier: GPL-2.0-only
//
// Battery levels of the Bluetooth accessories macOS has power records for, one
// "<category>\t<percent>\t<charging>\t<name>" line each, for the OmniShell
// battery widget's launchd agent.
//
// macOS keeps these as "Accessory Source" entries in the IOPS power-source
// registry — the same records `pmset -g accps` prints and Control Center draws
// its accessory battery from. `IOPSCopyPowerSourcesInfo` only ever returns the
// internal battery; the list that includes accessories is
// `IOPSCopyPowerSourcesByType(0)`. The symbol is exported by IOKit but declared
// in no SDK header (it takes an integer source-type mask, not a CFString), so
// it is looked up by name rather than linked against a hand-written prototype.
//
// Only Bluetooth transports are emitted: a USB dongle's battery is not what the
// widget is about, and the category (Keyboard, Mouse, …) picks its icon. A
// category or name that would break the line format has its tabs and newlines
// flattened to spaces.

#import <Foundation/Foundation.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <dlfcn.h>

typedef CFArrayRef (*CopyPowerSourcesByTypeFn)(int32_t);

static NSString *flatten(NSString *value)
{
    if (![value isKindOfClass:[NSString class]]) {
        return @"";
    }
    return [[value stringByReplacingOccurrencesOfString:@"\t" withString:@" "]
        stringByReplacingOccurrencesOfString:@"\n"
                                   withString:@" "];
}

int main(void)
{
    @autoreleasepool {
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        CopyPowerSourcesByTypeFn copyByType =
            iokit ? (CopyPowerSourcesByTypeFn)dlsym(iokit, "IOPSCopyPowerSourcesByType") : NULL;
        if (!copyByType) {
            return 1;
        }

        // 0 is the mask that includes every source; the Type key filters out the
        // internal battery below.
        CFArrayRef sources = copyByType(0);
        if (!sources) {
            return 0;
        }

        for (CFIndex i = 0; i < CFArrayGetCount(sources); i++) {
            NSDictionary *source = (__bridge NSDictionary *)CFArrayGetValueAtIndex(sources, i);
            if (![source[@kIOPSTypeKey] isEqual:@"Accessory Source"]) {
                continue;
            }
            NSString *transport = source[@kIOPSTransportTypeKey];
            if ([transport isKindOfClass:[NSString class]] &&
                [transport rangeOfString:@"bluetooth" options:NSCaseInsensitiveSearch].location == NSNotFound) {
                continue;
            }

            NSNumber *current = source[@kIOPSCurrentCapacityKey];
            if (![current isKindOfClass:[NSNumber class]]) {
                continue;
            }
            double percent = current.doubleValue;
            NSNumber *maximum = source[@kIOPSMaxCapacityKey];
            if ([maximum isKindOfClass:[NSNumber class]] && maximum.doubleValue > 0) {
                percent = percent * 100.0 / maximum.doubleValue;
            }

            // Accessory sources carry `Is Charging` as a CFBoolean when the
            // device reports it; absent means not charging (or unknown), which
            // is what pmset's "74%;" line without "charging" says too.
            BOOL charging = [source[@kIOPSIsChargingKey] boolValue];

            printf("%s\t%d\t%d\t%s\n",
                flatten(source[@"Accessory Category"] ?: @"Bluetooth").UTF8String,
                (int)lround(percent), charging ? 1 : 0,
                flatten(source[@kIOPSNameKey] ?: @"Accessory").UTF8String);
        }

        CFRelease(sources);
    }
    return 0;
}
