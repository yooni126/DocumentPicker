#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dispatch/dispatch.h>
#include "FlashRuntimeExtensions.h"

static const NSUInteger FDPMaximumExcelBytes = 20 * 1024 * 1024;

@interface FDPDocumentPickerContext : NSObject <UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, assign) FREContext context;
@property(nonatomic, assign) BOOL requestActive;
@property(nonatomic, assign) NSUInteger generation;
// UI and ownership properties below are accessed only on the main queue.
@property(nonatomic, strong) UIDocumentPickerViewController *picker;
@property(nonatomic, strong) NSFileCoordinator *coordinator;
@property(nonatomic, strong) NSURL *importFolder;
@property(nonatomic, assign) NSUInteger pickerRequest;
- (NSUInteger)reserveRequest;
- (BOOL)isActiveFor:(NSUInteger)request;
- (BOOL)emit:(NSString *)code payload:(NSDictionary *)payload request:(NSUInteger)request;
- (void)showPicker:(NSUInteger)request;
- (void)cancelRequest;
- (void)releaseFile;
- (void)invalidate;
@end

static UIViewController *FDPPresentingController(void) {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) { window = candidate; break; }
                if (!window && !candidate.hidden && candidate.windowLevel == UIWindowLevelNormal)
                    window = candidate;
            }
            if (window) break;
        }
    } else {
        for (UIWindow *candidate in app.windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
    }
    UIViewController *controller = window.rootViewController;
    while (controller) {
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
            controller = controller.presentedViewController;
        else if ([controller isKindOfClass:UINavigationController.class])
            controller = ((UINavigationController *)controller).visibleViewController;
        else if ([controller isKindOfClass:UITabBarController.class])
            controller = ((UITabBarController *)controller).selectedViewController;
        else break;
    }
    return controller;
}

// Copy only the selected document. Streaming bounds memory/disk consumption and
// never changes, renames or deletes the user's original file.
static BOOL FDPCopyWorkbook(NSURL *source, NSURL *destination, NSString * __strong *failure,
                            FDPDocumentPickerContext *state, NSUInteger request) {
    NSInputStream *input = [NSInputStream inputStreamWithURL:source];
    NSOutputStream *output = [NSOutputStream outputStreamWithURL:destination append:NO];
    [input open]; [output open];
    BOOL success = NO;
    NSUInteger total = 0;
    uint8_t buffer[64 * 1024];
    while ([state isActiveFor:request]) {
        NSInteger count = [input read:buffer maxLength:sizeof(buffer)];
        if (count < 0) break;
        if (count == 0) { success = total > 0; break; }
        total += (NSUInteger)count;
        if (total > FDPMaximumExcelBytes) { *failure = @"size"; break; }
        NSInteger offset = 0;
        while (offset < count) {
            NSInteger written = [output write:buffer + offset maxLength:(NSUInteger)(count - offset)];
            if (written <= 0) goto done;
            offset += written;
        }
    }
done:
    [input close]; [output close];
    if (!success) [NSFileManager.defaultManager removeItemAtURL:destination error:nil];
    return success;
}

