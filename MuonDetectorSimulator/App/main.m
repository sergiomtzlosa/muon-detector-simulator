#import <Cocoa/Cocoa.h>

#import "MDSAppDelegate.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        MDSAppDelegate *delegate = [[MDSAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
        (void)delegate;
    }
    return 0;
}
​​​​​​