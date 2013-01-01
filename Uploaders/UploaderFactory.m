//
//  UploaderFactory.m
//  GrabBox2
//
//  Created by Jørgen Tjernø on 7/17/11.
//  Copyright 2011 Lookout, Inc. All rights reserved.
//

#import "UploaderFactory.h"

#import "GrabBoxAppDelegate.h"

#import "WelcomeViewController.h"
#import "DropboxAuthViewController.h"

#import "ImgurUploader.h"
#import "DropboxUploader.h"

NSString * const GBUploaderUnavailableNotification = @"GBUploaderUnavailableNotification";
NSString * const GBUploaderAvailableNotification = @"GBUploaderAvailableNotification";
NSString * const GBGainedFocusNotification = @"GBGainedFocusNotification";

static NSString * const dropboxConsumerKey = @"<INSERT DROPBOX CONSUMER KEY>";
static NSString * const dropboxConsumerSecret = @"<INSERT DROPBOX CONSUMER SECRET>";

static UploaderFactory *defaultFactory = nil;

@interface UploaderFactory ()

@property (assign) Class uploaderClass;
@property (retain) NSViewController *currentVC;

- (void) promptForHost;
- (void) promptForDropboxLink;

- (void) setupHost:(NSInteger)host;
- (void) setupDropbox;
- (void) setupImgur;

- (DBRestClient *)restClient;

@end

@implementation UploaderFactory

@synthesize uploaderClass;
@synthesize currentVC;

@synthesize account;

@synthesize hostSelecter;
@synthesize radioGroup;
@synthesize advanceButton;

+ (void) initialize
{
    if (defaultFactory == nil)
    {
        defaultFactory = [[UploaderFactory alloc] init];
    }
}

+ (id) defaultFactory
{
    return defaultFactory;
}

- (id) init
{
    self = [super init];
    if (self)
    {
        ignoreUpdates = NO;
        [self setUploaderClass:[ImgurUploader class]];
        [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                                  forKeyPath:[@"values." stringByAppendingString:CONFIG(Host)]
                                                                     options:0
                                                                     context:NULL];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(gainedFocus:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(gainedFocus:)
                                                     name:GBGainedFocusNotification
                                                   object:nil];
    }

    return self;
}

- (void) dealloc
{
    [restClient setDelegate:nil];
    [restClient release];
    [self setAccount:nil];
    [self setCurrentVC:nil];

    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self
                                                                 forKeyPath:[@"values." stringByAppendingString:CONFIG(Host)]];
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [super dealloc];
}

- (void) awakeFromNib
{
    NSInteger host = [[NSUserDefaults standardUserDefaults] integerForKey:CONFIG(Host)];
    if (!host)
        host = HostImgur;

    [radioGroup selectCellWithTag:host];

    [hostSelecter makeKeyAndOrderFront:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction) advanceSelecter:(id)sender
{
    NSInteger selectedTag = [radioGroup selectedTag];
    switch (selectedTag)
    {
        case HostDropbox:
            [self setCurrentVC:[[[DropboxAuthViewController alloc] init] autorelease]];
            break;
        case HostImgur:
            [[NSUserDefaults standardUserDefaults] setInteger:selectedTag forKey:CONFIG(Host)];
            [self setCurrentVC:[[[WelcomeViewController alloc] init] autorelease]];
            break;

        default:
            // TODO: Handle this better?
            ErrorLog(@"Invalid selected tag: %ld!", selectedTag);
            [NSApp terminate:self];
            return;
    }

    if (currentVC)
    {
        [hostSelecter setContentView:[currentVC view]];
        [hostSelecter setTitle:[currentVC windowTitle]];
    }
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                         change:(NSDictionary *)change context:(void *)context
{
    if (ignoreUpdates)
        return;

    if ([keyPath isEqualToString:[@"values." stringByAppendingString:CONFIG(Host)]])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadSettings];
        });
    }
}

- (Uploader *) uploaderForFile:(NSString *)file
                   inDirectory:(NSString *)source
{
    return [[[uploaderClass alloc] initForFile:file inDirectory:source] autorelease];
}

- (void) loadSettings
{
    NSInteger host = [[NSUserDefaults standardUserDefaults] integerForKey:CONFIG(Host)];
    [[NSNotificationCenter defaultCenter] postNotificationName:GBUploaderUnavailableNotification object:nil];

    [self setAccount:nil];
    [self setUploaderClass:nil];

    [self setupHost:host];
}

- (DBSession *) dropboxSession
{
    return [[[DBSession alloc] initWithAppKey:dropboxConsumerKey
                                    appSecret:dropboxConsumerSecret
                                         root:kDBRootAppFolder] autorelease];
}

- (void) setupHost:(NSInteger)host
{
    switch (host)
    {
        case HostDropbox:
            [self setupDropbox];
            break;

        case HostImgur:
            [self setupImgur];
            break;

        default:
        {
            DBSession *session = [self dropboxSession];
            if ([session isLinked])
            {
                [session unlinkAll];
                [restClient release];
                restClient = nil;
            }
            [self promptForHost];
            break;
        }
    }
}

