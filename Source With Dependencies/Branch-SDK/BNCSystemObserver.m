//
//  BNCSystemObserver.m
//  Branch-SDK
//
//  Created by Alex Austin on 6/5/14.
//  Copyright (c) 2014 Branch Metrics. All rights reserved.
//

#include <sys/utsname.h>
#import "BNCPreferenceHelper.h"
#import "BNCSystemObserver.h"
#import "BranchServerInterface.h"
#import <UIKit/UIDevice.h>
#import <UIKit/UIScreen.h>
#import <SystemConfiguration/SystemConfiguration.h>

@implementation BNCSystemObserver

+ (NSString *)getUniqueHardwareId:(BOOL *)isReal andIsDebug:(BOOL)debug {
    NSString *uid = nil;
    *isReal = YES;
    
    Class ASIdentifierManagerClass = NSClassFromString(@"ASIdentifierManager");
    if (ASIdentifierManagerClass && !debug) {
        SEL sharedManagerSelector = NSSelectorFromString(@"sharedManager");
        id sharedManager = ((id (*)(id, SEL))[ASIdentifierManagerClass methodForSelector:sharedManagerSelector])(ASIdentifierManagerClass, sharedManagerSelector);
        SEL advertisingIdentifierSelector = NSSelectorFromString(@"advertisingIdentifier");
        NSUUID *uuid = ((NSUUID* (*)(id, SEL))[sharedManager methodForSelector:advertisingIdentifierSelector])(sharedManager, advertisingIdentifierSelector);
        uid = [uuid UUIDString];
    }
    
    if (!uid && NSClassFromString(@"UIDevice")) {
        uid = [[UIDevice currentDevice].identifierForVendor UUIDString];
    }
    
    if (!uid) {
        uid = [[NSUUID UUID] UUIDString];
        *isReal = NO;
    }
    
    return uid;
}

+ (BOOL)adTrackingSafe {
    Class ASIdentifierManagerClass = NSClassFromString(@"ASIdentifierManager");
    if (ASIdentifierManagerClass) {
        SEL sharedManagerSelector = NSSelectorFromString(@"sharedManager");
        id sharedManager = ((id (*)(id, SEL))[ASIdentifierManagerClass methodForSelector:sharedManagerSelector])(ASIdentifierManagerClass, sharedManagerSelector);
        SEL advertisingEnabledSelector = NSSelectorFromString(@"isAdvertisingTrackingEnabled");
        BOOL enabled = ((BOOL (*)(id, SEL))[sharedManager methodForSelector:advertisingEnabledSelector])(sharedManager, advertisingEnabledSelector);
        return enabled;
    }
    return YES;
}

+ (NSString *)getDefaultUriScheme {
    NSArray *urlTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];

    for (NSDictionary *urlType in urlTypes) {
        NSArray *urlSchemes = [urlType objectForKey:@"CFBundleURLSchemes"];
        for (NSString *urlScheme in urlSchemes) {
            NSString *firstTwoCharacters = [urlScheme substringWithRange:NSMakeRange(0, 2)];
            NSString *firstThreeCharacters = [urlScheme substringWithRange:NSMakeRange(0, 3)];
            BOOL isFBScheme = [firstTwoCharacters isEqualToString:@"fb"];
            BOOL isDBScheme = [firstTwoCharacters isEqualToString:@"db"];
            BOOL isPinScheme = [firstThreeCharacters isEqualToString:@"pin"];
            
            // Don't use the schemes set aside for other integrations.
            if (!isFBScheme && !isDBScheme && !isPinScheme) {
                return urlScheme;
            }
        }
    }

    return nil;
}

+ (NSString *)getAppVersion {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
}

+ (NSString *)getCarrier {
    NSString *carrierName = nil;
    
    Class CTTelephonyNetworkInfoClass = NSClassFromString(@"CTTelephonyNetworkInfo");
    if (CTTelephonyNetworkInfoClass) {
        id networkInfo = [[CTTelephonyNetworkInfoClass alloc] init];
        SEL subscriberCellularProviderSelector = NSSelectorFromString(@"subscriberCellularProvider");
        
        id carrier = ((id (*)(id, SEL))[networkInfo methodForSelector:subscriberCellularProviderSelector])(networkInfo, subscriberCellularProviderSelector);
        if (carrier) {
            SEL carrierNameSelector = NSSelectorFromString(@"carrierName");
            carrierName = ((NSString* (*)(id, SEL))[carrier methodForSelector:carrierNameSelector])(carrier, carrierNameSelector);
        }
    }
    
    return carrierName;
}

+ (NSString *)getBrand {
    return @"Apple";
}

