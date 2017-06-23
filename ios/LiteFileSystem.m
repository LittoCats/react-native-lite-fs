//
//  LiteFileSystem.m
//  ios
//
//  Created by 程巍巍 on 5/9/17.
//  Copyright © 2017 程巍巍. All rights reserved.
//

#import "LiteFileSystem.h"
#import <UIKit/UIKit.h>

@implementation LiteFileSystem {
    __strong NSMutableArray* _fds;
}

RCT_EXPORT_MODULE(LiteFileSystem)

- (instancetype)init
{
    if (self = [super init]) {
        _fds = [NSMutableArray new];
    }
    return self;
}

- (NSFileHandle*)get:(int)descriptor {
    for (NSFileHandle* handle in _fds) {
        if (handle.fileDescriptor == descriptor) return handle;
    }
    return nil;
}

- (NSDictionary<NSString *, id> *)constantsToExport
{
    NSMutableDictionary* constants = [NSMutableDictionary new];
    constants[@"HOME"] = NSHomeDirectory();
    constants[@"TEMP"] = NSTemporaryDirectory();
    constants[@"UUID"] = ^{
        NSString* service = [[[NSBundle mainBundle] bundleIdentifier] stringByAppendingString:@".UUID"];
        NSString* uuid = CKPull(service);
        if (!uuid) {
            uuid = [NSUUID UUID].UUIDString;
            CKPush(service, uuid);
        }
        return uuid;
    }();

    constants[@"MODEL"] = [UIDevice currentDevice].model || @"unknown";

    return constants;
}

/*******************************************************************************

  Native.open     = (path: string)=> number // fd
  Native.tell     = (fd: number, location: number)=> number // current location
  Native.seek     = (fd: number, offset: number)=> number // current location
  Native.truncate = (fd: number, length: number)=> number // of file length
  Native.write    = (fd: number, hex: string, offset: number)=> number // of bytes has been written
  Native.read     = (fd: number, length: number)=> string // encoded hex
  Native.close    = (fd: number)=> undefined

  Native.exists   = (file: string)=> number // 0 not exists, 1 directory, 2 regular file
  Native.remove   = (file: string)=> undefined
  Native.move     = (file: string)=> undefined
  Native.copy     = (file: string)=> undefined
  Native.readir   = (file: string)=> Array<string>
  Native.touch    = (file: string)=> undefined
  Native.mkdir    = (file: stirng)=> undefined
  Native.stat     = (file: stat)=> Object<{path: string, length: number, ctime: number, mtime: number, flag: number}>

******************************************************************************/



#define EXPORT_METHOD(...) RCT_EXPORT_METHOD(__VA_ARGS__ resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

//Native.open     = (path: string)=> number // fd
EXPORT_METHOD(open:(NSString*)path) {
    int descriptor = open(path.UTF8String, O_RDWR);
    if (!descriptor) {
        reject([NSString stringWithFormat:@"%i", errno], @"open faild", nil);
    }
    NSFileHandle* handle = [[NSFileHandle alloc] initWithFileDescriptor:descriptor closeOnDealloc:true];
    [_fds addObject:handle];
    resolve(@(descriptor));
}

EXPORT_METHOD(close:(NSInteger)fd) {
    NSFileHandle* handle = [self get:fd];
    if (handle) [_fds removeObject:handle];
    resolve(nil);
}

EXPORT_METHOD(tell:(NSInteger)fd) {
    NSFileHandle* handle = [self get:fd];
    resolve(@(handle.offsetInFile));
}

EXPORT_METHOD(seek:(NSInteger)fd :(NSUInteger)offset) {
    NSFileHandle* handle = [self get:fd];
    [handle seekToFileOffset:offset];
    resolve(@(handle.offsetInFile));
}

//Native.truncate = (file: string, length: number)=> number // of file length
EXPORT_METHOD(truncate:(NSInteger)fd :(NSUInteger)length) {
    NSFileHandle* handle = [self get:fd];
    [handle truncateFileAtOffset:length];
    resolve(@(length));
}

//Native.read     = (file: string, length: number)=> string // encoded hex
static const char* HexTable = "0123456789abcdef";
EXPORT_METHOD(read:(NSInteger)fd :(NSUInteger)length) {
    NSFileHandle* handle = [self get:fd];
    NSData* data = [handle readDataOfLength:length];
    uint8_t* buffer = data.bytes;

    NSMutableString* mstr = [[NSMutableString alloc] initWithCapacity:length*2];
    int i = 0;
    while (i < data.length) {
        uint8_t code = buffer[i++];
        [mstr appendFormat:@"%c%c", HexTable[(code >> 4) & 0xf], HexTable[code & 0xf]];
    }

    resolve(mstr);
}

//Native.write    = (file: string, hex: string, offset: number)=> number // of bytes has been written
static const uint8_t HexDetable[] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6,7,8,9,0,0,0,0,0,0,0,10,11,12,13,14,15,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,10,11,12,13,14,15};

