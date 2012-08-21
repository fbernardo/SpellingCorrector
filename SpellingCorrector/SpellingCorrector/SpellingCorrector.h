//
// Created by fbernardo on 8/20/12.
//
// Simple corrector totally based on http://norvig.com/spell-correct.html
//


#import <Foundation/Foundation.h>

typedef void (^SpellingCorrectorCompletionBlock)(BOOL);

@interface SpellingCorrector : NSObject

//Init with a big text file
- (id)initWithWordsFile:(NSString *)path;

//Non-blocking method to parse the words file,
//the completion block might be executed in the calling thread if we have cache
- (void)parseFile:(SpellingCorrectorCompletionBlock)completionBlock invalidateCache:(BOOL)invalidateCache;

//Will return the most likely suggestions to the given word
- (NSArray *)correctString:(NSString *)string;
@end