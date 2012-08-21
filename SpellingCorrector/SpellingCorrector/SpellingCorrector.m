//
// Created by fbernardo on 8/20/12.
//
//


#import "SpellingCorrector.h"

#define kSpellingCorrectorBufferSize 2048
#define kSpellingCorrectorCacheFileName @"spellingCorrector.cache"

@interface SpellingCorrector ()
@property (nonatomic, retain) NSString *textFilePath;
@property (nonatomic, retain) NSCountedSet *countedSet;
@property (nonatomic, retain) NSLock *countedSetLock;
@end

@implementation SpellingCorrector
@synthesize textFilePath = _textFilePath;
@synthesize countedSet = _countedSet;
@synthesize countedSetLock = _countedSetLock;


#pragma mark - Init/Dealloc

- (id)initWithWordsFile:(NSString *)path {
    if (!path) {
        [NSException raise:NSInvalidArgumentException format:@"path is nil"];
    }

    self = [super init];
    if (self) {
        self.countedSet = [NSCountedSet set];
        self.countedSetLock = [[NSLock alloc] init];
        self.textFilePath = path;
    }
    return self;
}

#pragma mark - Public Methods

- (void)parseFile:(SpellingCorrectorCompletionBlock)completionBlock invalidateCache:(BOOL)invalidateCache {
    NSArray *cacheDirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDir = [cacheDirs objectAtIndex:0];
    NSString *cachePath = [cacheDir stringByAppendingPathComponent:kSpellingCorrectorCacheFileName];

    //If we already have the file on cache
    if (!invalidateCache && [[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        [self.countedSetLock lock];
        self.countedSet = [NSUnarchiver unarchiveObjectWithFile:cachePath];
        [self.countedSetLock unlock];
        completionBlock(YES);
        return;
    }
    
    NSString *path = [self.textFilePath copy];
    unsigned long long int fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];

    
    dispatch_async([SpellingCorrector dispatchQueue], ^{
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
        
        while ([handle offsetInFile] < fileSize) {
            NSData *data;
            unsigned long long int remain = fileSize - [handle offsetInFile];

            @try {
                data = [handle readDataOfLength:MIN(kSpellingCorrectorBufferSize, remain)];
            } @catch (NSException *exception) {
                completionBlock(NO);
                [handle closeFile];
                return;
            }
            
            NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSArray *stringComponents = [string componentsSeparatedByCharactersInSet:[[NSCharacterSet letterCharacterSet] invertedSet]];

            int numberOfComponents = [stringComponents count];
            if (kSpellingCorrectorBufferSize < remain) {
                //We're not at EOF yet
                numberOfComponents--;
                [handle seekToFileOffset:[handle offsetInFile]-[[stringComponents lastObject] length]];
            }

            NSArray *words = [stringComponents subarrayWithRange:NSMakeRange(0, numberOfComponents)];

            for (__strong NSString *word in words) {
                NSString *a = [word copy];
                word = [word lowercaseString];
                word = [word decomposedStringWithCanonicalMapping];
                word = [[word componentsSeparatedByCharactersInSet:[[NSCharacterSet letterCharacterSet] invertedSet]] componentsJoinedByString:@""];
                if (word && [word length] > 0) {
                    [self incrementWordCount:word];
                }
            }
        }

        [handle closeFile];
        [self.countedSetLock lock];
        [NSArchiver archiveRootObject:self.countedSet toFile:cachePath];
        [self.countedSetLock unlock];

        completionBlock(YES);

    });
}

- (NSArray *)correctString:(NSString *)string {
    if ([self countForWord:string] > 1)
        return nil;


    //all 1 edit away words
    NSSet *edit1Words = [self possibleEditsForWord:string filterWords:YES];
    if ([edit1Words count]>0) return [edit1Words allObjects];

    //all 2 edit away words
    edit1Words = [self possibleEditsForWord:string filterWords:NO];
    NSSet *edit2Words = [NSSet set];
    for (NSString *word in edit1Words) {
        edit2Words = [edit2Words setByAddingObjectsFromSet:[self possibleEditsForWord:word filterWords:YES]];
    }

    if ([edit2Words count]>0) return [edit2Words allObjects];
    return nil;
}

#pragma mark - Private Methods

- (NSSet *)possibleEditsForWord:(NSString *)word filterWords:(BOOL)shouldFilter {

    NSUInteger wordLength = [word length];
    NSMutableSet *edits = [NSMutableSet setWithCapacity:54 * wordLength + 25];

    for (NSUInteger i = 0; i < wordLength; i++) {
        NSString *firstHalf = [word substringWithRange:NSMakeRange(0, i)];
        NSString *secondHalf = [word substringWithRange:NSMakeRange(i, wordLength-i)];

        NSString *secondHalfSubstringFrom1 = [secondHalf substringFromIndex:1];

        if ([secondHalf length] > 0) {
            //delete: a + b[1:]            
            NSString *possibleWord = [firstHalf stringByAppendingString:secondHalfSubstringFrom1];
            if (!shouldFilter || [self countForWord:possibleWord] > 0)
                [edits addObject:possibleWord];
        }

        if ([secondHalf length] > 1) {
            //transposition: a + b[1] + b[0] + b[2:]

            NSString *secondHalfSubstringFrom2 = [secondHalf substringFromIndex:2];
            NSString *possibleWord = [firstHalf stringByAppendingFormat:@"%C%C%@",
                                                                        [secondHalf characterAtIndex:1],
                                                                        [secondHalf characterAtIndex:0],
                                                                        secondHalfSubstringFrom2];
            if (!shouldFilter || [self countForWord:possibleWord] > 0)
                [edits addObject:possibleWord];
        }



        //inserts: a + c + b
        for (unichar c = 'a'; c <= 'z'; c++) {
            if ([secondHalf length] > 0) {
                //replaces: a + c + b[1:]
                NSString *possibleWord = [firstHalf stringByAppendingFormat:@"%C%@", c, secondHalfSubstringFrom1];

                if (!shouldFilter || [self countForWord:possibleWord] > 0) {
                    [edits addObject:possibleWord];
                }
            }
            NSString *possibleWord = [firstHalf stringByAppendingFormat:@"%C%@", c, secondHalf];

            if (!shouldFilter || [self countForWord:possibleWord] > 0) {
                [edits addObject:possibleWord];
            }
        }
    }
    return edits;
}

- (void)incrementWordCount:(NSString *)word {
    [self.countedSetLock lock];
    {
        [self.countedSet addObject:word];
    }
    [self.countedSetLock unlock];
}

- (NSUInteger)countForWord:(NSString *)word {
    NSUInteger count = 0;
    [self.countedSetLock lock];
    {
        count = [self.countedSet countForObject:word];
    }
    [self.countedSetLock unlock];
    return count;
}

+ (dispatch_queue_t)dispatchQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t  once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("SpellingCorrectorDispatchQueue", NULL);
    });
    return queue;
}

@end