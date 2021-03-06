//
//  InformationGatherer.m
//  GrabBox
//
//  Created by Jørgen P. Tjernø on 7/10/10.
//  Copyright (C) 2014 Jørgen P. Tjernø. Licensed under GPLv2, see LICENSE in the project root for more info.
//

#import "InformationGatherer.h"

#import "NSData+Base64.h"

static InformationGatherer* defaultInstance = nil;

@interface InformationGatherer ()

@property (nonatomic, retain) NSString* screenshotPath;
@property (nonatomic, retain) NSString* localizedScreenshotPattern;
@property (nonatomic, retain) NSString* workQueuePath;
@property (nonatomic, assign) SInt32 osVersion;
@property (nonatomic, retain) NSSet* dirContents;

@end

@implementation InformationGatherer

@synthesize screenshotPath;
@synthesize workQueuePath;
@synthesize localizedScreenshotPattern;
@synthesize osVersion;
@synthesize dirContents;

#pragma mark -
#pragma mark Singleton management code

/* "The runtime sends initialize to each class in a program exactly one time
 * just before the class, or any class that inherits from it, is sent its first
 * message from within the program. (Thus the method may never be invoked if the
 * class is not used.) The runtime sends the initialize message to classes in a
 * thread-safe manner. Superclasses receive this message before their
 * subclasses."
 */
+ (void)initialize
{
    if (defaultInstance == nil)
        defaultInstance = [[self alloc] init];
}

+ (id) defaultGatherer
{
    return defaultInstance;
}

+ (id) allocWithZone:(NSZone *)zone
{
    /* Make sure we're not allocated more than once. */
    @synchronized(self) {
        if (defaultInstance == nil) {
            return [super allocWithZone:zone];
        }
    }
    return defaultInstance;
}

- (id) init
{
    if (defaultInstance == nil)
    {
        self = [super init];
        if (self)
        {
            [self setScreenshotPath:nil];
            [self setDirContents:[self files]];

            SInt32 MacVersion;
            if (Gestalt(gestaltSystemVersion, &MacVersion) == noErr)
                [self setOsVersion:MacVersion];
            else
                ErrorLog(@"Could not query OS version.");
        }
        return self;
    }

    return defaultInstance;
}

/* Make sure there is always one instance, and make sure it's never free'd. */
- (id) copyWithZone:(NSZone *)zone { return self; }
- (id) retain { return self; }
- (NSUInteger) retainCount { return UINT_MAX; }
- (oneway void) release {}
- (id) autorelease { return self; }

#pragma mark -
#pragma mark Information gathering

- (void) updateScreenshotPath
{
    if (screenshotPath)
        return;

    // Look up ScreenCapture location, or use ~/Desktop as default.
    NSDictionary*  dict = [[NSUserDefaults standardUserDefaults]
                           persistentDomainForName:@"com.apple.screencapture"];
    NSString* foundPath = [dict objectForKey:@"location"];
    if (!foundPath)
        foundPath = [@"~/Desktop" stringByStandardizingPath];
    else
    {
        BOOL isDir = FALSE;
        foundPath = [foundPath stringByStandardizingPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:foundPath
                                                  isDirectory:&isDir] || !isDir)
        {
            [[DMTracker defaultTracker] trackEvent:@"Invalid com.apple.screencapture"
                                    withProperties:@{@"Path": foundPath}];

            NSLog(@"Path specified in com.apple.screencapture location does not exist. Falling back to ~/Desktop.");
            foundPath = [@"~/Desktop" stringByStandardizingPath];
        }
    }

    DLog(@"screenshotPath: %@", foundPath);
    [self setScreenshotPath:foundPath];
}

- (NSString *) screenshotPath
{
    if (!screenshotPath)
    {
        @synchronized(self) { [self updateScreenshotPath]; }
    }

    return screenshotPath;
}

+ (NSDictionary *)stringsForTable:(NSString *)tableName
                       fromBundle:(NSBundle *)bundle
                  forLocalization:(NSString *)localization
{
    NSString *error;
    NSString *tablePath = [bundle pathForResource:tableName
                                           ofType:@"strings"
                                      inDirectory:@""
                                  forLocalization:localization];
    if (!tablePath)
    {
        NSLog(@"%@ doesn't have %@.strings.", localization, tableName);
        return nil;
    }

    NSData* data = [NSData dataWithContentsOfFile:tablePath];
    if (!data)
    {
        ErrorLog(@"Couldn't load %@.lproj/%@.strings.", localization, tableName);
        return nil;
    }

    NSDictionary* table = [NSPropertyListSerialization propertyListFromData:data
                                                           mutabilityOption:NSPropertyListImmutable
                                                                     format:NULL
                                                           errorDescription:&error];
    if (!table)
    {
        ErrorLog(@"Couldn't parse %@.lproj/%@.strings: %@", localization, tableName, error);
        return nil;
    }

    return table;
}

