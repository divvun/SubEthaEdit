//  main.m
//  SubEthaEditLSPHost

#import <Foundation/Foundation.h>
#import "SEELSPHostService.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        SEELSPHostService *delegate = [[SEELSPHostService alloc] init];
        NSXPCListener *listener = [NSXPCListener serviceListener];
        listener.delegate = delegate;
        [listener resume];
    }
    return 0;
}