EXPORT_METHOD(write:(NSInteger)fd :(NSString*)hex) {

    uint8_t* buffer = malloc(hex.length/2);
    int i = 0;
    while (i < hex.length) {
        int h = HexDetable[[hex characterAtIndex:i++]];
        int l = HexDetable[[hex characterAtIndex:i++]];
        buffer[i/2-1] = ((h << 4) & 0xf0) | (l & 0xf);
    }

    NSFileHandle* handle = [self get:fd];
    [handle writeData:[NSData dataWithBytesNoCopy:buffer length:hex.length/2 freeWhenDone:true]];
    [handle synchronizeFile];

    resolve(@(hex.length/2));
}


EXPORT_METHOD(stat:(NSString*)path) {
    NSError* error;
    NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    if (error) reject(@(error.code).description, error.domain, error);
    else {
        NSMutableDictionary* result = [NSMutableDictionary new];
        result[@"type"] = [NSFileTypeRegular isEqualToString:attributes[NSFileType]] ? @(2) : [NSFileTypeDirectory isEqualToString:attributes[NSFileType]] ? @(1) : @(-1);
        result[@"length"] = attributes[NSFileSize];
        result[@"ctime"] = @([attributes[NSFileCreationDate] timeIntervalSince1970]);
        result[@"mtime"] = @([attributes[NSFileModificationDate] timeIntervalSince1970]);

        resolve(result);
    };
}

EXPORT_METHOD(exists:(NSString*)path) {
    BOOL isDirectory = false;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
    resolve(@(!exists ? 0 : isDirectory ? 1 : 2));
}

//Native.readir   = (file: string)=> Array<string>
EXPORT_METHOD(readir:(NSString*)path) {
    NSError* error;
    NSArray* items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    if (error) reject(@(error.code).description, error.domain, error);
    else resolve(items ? items : @[]);
}

//Native.move     = (file: string)=> undefined
EXPORT_METHOD(move:(NSString*)src :(NSString*)to) {
    NSError* error;
    BOOL status = [[NSFileManager defaultManager] moveItemAtPath:src toPath:to error:&error];
    if (error) reject(@(error.code).description, error.domain, error);
    else resolve(@(status));
}

//Native.remove   = (file: string)=> undefined
EXPORT_METHOD(remove:(NSString*)path) {
    NSError* error;
    BOOL status = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if (error) reject(@(error.code).description, error.domain, error);
    else resolve(@(status));
}

//Native.copy     = (file: string)=> undefined
EXPORT_METHOD(copy:(NSString*)src :(NSString*)to) {
    NSError* error;
    BOOL status = [[NSFileManager defaultManager] copyItemAtPath:src toPath:to error:&error];
    if (error) reject(@(error.code).description, error.domain, error);
    else resolve(@(status));
}

//Native.touch    = (file: string)=> undefined
EXPORT_METHOD(touch:(NSString*)src) {
    NSError* error;
    BOOL status = [[NSFileManager defaultManager] createFileAtPath:src contents:nil attributes:nil];
    if (error) reject(@(error.code).description, error.domain, error);
    else resolve(@(status));
}
//Native.mkdir    = (file: stirng)=> undefined
EXPORT_METHOD(mkdir:(NSString*)src) {
    NSError* error;
    BOOL status = [[NSFileManager defaultManager] createDirectoryAtPath:src withIntermediateDirectories:false attributes:nil error:nil];
    if (error) reject(@(error.code).description, error.domain, error);
    else resolve(@(status));
}

/******************************************************************************************************************************/

static void CKPush(NSString* service, id data) {
    NSMutableDictionary* query = CKQuery(service);
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    NSLog(@"CKPush 1: %i", status);
    [query setObject:[NSKeyedArchiver archivedDataWithRootObject:data] forKey:kSecValueData];
    status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    NSLog(@"CKPush 2: %i", status);
}

static id CKPull(NSString* service) {
    id data = nil;
    NSMutableDictionary* query = CKQuery(service);
    [query setObject:(id)kCFBooleanTrue forKey:(__bridge_transfer id)kSecReturnData];
    [query setObject:(__bridge_transfer id)kSecMatchLimitOne forKey:(__bridge_transfer id)kSecMatchLimit];
    CFDataRef keyData = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&keyData);
    if (status == noErr) {
        @try {
            data = [NSKeyedUnarchiver unarchiveObjectWithData:(__bridge_transfer NSData *)keyData];
        } @catch (NSException *e) {
            NSLog(@"Unarchive of %@ failed: %@", service, e);
        } @finally {
        }
    }

    return data;
}

static void CKDelete(NSString* service) {
    NSMutableDictionary* query = CKQuery(service);
}

static NSMutableDictionary* CKQuery(NSString* service) {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            (__bridge_transfer id)kSecClassGenericPassword,(__bridge_transfer id)kSecClass,
            service, (__bridge_transfer id)kSecAttrService,
            service, (__bridge_transfer id)kSecAttrAccount,
            (__bridge_transfer id)kSecAttrAccessibleAfterFirstUnlock,(__bridge_transfer id)kSecAttrAccessible,
            nil];
}

/******************************************************************************************************************************/

@end
