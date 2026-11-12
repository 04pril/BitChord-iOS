#import "YTMUWGCore.h"

// BitChord's HTTPAudioSource uses NSURLSession through AudioCacheResourceLoader.
// The URLSession hooks are installed by the shared core. Google app-specific
// HAM/Cronet/Envoy hooks do not apply to this native third-party client.
void YTMUWGInstallTransportPatches(void) {}
NSArray<NSString *> *YTMUWGTransportReportLines(void) {
    return @[@"transport: BitChord URLSession / HTTPAudioSource (app-local proxy)",
             @"scope: URLSession API and cached HTTP audio; system AVFoundation HLS, canvas, WebKit and SMB are outside this proxy scope"];
}
NSArray<NSString *> *YTMUWGScanTransportClasses(void) {
    return YTMUWGTransportReportLines();
}
