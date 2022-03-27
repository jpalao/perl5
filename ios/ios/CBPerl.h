//
//  CBPerl.h
//  Camel Bones - a bare-bones Perl bridge for Objective-C
//  Originally written for ShuX
//
//  Copyright (c) 2002 Sherm Pendley. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PerlImports.h"
#include "perlxsi.h"

#define CBPerlErrorException @"CBPerlErrorException"

typedef void (^PerlCompletionBlock)(int perlRunResult);

@interface CBPerl : NSObject {
    PerlInterpreter * _CBPerlInterpreter;
}

// _CBPerlInterpreter: pointer to this CBPerl object's perl interpreter
@property (nonatomic, assign) PerlInterpreter * CBPerlInterpreter;

@property (nonatomic, assign) NSString * perlVersionString;

// getPerlInterpreter: Class method that returns the current perl Interpreter
+ (PerlInterpreter *) getPerlInterpreter;

// The following three methods handle global registration of CBPerl objects and their perl
// interpreters through perlInstanceDict and perlInitialized globals

// getPerlInterpreter: Class method that returns the global perl Interpreter dictionary
// It will initialize the dictionary if not already initialized
+ (NSMutableDictionary *) getPerlInstanceDictionary;

// init the perl instance Dictionary
+ (void) initPerlInstanceDictionary: (NSMutableDictionary *) dictionary;

// if passed the correct pointer will delete the dictionary
// make sure the dictionary is empty before using this!!!
+ (void) clearPerlInstanceDictionary: (NSMutableDictionary *) dictionary;

// getCBPerlFromPerlInterpreter: Class method that returns the CBPerl object corresponding to an embedded perl interpreter object
+ (CBPerl *) getCBPerlFromPerlInterpreter: (PerlInterpreter *) perlInterpreter;

// setCBPerl: Class method that sets the CBPerl object corresponding to an embedded perl interpreter object
+ (void) setCBPerl:(CBPerl *) cbperl forPerlInterpreter:(PerlInterpreter *) perlInterpreter;

// clean up this CBPerl object's perl interpreter
- (void) cleanUp;

// init this CBPerl object with a new perl interpreter
-(void) initWithFileName:(NSString*)fileName withAbsolutePwd:(NSString*)pwd withDebugger:(Boolean)debuggerEnabled withOptions:(NSArray *) options withArguments:(NSArray *) arguments error:(NSError **)error completion:(PerlCompletionBlock)completion;

- (void) dealloc;

// initXS: A version of init suitable for use within XS modules
- (id) initXS;

// Pseudo fork implementation
+ (void *) perl_fork;
+ (void *) perl_getpid;
+ (void *) perl_wait;
+ (void *) perl_kill: (int) pid with_signal: (int) signal;
+ (void *) perl_waitpid: (int) pid with_flags: (int) flags;
@end

