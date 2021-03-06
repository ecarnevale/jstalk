//
//  JSTalk.m
//  jstalk
//
//  Created by August Mueller on 1/15/09.
//  Copyright 2009 Flying Meat Inc. All rights reserved.
//

#import "JSTalk.h"
#import "JSTListener.h"
#import "JSTPreprocessor.h"
#import <ScriptingBridge/ScriptingBridge.h>

static BOOL JSTalkShouldLoadJSTPlugins = YES;
static NSMutableArray *JSTalkPluginList;

@interface JSTalk (Private)
- (void) print:(NSString*)s;
@end


@implementation JSTalk
@synthesize printController=_printController;
@synthesize errorController=_errorController;
@synthesize jsController=_jsController;

+ (void) load {
    //debug(@"%s:%d", __FUNCTION__, __LINE__);
}

+ (void) listen {
    [JSTListener listen];
}

+ (void) setShouldLoadExtras:(BOOL)b {
    JSTalkShouldLoadJSTPlugins = b;
}

+ (void) setShouldLoadJSTPlugins:(BOOL)b {
    JSTalkShouldLoadJSTPlugins = b;
}

- (id) init {
	self = [super init];
	if (self != nil) {
        self.jsController = [[[JSCocoaController alloc] init] autorelease];
	}
    
	return self;
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if ([_jsController ctx]) {
        JSGarbageCollect([_jsController ctx]);
    }
    
    
    [_jsController release];
    _jsController = 0x00;
    
    [super dealloc];
}

- (void) loadExtraAtPath:(NSString*) fullPath {
    
    Class pluginClass;
    
    @try {
        
        NSBundle *pluginBundle = [NSBundle bundleWithPath:fullPath];
        if (!pluginBundle) {
            return;
        }
        
        NSString *principalClassName = [[pluginBundle infoDictionary] objectForKey:@"NSPrincipalClass"];
        
        if (principalClassName && NSClassFromString(principalClassName)) {
            NSLog(@"The class %@ is already loaded, skipping the load of %@", principalClassName, fullPath);
            return;
        }
        
        NSError *err = 0x00;
        [pluginBundle loadAndReturnError:&err];
        
        if (err) {
            NSLog(@"Error loading plugin at %@", fullPath);
            NSLog(@"%@", err);
        }
        else if ((pluginClass = [pluginBundle principalClass])) {
            
            // do we want to actually do anything with em' at this point?
            
            NSString *bridgeSupportName = [[pluginBundle infoDictionary] objectForKey:@"BridgeSuportFileName"];
            
            if (bridgeSupportName) {
                NSString *bridgeSupportPath = [pluginBundle pathForResource:bridgeSupportName ofType:nil];
                
                [[BridgeSupportController sharedController] loadBridgeSupport:bridgeSupportPath];
            }
        }
        else {
            //debug(@"Could not load the principal class of %@", fullPath);
            //debug(@"infoDictionary: %@", [pluginBundle infoDictionary]);
        }
        
    }
    @catch (NSException * e) {
        NSLog(@"EXCEPTION: %@: %@", [e name], e);
    }
    
}

- (void) loadPlugins {
    JSTalkPluginList = [[NSMutableArray array] retain];
    
    NSString *appSupport = @"Library/Application Support/JSTalk/Plug-ins";
    NSString *appPath    = [[NSBundle mainBundle] builtInPlugInsPath];
    NSString *sysPath    = [@"/" stringByAppendingPathComponent:appSupport];
    NSString *userPath   = [NSHomeDirectory() stringByAppendingPathComponent:appSupport];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:userPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[userPath stringByDeletingLastPathComponent] attributes:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:userPath attributes:nil];
    }
    
    for (NSString *folder in [NSArray arrayWithObjects:appPath, sysPath, userPath, nil]) {
        
        for (NSString *bundle in [[NSFileManager defaultManager] directoryContentsAtPath:folder]) {
            
            if (!([bundle hasSuffix:@".jstplugin"])) {
                continue;
            }
            
            [self loadExtraAtPath:[folder stringByAppendingPathComponent:bundle]];
        }
    }
}