@implementation FDPDocumentPickerContext
- (instancetype)init {
    self = [super init];
    if (self) _lock = [NSLock new];
    return self;
}
- (NSUInteger)reserveRequest {
    [self.lock lock];
    BOOL accepted = self.context != NULL && !self.requestActive;
    NSUInteger request = 0;
    if (accepted) {
        self.requestActive = YES;
        request = ++self.generation;
    }
    [self.lock unlock];
    return request;
}
- (BOOL)isActiveFor:(NSUInteger)request {
    [self.lock lock];
    BOOL active = self.context != NULL && self.requestActive && self.generation == request;
    [self.lock unlock];
    return active;
}
- (BOOL)emit:(NSString *)code payload:(NSDictionary *)payload request:(NSUInteger)request {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *level = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    [self.lock lock];
    BOOL accepted = self.context != NULL && self.requestActive && self.generation == request;
    if (accepted) {
        self.requestActive = NO;
        // This FRE call is thread-safe. Holding the lock prevents dispatch after
        // the AIR context finalizer has invalidated its handle.
        FREDispatchStatusEventAsync(self.context, (const uint8_t *)code.UTF8String,
                                   (const uint8_t *)(level ?: @"{}").UTF8String);
    }
    [self.lock unlock];
    return accepted;
}
- (void)releaseFile {
    NSURL *ownedFolder = self.importFolder;
    self.importFolder = nil;
    if (ownedFolder) [NSFileManager.defaultManager removeItemAtURL:ownedFolder error:nil];
}
- (void)clearPicker {
    UIDocumentPickerViewController *picker = self.picker;
    self.picker = nil;
    picker.delegate = nil;
    picker.presentationController.delegate = nil;
    if (picker.presentingViewController) [picker dismissViewControllerAnimated:YES completion:nil];
}
- (void)showPicker:(NSUInteger)request {
    if (![self isActiveFor:request]) return;
    [self releaseFile];
    UIViewController *presenter = FDPPresentingController();
    if (!presenter || !presenter.view.window || presenter.isBeingPresented ||
        presenter.isBeingDismissed || [presenter isKindOfClass:UIDocumentPickerViewController.class]) {
        [self emit:@"ERROR" payload:@{@"code": @"presentation"} request:request];
        return;
    }
    [presenter.view endEditing:YES];
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) {
        UTType *xlsx = [UTType typeWithFilenameExtension:@"xlsx"];
        if (!xlsx) xlsx = [UTType typeWithIdentifier:@"org.openxmlformats.spreadsheetml.sheet"];
        if (!xlsx) { [self emit:@"ERROR" payload:@{@"code": @"type"} request:request]; return; }
        picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[xlsx] asCopy:YES];
    } else {
        picker = [[UIDocumentPickerViewController alloc]
                  initWithDocumentTypes:@[@"org.openxmlformats.spreadsheetml.sheet"]
                  inMode:UIDocumentPickerModeImport];
    }
    self.picker = picker;
    self.pickerRequest = request;
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [presenter presentViewController:picker animated:YES completion:^{
        if ([self isActiveFor:request] && self.picker == picker)
            picker.presentationController.delegate = self;
    }];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (controller != self.picker) return;
    [self clearPicker];
    [self emit:@"CANCEL" payload:@{} request:self.pickerRequest];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller {
    if (controller.presentedViewController != self.picker) return;
    [self clearPicker];
    [self emit:@"CANCEL" payload:@{} request:self.pickerRequest];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self documentPicker:controller didPickDocumentsAtURLs:@[url]];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSUInteger request = self.pickerRequest;
    if (controller != self.picker || ![self isActiveFor:request]) return;
    NSURL *source = urls.firstObject;
    [self clearPicker];
    if (!source.isFileURL || ![source.pathExtension.lowercaseString isEqualToString:@"xlsx"]) {
        [self emit:@"ERROR" payload:@{@"code": @"type"} request:request];
        return;
    }
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    self.coordinator = coordinator;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            BOOL scoped = [source startAccessingSecurityScopedResource];
            NSFileManager *manager = NSFileManager.defaultManager;
            NSURL *cache = [manager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
            NSURL *folder = [[cache URLByAppendingPathComponent:@"FDPDocumentPicker" isDirectory:YES]
                            URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
            NSURL *destination = [folder URLByAppendingPathComponent:@"workbook.xlsx"];
            __block NSString *failure = @"read";
            __block BOOL copied = NO;
            NSError *error = nil;
            if (folder && [manager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
                [coordinator coordinateReadingItemAtURL:source options:0 error:&error byAccessor:^(NSURL *readURL) {
                    copied = FDPCopyWorkbook(readURL, destination, &failure, self, request);
                }];
            }
            if (scoped) [source stopAccessingSecurityScopedResource];
            if (error) copied = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.coordinator == coordinator) self.coordinator = nil;
                if (copied && [self isActiveFor:request]) {
                    self.importFolder = folder;
                    if (![self emit:@"SELECT" payload:@{@"url": destination.absoluteString} request:request]) [self releaseFile];
                } else {
                    if (folder) [manager removeItemAtURL:folder error:nil];
                    [self emit:@"ERROR" payload:@{@"code": failure} request:request];
                }
            });
        }
    });
}
- (void)cancelRequest {
    [self.lock lock];
    NSUInteger request = self.generation;
    [self.lock unlock];
    [self.coordinator cancel];
    [self clearPicker];
    [self releaseFile];
    [self emit:@"CANCEL" payload:@{} request:request];
}
- (void)invalidate {
    [self.lock lock];
    self.context = NULL;
    self.requestActive = NO;
    [self.lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{ [self cancelRequest]; });
}
@end

