#import "MDSBatch.h"

@implementation MDSBatch

- (instancetype)initWithEvents:(NSArray<MDSSimulationEvent *> *)events
                  coincidences:(NSArray<MDSCoincidence *> *)coincidences {
    self = [super init];
    if (self) {
        _events = [events copy] ?: @[];
        _coincidences = [coincidences copy] ?: @[];
    }
    return self;
}

- (BOOL)isEmpty {
    return self.events.count == 0 && self.coincidences.count == 0;
}

@end
​​​​