- (void) pushObject:(id)obj withName:(NSString*)name inController:(JSCocoaController*)jsController {
    
    JSContextRef ctx                = [jsController ctx];
    JSStringRef jsName              = JSStringCreateWithUTF8CString([name UTF8String]);
    JSObjectRef jsObject            = [JSCocoaController jsCocoaPrivateObjectInContext:ctx];
    JSCocoaPrivateObject *private   = JSObjectGetPrivate(jsObject);
    private.type = @"@";
    [private setObject:obj];
    
    JSObjectSetProperty(ctx, JSContextGetGlobalObject(ctx), jsName, jsObject, 0, NULL);
    JSStringRelease(jsName);  
}


- (id) executeString:(NSString*) str {
    
    if (!JSTalkPluginList && JSTalkShouldLoadJSTPlugins) {
        [self loadPlugins];
    }
    
    str = [JSTPreprocessor preprocessCode:str];
        
    [self pushObject:self withName:@"jstalk" inController:_jsController];
    
    JSValueRef resultRef = 0x00;
    id resultObj = 0x00;
    
    @try {
        [_jsController setUseAutoCall:NO];
        resultRef = [_jsController evalJSString:[NSString stringWithFormat:@"function print(s) { jstalk.print_(s); } var nil=null; %@", str]];
    }
    @catch (NSException * e) {
        NSLog(@"Exception: %@", e);
        [self print:[e description]];
    }
    @finally {
        //
    }
    
    if (resultRef) {
        [JSCocoaFFIArgument unboxJSValueRef:resultRef toObject:&resultObj inContext:[[self jsController] ctx]];
    }
    
    return resultObj;
}

- (id) callFunctionNamed:(NSString*)name withArguments:(NSArray*)args {
    
    JSCocoaController *jsController = [self jsController];
    JSContextRef ctx                = [jsController ctx];
    
    JSValueRef exception            = 0x00;   
    JSStringRef functionName        = JSStringCreateWithUTF8CString([name UTF8String]);
    JSValueRef functionValue        = JSObjectGetProperty(ctx, JSContextGetGlobalObject(ctx), functionName, &exception);
    
    JSStringRelease(functionName);  
    
    JSValueRef returnValue = [jsController callJSFunction:functionValue withArguments:args];
    
    id returnObject;
    [JSCocoaFFIArgument unboxJSValueRef:returnValue toObject:&returnObject inContext:ctx];
    
    return returnObject;
}



- (void) print:(NSString*)s {
    
    if (_printController && [_printController respondsToSelector:@selector(print:)]) {
        [_printController print:s];
    }
    else {
        if (![s isKindOfClass:[NSString class]]) {
            s = [s description];
        }
        
        printf("%s\n", [s UTF8String]);
    }
}

+ (id) applicationOnPort:(NSString*)port {
    
    NSConnection *conn  = 0x00;
    NSUInteger tries    = 0;
    
    while (!conn && tries < 10) {
        
        conn = [NSConnection connectionWithRegisteredName:port host:nil];
        tries++;
        if (!conn) {
            debug(@"Sleeping, waiting for %@ to open", port);
            sleep(1);
        }
    }
    
    if (!conn) {
        NSBeep();
        NSLog(@"Could not find a JSTalk connection to %@", port);
    }
    
    return [conn rootProxy];
}

+ (id) application:(NSString*)app {
    
    NSString *appPath = [[NSWorkspace sharedWorkspace] fullPathForApplication:app];
    
    if (!appPath) {
        NSLog(@"Could not find application '%@'", app);
        return [NSNumber numberWithBool:NO];
    }
    
    NSBundle *appBundle = [NSBundle bundleWithPath:appPath];
    NSString *bundleId  = [appBundle bundleIdentifier];
    
    
    // make sure it's running
	NSArray *runningApps = [[[NSWorkspace sharedWorkspace] launchedApplications] valueForKey:@"NSApplicationBundleIdentifier"];
    
	if (![runningApps containsObject:bundleId]) {
        [[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:bundleId
                                                             options:NSWorkspaceLaunchWithoutActivation | NSWorkspaceLaunchAsync
                                      additionalEventParamDescriptor:nil
                                                    launchIdentifier:nil];
    }
    
    
    return [self applicationOnPort:[NSString stringWithFormat:@"%@.JSTalk", bundleId]];
}


+ (id) proxyForApp:(NSString*)app {
    return [self application:app];
}


@end
