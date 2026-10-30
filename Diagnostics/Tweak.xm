#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static NSMutableArray<NSString *> *entries;
static NSObject *logLock;
static NSDate *started;

static void Record(NSString *message) {
    if (!logLock || !message) return;
    @synchronized (logLock) {
        NSString *line = [NSString stringWithFormat:@"%7.1fs  %@", -[started timeIntervalSinceNow], message];
        [entries addObject:line];
        if (entries.count > 200) [entries removeObjectAtIndex:0];
    }
}

static void RecordError(NSError *error, NSString *origin) {
    if (!error) return;
    NSString *domain = error.domain;
    if ([domain rangeOfString:@"youtube" options:NSCaseInsensitiveSearch].location == NSNotFound &&
        [domain rangeOfString:@"media" options:NSCaseInsensitiveSearch].location == NSNotFound &&
        ![domain isEqualToString:NSURLErrorDomain] && ![domain isEqualToString:AVFoundationErrorDomain]) return;
    // Deliberately omit userInfo, descriptions, URLs, account IDs and headers.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    if (domain.length > 160 || [domain rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return;
    Record([NSString stringWithFormat:@"%@ domain=%@ code=%ld", origin, domain, (long)error.code]);
}

@interface YTDLogController : UIViewController
@property(nonatomic,strong) UITextView *textView;
@end

static NSString *Snapshot(void) {
    @synchronized (logLock) {
        return [@"YouTube 21.43.5 / YTPlus 5.2b4 diagnostics\nNative share and segment-skip compatibility patches enabled.\nYTUHD playback workaround removed.\nOnly error domains/codes and app/playback state; no request/account data.\n\n" stringByAppendingString:[entries componentsJoinedByString:@"\n"]];
    }
}

@implementation YTDLogController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Playback logs";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.editable = NO;
    self.textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textView];
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeLogs)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareLogs:)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshLogs)]
    ];
    [self refreshLogs];
}
- (void)refreshLogs { self.textView.text = Snapshot(); }
- (void)closeLogs { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)shareLogs:(UIBarButtonItem *)sender {
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[Snapshot()] applicationActivities:nil];
    sheet.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:sheet animated:YES completion:nil];
}
@end

@interface YTDLogAccess : NSObject
@property(nonatomic,strong) UIButton *button;
- (void)attach;
- (void)openLogs;
@end

@implementation YTDLogAccess
- (UIWindow *)activeWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) return window;
    }
    return nil;
}
- (void)attach {
    UIWindow *window = [self activeWindow];
    if (!window) return;
    if (!self.button) {
        self.button = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.button setTitle:@"Logs" forState:UIControlStateNormal];
        self.button.accessibilityLabel = @"Open playback diagnostics";
        self.button.backgroundColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:0.9];
        self.button.layer.cornerRadius = 12;
        [self.button addTarget:self action:@selector(openLogs) forControlEvents:UIControlEventTouchUpInside];
    }
    self.button.frame = CGRectMake(window.bounds.size.width - 66, window.safeAreaInsets.top + 54, 56, 32);
    self.button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    if (self.button.superview != window) [window addSubview:self.button];
    [window bringSubviewToFront:self.button];
}
- (void)openLogs {
    UIViewController *top = [self activeWindow].rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top || [top isKindOfClass:YTDLogController.class]) return;
    if ([top isKindOfClass:UINavigationController.class] && [((UINavigationController *)top).topViewController isKindOfClass:YTDLogController.class]) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[YTDLogController new]];
    [top presentViewController:nav animated:YES completion:nil];
}
@end

%hook NSError
+ (id)errorWithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)info {
    NSError *error = %orig;
    RecordError(error, @"Error");
    return error;
}
- (id)initWithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)info {
    NSError *error = %orig;
    RecordError(error, @"Error init");
    return error;
}
%end

%ctor {
    @autoreleasepool {
        entries = [NSMutableArray new]; logLock = [NSObject new]; started = [NSDate date];
        Record(@"Diagnostics loaded; background workaround OFF");
        %init;
        static YTDLogAccess *access = [YTDLogAccess new];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            Record(@"App active");
            [access attach];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [access attach]; });
        }];
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { Record(@"App entered background"); }];
        [center addObserverForName:AVPlayerItemPlaybackStalledNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { Record(@"AVPlayer playback stalled"); }];
        [center addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            Record(@"AVPlayer failed to finish"); RecordError(n.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey], @"AVPlayer failure");
        }];
        [center addObserverForName:AVPlayerItemNewErrorLogEntryNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (![n.object isKindOfClass:AVPlayerItem.class]) return;
            AVPlayerItemErrorLogEvent *event = ((AVPlayerItem *)n.object).errorLog.events.lastObject;
            if (event) Record([NSString stringWithFormat:@"AVPlayer stream status=%ld", (long)event.errorStatusCode]);
        }];
    }
}
