//
//  ImageRenamer.h
//  GrabBox
//
//  Created by Jørgen P. Tjernø on 7/13/10.
//  Copyright 2010 devSoft. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GrowlerDelegate.h"

@interface ImageRenamer : NSObject <GrowlerDelegate> {
    NSWindow *window;
    NSImageView *imageView;
    NSTextField *name;
    NSImage *image;
    NSString *path;
    NSString *url;
}

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSImageView *imageView;
@property (assign) IBOutlet NSTextField *name;
@property (nonatomic, retain) NSImage *image;
@property (nonatomic, retain) NSString *path;
@property (nonatomic, retain) NSString *url;

+ (id) renamerForFile:(NSString *)path
                atURL:(NSString *)url;

- (id) initForFile:(NSString *)path
             atURL:(NSString *)url;
- (void) dealloc;

- (void) awakeFromNib;
- (BOOL) windowShouldClose;

- (void) growlClickedWithData:(id)data;
- (void) growlTimedOutWithData:(id)data;

- (void) showRenamer;
- (IBAction) clickedOk:(id)sender;

@end