static FDPDocumentPickerContext *FDPState(FREContext context) {
    void *data = NULL;
    if (FREGetContextNativeData(context, &data) != FRE_OK) return nil;
    return (__bridge FDPDocumentPickerContext *)data;
}
static FREObject FDPBoolean(BOOL value) {
    FREObject result = NULL;
    FRENewObjectFromBool(value ? 1 : 0, &result);
    return result;
}
static FREObject FDPIsSupported(FREContext context, void *data, uint32_t argc, FREObject argv[]) {
    return FDPBoolean(FDPState(context) != nil);
}
static FREObject FDPBrowseExcel(FREContext context, void *data, uint32_t argc, FREObject argv[]) {
    FDPDocumentPickerContext *state = FDPState(context);
    NSUInteger request = [state reserveRequest];
    if (request == 0) return FDPBoolean(NO);
    dispatch_async(dispatch_get_main_queue(), ^{ [state showPicker:request]; });
    return FDPBoolean(YES);
}
static FREObject FDPReleaseFile(FREContext context, void *data, uint32_t argc, FREObject argv[]) {
    FDPDocumentPickerContext *state = FDPState(context);
    dispatch_async(dispatch_get_main_queue(), ^{ [state releaseFile]; });
    return NULL;
}
static FREObject FDPCancel(FREContext context, void *data, uint32_t argc, FREObject argv[]) {
    FDPDocumentPickerContext *state = FDPState(context);
    dispatch_async(dispatch_get_main_queue(), ^{ [state cancelRequest]; });
    return NULL;
}
static void FDPContextInitializer(void *data, const uint8_t *type, FREContext context,
                                  uint32_t *count, const FRENamedFunction **functions) {
    FDPDocumentPickerContext *state = [FDPDocumentPickerContext new];
    state.context = context;
    void *retained = (void *)CFBridgingRetain(state);
    if (FRESetContextNativeData(context, retained) != FRE_OK) CFRelease(retained);
    static const FRENamedFunction names[] = {
        {(const uint8_t *)"isSupported", NULL, FDPIsSupported},
        {(const uint8_t *)"browseExcel", NULL, FDPBrowseExcel},
        {(const uint8_t *)"releaseSelectedFile", NULL, FDPReleaseFile},
        {(const uint8_t *)"cancel", NULL, FDPCancel}
    };
    *count = sizeof(names) / sizeof(names[0]);
    *functions = names;
}
static void FDPContextFinalizer(FREContext context) {
    void *data = NULL;
    if (FREGetContextNativeData(context, &data) == FRE_OK && data) {
        FDPDocumentPickerContext *state = CFBridgingRelease(data);
        [state invalidate];
    }
}
__attribute__((visibility("default")))
void FDPDocumentPickerInitializer(void **data, FREContextInitializer *initializer, FREContextFinalizer *finalizer) {
    *data = NULL;
    *initializer = FDPContextInitializer;
    *finalizer = FDPContextFinalizer;
}
__attribute__((visibility("default")))
void FDPDocumentPickerFinalizer(void *data) {}