- (void) setupDropbox
{
    DBSession *session = [self dropboxSession];
    [session setDelegate:self];
    [DBSession setSharedSession:session];

    NSAppleEventManager *em = [NSAppleEventManager sharedAppleEventManager];
    [em setEventHandler:self
            andSelector:@selector(getUrl:withReplyEvent:)
          forEventClass:kInternetEventClass andEventID:kAEGetURL];

    [[self restClient] setDelegate:self];

    if ([session isLinked])
    {
        [[self restClient] loadAccountInfo];
    }
    else
    {
        [self promptForDropboxLink];
    }
}

- (void)gainedFocus:(NSNotification *)aNotification {
    if ([DBSession sharedSession])
    {
        if ([[self restClient] requestTokenLoaded]) {
            [[self restClient] loadAccessToken];
        }
    }
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
	// This gets called when the user clicks Show "App name". You don't need to do anything for Dropbox here
    // TODO: GH-2: Show a dialog to confirm
}

- (void) setupImgur
{
    [self setUploaderClass:[ImgurUploader class]];
    [[NSNotificationCenter defaultCenter] postNotificationName:GBUploaderAvailableNotification object:nil];
}

- (void) promptForHost
{
    [NSBundle loadNibNamed:@"HostSetup" owner:self];
}

- (void) promptForDropboxLink
{
    [[DMTracker defaultTracker] trackEvent:@"Account Link Prompt"];
    if (![[self restClient] requestTokenLoaded]) {
        [[self restClient] loadRequestToken];
    }
}


#pragma mark DBSession delegate methods

- (void) sessionDidReceiveAuthorizationFailure:(DBSession *)session
                                        userId:(NSString *)userId
{
    [[DMTracker defaultTracker] trackEvent:@"Authorization Failure"];
    NSLog(@"Received authorization failure, disabling app then prompt for link!");
    [self setAccount:nil];
    [self setUploaderClass:nil];

    [[NSNotificationCenter defaultCenter] postNotificationName:GBUploaderUnavailableNotification object:nil];
    [self promptForDropboxLink];
}

#pragma mark DBRestClientOSXDelegate delegate methods

- (void)restClientLoadedRequestToken:(DBRestClient *)restClient
{
    NSURL *url = [[self restClient] authorizeURL];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)restClient:(DBRestClient *)restClient loadRequestTokenFailedWithError:(NSError *)error {
    DLog(@"loadRequestTokenFailedWithError: %@", error);
}

- (void)restClientLoadedAccessToken:(DBRestClient *)restClient {
    [[self restClient] loadAccountInfo];
}

- (void)restClient:(DBRestClient *)restClient loadAccessTokenFailedWithError:(NSError *)error {
    DLog(@"loadAccessTokenFailedWithError: %@", error);
}

#pragma mark DBRestClient delegate methods

- (void)restClient:(DBRestClient*)client
 loadedAccountInfo:(DBAccountInfo*)accountInfo
{
    DLog(@"Got account info, starting FS monitoring and enabling interaction!");
    [self setAccount:accountInfo];
    [self setUploaderClass:[DropboxUploader class]];

    [self setCurrentVC:[[[WelcomeViewController alloc] init] autorelease]];
    [[self hostSelecter] setContentView:[currentVC view]];
    [[self hostSelecter] setTitle:[currentVC windowTitle]];

    [[NSNotificationCenter defaultCenter] postNotificationName:GBUploaderAvailableNotification object:nil];
}

- (void)restClient:(DBRestClient*)client loadAccountInfoFailedWithError:(NSError*)error
{
    // Error codes described here: https://www.dropbox.com/developers/reference/api
    if (error.code == 401)
        // "Bad or expired token. This can happen if the user or Dropbox revoked or expired an access token.
        // To fix, you should re-authenticate the user."
    {
        if (account)
        {
            // TODO: GH-1: Show error dialog & ask to re-auth.
            // For now we just force a re-auth.
            DLog(@"401 from Dropbox when loading account info.");

            [[NSUserDefaults standardUserDefaults] removeObjectForKey:CONFIG(Host)];
        }
        else
        {
            [[DMTracker defaultTracker] trackEvent:@"Bad token on first-run"];
            DLog(@"401 from Dropbox when loading initial account info.");

            [[NSUserDefaults standardUserDefaults] removeObjectForKey:CONFIG(Host)];
        }
    }
    else
    {
        // TODO: GH-3: Open an error dialog!
        ErrorLog(@"Failed retrieving account info: %ld", error.code);
        [NSApp terminate:self];
    }
}

- (DBRestClient *)restClient {
	if (!restClient) {
		restClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
		restClient.delegate = self;
	}
	return restClient;
}

@end
