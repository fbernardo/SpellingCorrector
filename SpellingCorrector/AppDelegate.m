//
//  AppDelegate.m
//  SpellingCorrector
//
//  Created by Fábio Bernardo on 08/20/12.
//

#import "AppDelegate.h"
#import "SpellingCorrector.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSDictionary *tests = @{
        @"forbiden" : @"forbidden", 
        @"deciscions": @"decisions", 
        @"descisions" : @"decisions", 
        @"supposidly" : @"supposedly", 
        @"embelishing" : @"embellishing", 
        @"tha" : @"the"
    };

    SpellingCorrector *corrector = [[SpellingCorrector alloc] initWithWordsFilePath:[[NSBundle mainBundle] pathForResource:@"big" ofType:@"txt"]];
    [corrector parseFile:^(BOOL success){
        for (NSString *key in tests) {
            NSArray *array = [corrector correctString:key];
            BOOL s = [array containsObject:tests[key]];
            NSLog(@"SUCCESS: %@ | Word: %@ | Suggestions: %@", s ? @"YES" : @"NO", key, array);
        }
    } invalidateCache:NO];


}

@end