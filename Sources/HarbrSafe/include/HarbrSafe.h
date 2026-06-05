//
//  HarbrSafe.h
//  Harbr
//
//  Copyright (c) 2025 Alexander Hayworth
//  Licensed under the MIT License. See LICENSE file for details.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Runs `block` inside an Objective-C @try/@catch.
 *
 * Swift cannot catch ObjC exceptions natively — when AppKit/Foundation
 * APIs (notably NSTask under memory pressure) raise an NSException,
 * the unhandled throw becomes a call to abort() and crashes the app.
 * This shim converts ObjC exceptions into NSError so Swift can react.
 *
 * @return YES if the block ran without raising an exception; NO if an
 *         exception was caught and `error` was populated (when non-nil).
 */
BOOL HarbrSafeTry(NSError * _Nullable * _Nullable error,
                  NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
