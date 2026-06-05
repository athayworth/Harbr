//
//  HarbrSafe.m
//  Harbr
//
//  Copyright (c) 2025 Alexander Hayworth
//  Licensed under the MIT License. See LICENSE file for details.
//

#import "HarbrSafe.h"

NSString * const HarbrSafeErrorDomain = @"com.harbr.app.HarbrSafe";

BOOL HarbrSafeTry(NSError **error, NS_NOESCAPE void (^block)(void)) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: @"Unknown Objective-C exception";
            info[@"ExceptionName"] = exception.name ?: @"Unknown";
            if (exception.callStackSymbols != nil) {
                info[@"CallStack"] = exception.callStackSymbols;
            }
            *error = [NSError errorWithDomain:HarbrSafeErrorDomain
                                          code:1
                                      userInfo:info];
        }
        return NO;
    }
}
