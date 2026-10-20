// charge-limit: read or set macOS's own battery Charge Limit (System Settings ›
// Battery › Charge Limit) from a shell. It is the same PowerUIAgent client the
// Settings pane uses (PowerUI private framework) and needs no root.
//
//   charge-limit        print the limit (100 = no limit)
//   charge-limit 80     set it; macOS offers 80, 85, 90, 95 and 100
#import <Foundation/Foundation.h>
#include <dlfcn.h>

@interface PowerUISmartChargeClient : NSObject
- (instancetype)initWithClientName:(NSString *)name;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
@end

int main(int argc, char **argv) {
  @autoreleasepool {
    if (!dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW)) {
      fprintf(stderr, "charge-limit: %s\n", dlerror());
      return 1;
    }
    PowerUISmartChargeClient *client =
        [[NSClassFromString(@"PowerUISmartChargeClient") alloc] initWithClientName:@"charge-limit"];
    if (!client) {
      fprintf(stderr, "charge-limit: PowerUISmartChargeClient not found\n");
      return 1;
    }
    NSError *error = nil;
    if (argc > 1) {
      int want = atoi(argv[1]);
      if (want < 80 || want > 100) {
        fprintf(stderr, "charge-limit: %s is outside 80-100\n", argv[1]);
        return 2;
      }
      if (![client setMCLLimit:(unsigned char)want error:&error]) {
        fprintf(stderr, "charge-limit: set %d failed: %s\n", want, error.description.UTF8String ?: "");
        return 1;
      }
    }
    unsigned char limit = [client getMCLLimitWithError:&error];
    if (error) {
      fprintf(stderr, "charge-limit: %s\n", error.description.UTF8String);
      return 1;
    }
    printf("%u\n", limit);
  }
  return 0;
}