- (NSString *)localizedString:(NSString *)string
                   fromBundle:(NSBundle *)bundle
                        table:(NSString *)tableName
{
    /* Dictionary so we can do lookup for preferred locale -> localizations of the bundle. */
    NSMutableDictionary* bundleLanguages = [NSMutableDictionary dictionary];
    for (NSString* locale in [bundle localizations])
    {
        [bundleLanguages setObject:locale
                            forKey:[NSLocale canonicalLocaleIdentifierFromString:locale]];
    }

    /* Go through each preferred language in order of preference. */
    NSArray* languages = [NSLocale preferredLanguages];
    for (NSString* language in languages)
    {
        DLog(@"Trying language (before canonicalization): %@", language);
        language = [NSLocale canonicalLocaleIdentifierFromString:language];
        DLog(@"Trying language (after canonicalization):  %@", language);

        /* If we can't look it up, it means its not in the bundle. Try next preferred. */
        NSString* lproj = [bundleLanguages objectForKey:language];
        if (!lproj)
        {
            DLog(@"No lproj for %@, trying next preferred language (this isn't necessarily bad).", language);
            continue;
        }

        /* Table of localized strings */
        NSDictionary *table = [InformationGatherer stringsForTable:tableName
                                                        fromBundle:bundle
                                                   forLocalization:lproj];
        if (!table)
        {
            NSLog(@"Lookup failed, trying next language (this isn't necessarily bad).");
            continue;
        }

        /* If we find it - great! Return it. Otherwise, try next. */
        NSString* localizedString = [table objectForKey:string];
        if (localizedString)
        {
            return localizedString;
        }

        NSLog(@"No value for '%@' in %@, trying next preferred language (this isn't necessarily bad).", string, lproj);
    }

    ErrorLog(@"Could not look up a localization for %@ in table %@!", string, tableName);
    return string;
}

- (void) updateLocalizedScreenshotPattern
{
    if (localizedScreenshotPattern)
        return;

    NSString *name;
    NSString *format = @"%@ %@ at %@";
    NSString *formatTable = @"ScreenCapture";
    NSString* screenshotPattern = nil;

    /* These are the keys we look up for localization. */
    if (osVersion >= 0x1070)
    {
        name = @"Screen Shot";
    }
    else if (osVersion >= 0x1060)
    {
        name = @"Screen shot";
        formatTable = @"Localizable";
    }
    else
    {
        name = @"Picture";
        format = @"%@ %@";
    }

    /* Look up the SystemUIServer bundle - we'll be reading its localization strings. */
    NSBundle* systemUIServer = [NSBundle bundleWithPath:@"/System/Library/CoreServices/SystemUIServer.app"];
    if (systemUIServer)
    {
        NSDictionary*  dict = [[NSUserDefaults standardUserDefaults]
                               persistentDomainForName:@"com.apple.screencapture"];
        NSString* nameOverride = [dict objectForKey:@"name"];
        if (nameOverride)
            name = nameOverride;
        else
            name = [self localizedString:name fromBundle:systemUIServer table:@"ScreenCapture"];

        format = [self localizedString:format fromBundle:systemUIServer table:formatTable];
    }
    else
    {
        /* If we can't load the bundle stuff, something is severely wrong. We default to something sane, but log it. */
        ErrorLog(@"Could not load bundle for /System/Library/CoreServices/SystemUIServer.app");
    }

    screenshotPattern = [[NSString stringWithFormat:format, name, @"*", @"*"] stringByAppendingString:@".*"];
    DLog(@"Pattern is %@", screenshotPattern);

    [self setLocalizedScreenshotPattern:screenshotPattern];
}

- (NSString *) localizedScreenshotPattern
{
    if (!localizedScreenshotPattern)
    {
        @synchronized(self) { [self updateLocalizedScreenshotPattern]; }
    }

    return localizedScreenshotPattern;
}

- (void) updateWorkQueuePath
{
    if (workQueuePath)
        return;

    NSString *base = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if ([paths count])
    {
        NSString *bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
        base = [[paths objectAtIndex:0] stringByAppendingPathComponent:bundleName];
    }
    else
    {
        base = NSTemporaryDirectory();
    }
    
    if (base)
    {
        NSError *error;
        [self setWorkQueuePath:[base stringByAppendingPathComponent:@"WorkQueue"]];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:workQueuePath
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error])
        {
            ErrorLog(@"%@ (%ld)", [error localizedDescription], [error code]);
            [self setWorkQueuePath:nil];
        }
    }
}

- (NSString *) workQueuePath
{
    if (!workQueuePath)
    {
        @synchronized(self) { [self updateWorkQueuePath]; }
    }

    return workQueuePath;
}

- (NSSet *)createdFiles
{
    NSSet *newContents = [self files];
    if (!newContents)
        return nil;

#if (MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_5)
    NSMutableSet* newEntries = [NSMutableSet set];
    for (id obj in newContents)
    {
        if ([dirContents member:obj] == nil)
        {
            [newEntries addObject:obj];
        }
    }
#else
    NSSet* newEntries = [newContents objectsPassingTest:^ BOOL (id obj, BOOL* stop) {
        return [dirContents member:obj] == nil;
    }];
#endif

    [self setDirContents:newContents];
    return newEntries;
}

- (NSSet *)filesInDirectory:(NSString *)path
{
    NSError* error;
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray* dirList = [fm contentsOfDirectoryAtPath:path
                                               error:&error];
    if (!dirList)
    {
        ErrorLog(@"Failed getting dirlist: %@", [error localizedDescription]);
        return [NSSet set];
    }
    
    return [NSSet setWithArray:dirList];
}

- (NSSet *)files
{
    return [self filesInDirectory:[self screenshotPath]];
}

@end
