#import "metal_probe.h"
#import <Metal/Metal.h>
#include <stdio.h>

int ws_metal_probe(NSString **report) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) { *report = @"Metal compute: NOT RUN (no GPU exposed)\n"; return 2; }
    NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
      "kernel void probe(device uint *out [[buffer(0)]], uint i [[thread_position_in_grid]]) {"
      " if (i < 257) out[i] = i * 3u + 7u; }";
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (!library) { *report = [NSString stringWithFormat:@"Metal compile FAIL: %@\n", error]; return 1; }
    id<MTLFunction> function = [library newFunctionWithName:@"probe"];
    id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];
    if (!pipeline) { *report = [NSString stringWithFormat:@"Metal pipeline FAIL: %@\n", error]; return 1; }
    id<MTLBuffer> output = [device newBufferWithLength:320 * sizeof(uint32_t) options:MTLResourceStorageModeShared];
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
    if (!output || !encoder) { *report = @"Metal allocation/encoder FAIL\n"; return 1; }
    uint32_t *values = output.contents;
    for (unsigned i = 0; i < 320; ++i) values[i] = 0xdeadbeef;
    [encoder setComputePipelineState:pipeline];
    [encoder setBuffer:output offset:0 atIndex:0];
    [encoder dispatchThreadgroups:MTLSizeMake(5, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
    [encoder endEncoding];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [command addCompletedHandler:^(id<MTLCommandBuffer> buffer) { dispatch_semaphore_signal(done); }];
    [command commit];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
        *report = @"Metal compute FAIL: completion timed out (10 seconds)\n"; return 1;
    }
    if (command.status != MTLCommandBufferStatusCompleted) {
        *report = [NSString stringWithFormat:@"Metal execution FAIL: %@\n", command.error]; return 1;
    }
    unsigned failures = 0;
    for (unsigned i = 0; i < 320; ++i)
        if (values[i] != (i < 257 ? i * 3u + 7u : 0xdeadbeef)) failures++;
    *report = [NSString stringWithFormat:
        @"Metal device: %@\nSynthetic compute: %@ (%u/320 outputs and guard values correct)\n"
        "Runtime MSL compilation, pipeline, dispatch, and readback tested. NOT a translated game shader or renderer.\n",
        device.name, failures ? @"FAIL" : @"PASS", 320 - failures];
    return failures ? 1 : 0;
}
#ifdef WS_METAL_CLI
int main(void) {
    @autoreleasepool {
        NSString *report = nil;
        int result = ws_metal_probe(&report);
        puts(report.UTF8String);
        return result == 1 ? 1 : 0; /* GPU absence is explicitly a skip on hosted CI. */
    }
}
#endif