+ (NSString *)getModel {
    struct utsname systemInfo;
    uname(&systemInfo);
    
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

+ (BOOL)isSimulator {
    UIDevice *currentDevice = [UIDevice currentDevice];
    return [currentDevice.model rangeOfString:@"Simulator"].location != NSNotFound;
}

+ (NSString *)getDeviceName {
    if ([BNCSystemObserver isSimulator]) {
        struct utsname name;
        uname(&name);
        return [NSString stringWithFormat:@"%@ %s", [[UIDevice currentDevice] name], name.nodename];
    } else {
        return [[UIDevice currentDevice] name];
    }
}

+ (NSNumber *)getUpdateState {
    NSString *storedAppVersion = [BNCPreferenceHelper getAppVersion];
    NSString *currentAppVersion = [BNCSystemObserver getAppVersion];
    NSFileManager *manager = [NSFileManager defaultManager];
    
    // for creation date
    NSURL *documentsDirRoot = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSDictionary *documentsDirAttributes = [manager attributesOfItemAtPath:documentsDirRoot.path error:nil];
    NSDate *creationDate = [documentsDirAttributes fileCreationDate];
    
    // for modification date
    NSString *bundleRoot = [[NSBundle mainBundle] bundlePath];
    NSDictionary *bundleAttributes = [manager attributesOfItemAtPath:bundleRoot error:nil];
    NSDate *modificationDate = [bundleAttributes fileModificationDate];
    
    // No stored version
    if (!storedAppVersion) {
        // Modification and Creation date are more than 60 seconds different indicates an update
        // This would be the case that they were installing a new version of the app that was
        // adding Branch for the first time, where we don't already have an NSUserDefaults value.
        if (ABS([modificationDate timeIntervalSinceDate:creationDate]) > 60) {
            return @2;
        }
        
        // If we don't have one of the previous dates, or they're less than 60 apart,
        // we understand this to be an install.
        return @0;
    }
    // Have a stored version, but it isn't the same as the current value indicates an update
    else if (![storedAppVersion isEqualToString:currentAppVersion]) {
        return @2;
    }
    
    // Otherwise, we have a stored version, and it is equal.
    // Not an update, not an install.
    return @1;
}

+ (void)setUpdateState {
    NSString *currentAppVersion = [BNCSystemObserver getAppVersion];
    [BNCPreferenceHelper setAppVersion:currentAppVersion];
}

+ (NSString *)getOS {
    return @"iOS";
}

+ (NSString *)getOSVersion {
    UIDevice *device = [UIDevice currentDevice];
    return [device systemVersion];
}

+ (NSNumber *)getScreenWidth {
    UIScreen *mainScreen = [UIScreen mainScreen];
    float scaleFactor = mainScreen.scale;
    CGFloat width = mainScreen.bounds.size.width * scaleFactor;
    return [NSNumber numberWithInteger:(NSInteger)width];
}

+ (NSNumber *)getScreenHeight {
    UIScreen *mainScreen = [UIScreen mainScreen];
    float scaleFactor = mainScreen.scale;
    CGFloat height = mainScreen.bounds.size.height * scaleFactor;
    return [NSNumber numberWithInteger:(NSInteger)height];
}

+ (NSDictionary *)getListOfApps {
    NSMutableArray *appsPresent = [[NSMutableArray alloc] init];
    NSMutableArray *appsNotPresent = [[NSMutableArray alloc] init];
    NSDictionary *appsData = [NSDictionary dictionaryWithObjects:@[appsPresent, appsNotPresent] forKeys:@[@"canOpen", @"notOpen"]];
    
    BNCServerResponse *serverResponse = [[[BranchServerInterface alloc] init] retrieveAppsToCheck];
    [BNCPreferenceHelper log:FILE_NAME line:LINE_NUM message:@"returned from app check with %@", serverResponse.data];
    if (serverResponse && serverResponse.data) {
        NSInteger status = [serverResponse.statusCode integerValue];
        NSArray *apps = [serverResponse.data objectForKey:@"potential_apps"];
        UIApplication *application = [UIApplication sharedApplication];
        if (status == 200 && apps && application) {
            for (NSString *app in apps) {
                NSString *uriScheme = app;
                if ([uriScheme rangeOfString:@"://"].location != NSNotFound) {  // if (![uriScheme containsString:@"://"]) {
                    uriScheme = [uriScheme stringByAppendingString:@"://"];
                }
                NSURL *url = [NSURL URLWithString:uriScheme];
                if ([application canOpenURL:url]) {
                    [appsPresent addObject:app];
                } else {
                    [appsNotPresent addObject:app];
                }
            }
        }
    }
    
    return appsData;
}


@end
