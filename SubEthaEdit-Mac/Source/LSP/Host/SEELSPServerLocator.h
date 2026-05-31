//  SEELSPServerLocator.h
//  SubEthaEditLSPHost

#import <Foundation/Foundation.h>

@interface SEELSPServerLocator : NSObject

// Absolute path of an executable named `command` on the user's PATH / common
// install dirs, or nil if not found. An absolute `command` is returned as-is
// when it is executable.
+ (NSString *)resolvedPathForCommand:(NSString *)command;

// The effective search list: the login shell's PATH merged with the usual
// install directories (Homebrew, cargo, go, …). Also seeded into the child's
// environment so launched servers can find their own helper tools.
+ (NSArray<NSString *> *)searchPaths;

@end
