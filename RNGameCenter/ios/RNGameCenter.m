//
//  RNGameCenter.m
//  StockShot
//
//  Created by vyga on 9/18/17.
//  Copyright © 2017 Facebook. All rights reserved.
//

#import "RNGameCenter.h"
#import <React/RCTConvert.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>

// Global Defaults
NSString *_leaderboardIdentifier;
NSString *_achievementIdentifier;
NSString *_playerId;
BOOL _initCallHasCompleted = NO;

static RNGameCenter *SharedInstance = nil;
// static NSString *scoresArchiveKey = @"Scores";
// static NSString *achievementsArchiveKey = @"Achievements";
// static BOOL isGameCenterAvailable()
//{
//  // Check for presence of GKLocalPlayer API.
//  Class gcClass = (NSClassFromString(@"GKLocalPlayer"));
//
//  // The device must be running running iOS 4.1 or later.
//  NSString *reqSysVer = @"4.1";
//  NSString *currSysVer = [[UIDevice currentDevice] systemVersion];
//  BOOL osVersionSupported = ([currSysVer compare:reqSysVer
//  options:NSNumericSearch] != NSOrderedAscending);
//
//  return (gcClass && osVersionSupported);
//}

@interface RNGameCenter ()

@property(nonatomic, strong) GKGameCenterViewController *gkView;
@property(nonatomic, strong) UIViewController *reactNativeViewController;
@property(nonatomic, strong) NSNumber *_currentAdditionCounter;
@end

@implementation RNGameCenter

bool hasListeners;
UIViewController* storedGCViewController;
NSError* _storedInitError;
RCTPromiseResolveBlock _storedResolve;
RCTPromiseRejectBlock _storedReject;


- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"onAuthenticate"];
}

// Will be called when this module's first listener is added.
-(void)startObserving {
    hasListeners = YES;
}

// Will be called when this module's last listener is removed, or on dealloc.
-(void)stopObserving {
    hasListeners = NO;
}

- (void)sendAuthenticateEvent:(id)error isInitial:(bool)isInitial isAuthenticated:(bool)isAuthenticated {
    if (hasListeners) {
        [self sendEventWithName:@"onAuthenticate"
                           body:@{@"isAuthenticated": @(isAuthenticated),
                                  @"isInitial": @(isInitial)}];
    }
}


- (void)presentViewController:(RCTPromiseResolveBlock)resolve
                               rejecter: (RCTPromiseRejectBlock)reject {
    UIViewController *rnView =
    [UIApplication sharedApplication].keyWindow.rootViewController;
    
    // Note that if the user just cancels the view controller, then the promise
    // will never be called, because our authenticate method is never called by
    // GameKit. The user has to be aware of this.
    //
    // Recommeded usage would use the onAuthenticate event.
    _storedReject = reject;
    _storedResolve = resolve;
    [rnView presentViewController:storedGCViewController
                         animated:YES
                       completion:nil];
}

- (void)handleGameKitAuthenticate:(UIViewController*)gcViewController error:(NSError*)error {
    
    // There are more error codes that we might want to pay attention to:
    // GKErrorCancelled - if the user presses CANCEL on the view controller; if user has cancelled more than 3 times, you
    //    get this error directly without ever being given a view controller.
    if (error != nil) {
        printf("Error code is: %d", (int)error.code);
    }
    
    bool isThisFirstResponse = _initCallHasCompleted == NO;
    _initCallHasCompleted = YES;
    
    // We will always trigger an onAuthenticate() event, but is there a promise that
    // we have to fullfill?  A call to init() wants a response from us, as those a
    // call to authenticate().
    RCTPromiseResolveBlock resolveToCall;
    RCTPromiseRejectBlock rejectToCall;
    bool resolvePromise = NO;
    if (_storedResolve) {
        resolveToCall = _storedResolve;
        rejectToCall = _storedReject;
        _storedResolve = nil;
        _storedReject = nil;
        resolvePromise = YES;
    }
    
    // Handle errors.
    if (error.code == GKErrorCancelled) {
        rejectToCall(@"Error", @"cancelled", error);
        return;
    }
    
    // The following errors we only expect those on the very first callback.
    // We then store them for the future so we can fail any future calls.
    if (error.code == GKErrorGameUnrecognized) {
        if (isThisFirstResponse) {
            _storedInitError = error;
            rejectToCall(@"Error", @"game-unrecognized", error);
        } else {
            assert("authenticateHandler should not be called multiple times with this error");
        }
        return;
    }
    
    if (error.code == GKErrorNotSupported) {
        if (isThisFirstResponse) {
            _storedInitError = error;
            rejectToCall(@"Error", @"not-supported", error);
        } else {
            assert("authenticateHandler should not be called multiple times with this error");
        }
        return;
    }
    
    // GameKit gives us as view controller to do the login. Means we are not logged in.
    if (gcViewController != nil) {
        
        // Always store it for later
        storedGCViewController = gcViewController;
        
        // If there is a promise for us to fullfill
        if (resolvePromise) {
            resolveToCall(@{@"isAuthenticated": @NO});
        }
        
        // Always trigger an event
        [self sendAuthenticateEvent:[NSNull null] isInitial:isThisFirstResponse isAuthenticated:NO];
        
    }
    
    // GameKit tells us the result of the "login view controller", or updates us if
    // the app returns from the background.
    else if ([GKLocalPlayer localPlayer].isAuthenticated) {
        
        // Fullfill any promises
        if (resolvePromise) {
            resolveToCall(@{@"isAuthenticated": @YES});
        }
        
        // Always trigger an event
        [self sendAuthenticateEvent:[NSNull null] isInitial:isThisFirstResponse isAuthenticated:YES];
    }
    
    // GameKit tells us the result of the "login view controller", or updates us if
    // the app returns from the background.
    else {
        // Fullfill any promises
        if (resolvePromise) {
            resolveToCall(@{@"isAuthenticated": @NO});
        }
        
        // Always trigger an event
        [self sendAuthenticateEvent:[NSNull null] isInitial:isThisFirstResponse isAuthenticated:NO];
    }
}


RCT_EXPORT_MODULE()

/* -----------------------------------------------------------------------------------------------------------------------------------------
 Init Game Center
 https://developer.apple.com/documentation/gamekit/gklocalplayer/1515399-authenticatehandler
 -----------------------------------------------------------------------------------------------------------------------------------------*/

RCT_EXPORT_METHOD(init: (RCTPromiseResolveBlock)resolve
                  rejecter: (RCTPromiseRejectBlock)reject)
{
    GKLocalPlayer *localPlayerTemp = [GKLocalPlayer localPlayer];
    // If we already assigned an authenticate handler, do not do so again.
    // If the user calls init() a second time before the first one completed,
    // they would receive a "logged out" state. Note that if we checked
    // _initCallHasCompleted here, the second call might simply not return at all.
    if (localPlayerTemp.authenticateHandler) {
       if (_storedInitError) {
          
           // Is this right? Or can we make authenticateHandler run again and
           // see if the game is *now* recgonized?
           if (_storedInitError.code == GKErrorGameUnrecognized) {
               reject(@"Error", @"game-unrecognized", _storedInitError);
               return;
           }
           if (_storedInitError.code == GKErrorNotSupported) {
               reject(@"Error", @"not-supported", _storedInitError);
               return;
           }
       }
      
       resolve(@{@"isAuthenticated": @(localPlayerTemp.isAuthenticated)});
       [self sendAuthenticateEvent:[NSNull null] isInitial:NO isAuthenticated:localPlayerTemp.isAuthenticated];
   }

    // Setting the authenticateHandler will cause GameKit to check for an existing user,
    // showing a "Welcome back" message if found. The handler will then also be called
    // when the app returns from the background.
    //
    // By storing reject/resolve, they will be called once we get the result
    _storedReject = reject;
    _storedResolve = resolve;
    

    // NB: If we do not use a weak self here, what will happen is that the dealloc is
    // somehow delayed (I do not understand all the details), and a CTRL+R (RELOAD)
    // in react-native causes [self stopObserving] to be called by [EventEmitter dealloc]
    // *after* a addListener() call from JS causes [self startObserving] to be invoked.
    // Thus, disabling our listeners.
    //     __weak RNGameCenter *weakSelf = self;
    // localPlayer.authenticateHandler = ^(UIViewController *gcViewController,
    //                                     NSError *error)
    // {
    //     [weakSelf handleGameKitAuthenticate:gcViewController error:error];
    // };


    __weak GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
    __weak RNGameCenter *weakSelf = self;
    localPlayer.authenticateHandler = ^(UIViewController *gcAuthViewController,
                                        NSError *error) {
        if (gcAuthViewController != nil) {
            // Pause any activities that require user interaction, then present the
            // gcAuthViewController to the player.
        } else if (localPlayer.isAuthenticated) {
            // Player is signed in to Game Center. Get Firebase credentials from the
            // player's Game Center credentials (see below).
            // Get Firebase credentials from the player's Game Center credentials
            [FIRGameCenterAuthProvider getCredentialWithCompletion:^(FIRAuthCredential *credential,
                                                                    NSError *error) {
                // The credential can be used to sign in, or re-auth, or link or unlink.
                    if (error == nil) {
                        [[FIRAuth auth] signInWithCredential:credential
                            completion:^(FIRAuthDataResult *_Nullable user, NSError *_Nullable error) {
                        // If error is nil, player is signed in.
                        }];
                    }
                }];
        } else {
            // Error
        }
        // From forked version
        [weakSelf handleGameKitAuthenticate:gcAuthViewController error:error];
    };
};


RCT_EXPORT_METHOD(authenticate
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
    
    // If the player is already authenticated, we don't need to do anything.
    if (localPlayer.isAuthenticated) {
        [self sendAuthenticateEvent:[NSNull null] isInitial:NO isAuthenticated:YES];
        resolve(@{@"isAuthenticated": @YES});
        return;
    }
    
    // If init was not called, call init with a special option "show!"
    if (!_initCallHasCompleted) {
        [self init:^(id result)
         {
             NSDictionary *data = result;
             if ([data[@"isAuthenticated"] boolValue]) {
                 resolve(result);
             }
             else {
                 // At this point, if there is no controller, and since the user is not
                 // authenticated, we can assume that GameCenter is turned off.
                 if (!storedGCViewController) {
                     [self sendAuthenticateEvent:[NSNull null] isInitial:NO isAuthenticated:NO];
                     resolve(@{@"isAuthenticated": @NO, @"likelyReason": @"GameCenter is turned off in the settings"});
                     return;
                 }
                 
                 [self presentViewController:resolve rejecter:reject];
             }
         } rejecter:reject];
        return;
    }
    
    // So init() was already called...
    
    // If there was an initialiation error, raise it here.
    if (_storedInitError) {
        
        // Is this right? Or can we make authenticateHandler run again and
        // see if the game is *now* recgonized?
        if (_storedInitError.code == GKErrorGameUnrecognized) {
            reject(@"Error", @"game-unrecognized", _storedInitError);
            return;
        }
        if (_storedInitError.code == GKErrorNotSupported) {
            reject(@"Error", @"not-supported", _storedInitError);
            return;
        }
    }
    
    // At this point, if there is no controller, and since the user is not
    // authenticated, we can assume that GameCenter is turned off.
    //
    // This also happens if the user cancels a certain number of times:
    // https://stackoverflow.com/questions/18927723/reenabling-gamecenter-after-user-cancelled-3-times-ios7-only
    if (!storedGCViewController) {
        [self sendAuthenticateEvent:[NSNull null] isInitial:NO isAuthenticated:NO];
        resolve(@{@"isAuthenticated": @NO, @"likelyReason": @"GameCenter is turned off in the settings"});
        return;
    }
    
    // Otherwise, show the view controller given to us by a previous call to init().
    // Set things up such that the very next time promise the authenticated handler is called,
    // we return this promise??
    [self presentViewController:resolve rejecter:reject];
}



RCT_EXPORT_METHOD(setDefaultOptions
                  : (NSDictionary *)options)
{
    if (options[@"leaderboardIdentifier"])
        _leaderboardIdentifier = options[@"leaderboardIdentifier"];
    
    if (options[@"achievementIdentifier"])
        _achievementIdentifier = options[@"achievementIdentifier"];
    
}



/* -----------------------------------------------------------------------------------------------------------------------------------------
 Player
 -----------------------------------------------------------------------------------------------------------------------------------------*/


RCT_EXPORT_METHOD(generateIdentityVerificationSignature
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    GKLocalPlayer *localPlayer;
    @try {
        localPlayer = [GKLocalPlayer localPlayer];
        if (!localPlayer.isAuthenticated) {
            reject(@"Error", @"No user is authenticated", nil);
        }
    }
    @catch (NSError *e) {
        reject(@"Error", @"Error getting user", e);
    }

    [localPlayer generateIdentityVerificationSignatureWithCompletionHandler:^(
                     NSURL *publicKeyUrl, NSData *signature, NSData *salt,
                     uint64_t timestamp, NSError *error) {
      if (error) {
          reject(@"Error",
                 @"generateIdentityVerificationSignatureWithCompletionHandler "
                 @"failed",
                 error);
      }
      else {
          // package data to be sent to server for verification
          NSDictionary *params = @{
              @"publicKeyUrl" : publicKeyUrl.absoluteString,
              @"timestamp" : [NSString stringWithFormat:@"%llu", timestamp],
              @"signature" : [signature base64EncodedStringWithOptions:0],
              @"salt" : [salt base64EncodedStringWithOptions:0],
              @"playerID" : localPlayer.playerID,
              @"bundleID" : [[NSBundle mainBundle] bundleIdentifier]
          };

          resolve(params);
      }
    }];
}


RCT_EXPORT_METHOD(getPlayer
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    @try {
        GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
        if (localPlayer.isAuthenticated) {
            NSDictionary *gameCenterUser = @{
                @"alias" : localPlayer.alias,
                @"displayName" : localPlayer.displayName,
                @"playerID" : localPlayer.playerID
            };
            FIRUser *user = [FIRAuth auth].currentUser;
            if (user) {
                NSString *playerName = user.displayName;

                // The user's ID, unique to the Firebase project.
                // Do NOT use this value to authenticate with your backend server,
                // if you have one. Use getTokenWithCompletion:completion: instead.
                NSString *uid = user.uid;
                NSDictionary *firebaseUser = @{
                    @"firebaseUid" : user.uid,
                    @"gameCenterUser" : gameCenterUser
                };
                resolve(firebaseUser);
            }
        }
        else {
            resolve([NSNull null]);
        }
        
    }
    @catch (NSError *e) {
        reject(@"Error", @"Error getting user.", e);
    }
}

/* --------------loadLeaderboardPlayers--------------
 //let leaderboardIdentifier="high_scores"
 // let achievementIdentifier="pro_award"
 //let achievementIdentifier="novice_award"
 RCT_EXPORT_METHOD(loadLeaderboardPlayers:(RCTPromiseResolveBlock)resolve
 rejecter:(RCTPromiseRejectBlock)reject){
 NSArray *playersForIdentifiers=@[@"high_scores"];

 //  GKLocalPlayer *localPlayer =
 [GKLocalPlayer loadPlayersForIdentifiers:playersForIdentifiers
 withCompletionHandler:^(NSArray<GKPlayer *> * _Nullable players, NSError *
 _Nullable error) { NSLog(@"PLAYERRRS %@",players); if(error)return
 reject(@"Error",@"no users.", error); resolve(players);
 }];

 }

 */

/* --------------getPlayerImage--------------*/
//

RCT_EXPORT_METHOD(getPlayerImage
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    if (_initCallHasCompleted == NO) {
        reject(@"Error", @"init() method was not called", nil);
        return;
    }
    @try {

        GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];

        NSArray *paths = NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *path =
            [documentsDirectory stringByAppendingPathComponent:@"user.jpg"];

        // Check if the user photo is cached
        BOOL fileExists =
            [[NSFileManager defaultManager] fileExistsAtPath:path];

        if (fileExists) {
            // Return it if it does

            NSDictionary *json = @{@"image" : path};
            resolve(json);
        }
        else {
            // Else load it from the game center
            [localPlayer loadPhotoForSize:GKPhotoSizeSmall
                    withCompletionHandler:^(UIImage *photo, NSError *error) {
                      if (error != nil)
                          return reject(@"Error",
                                        @"Error fetching player image", error);

                      if (photo != nil) {
                          NSData *data = UIImageJPEGRepresentation(photo, 0.8);
                          [data writeToFile:path atomically:YES];
                          NSDictionary *json = @{@"image" : path};
                          resolve(json);
                      }
                      else {
                          //        NSMutableDictionary *json = @{@"image":nil};
                          NSMutableDictionary *json =
                              [NSMutableDictionary dictionary];
                          json[@"image"] = nil;
                          resolve(json);
                      }
                    }];
        }
    }
    @catch (NSError *e) {
        reject(@"Error", @"Error fetching player image", e);
    }
}

//
//
// RCT_EXPORT_METHOD(challengePlayers:(NSDictionary *)options
//                  resolve:(RCTPromiseResolveBlock)resolve
//                  rejecter:(RCTPromiseRejectBlock)reject){
////- (void)
///challengeViewController:(MyAchievementChallengeViewController*)controller
///wasDismissedWithChallenge:(BOOL)issued
//  @try {
//    NSArray *challengePlayerArray=options[@"players"];
//    resolve(@"Successfully opened achievements");
//  }
//  @catch (NSError * e) {
//    reject(@"Error",@"Error opening achievements.", e);
//  }
////
////  [self dismissViewControllerAnimated:YES completion:NULL];
////  if (issued)
////  {
////
////  }
//}
//
//
// RCT_EXPORT_METHOD(challengeWithScore:(int64_t)playerScore
//                  options:(NSDictionary *)options
//                  resolve:(RCTPromiseResolveBlock)resolve
//                  rejecter:(RCTPromiseRejectBlock)reject){
////  -(void) sendScoreChallengeToPlayers:(NSArray*)players
///withScore:(int64_t)score message:(NSString*)message {
//  NSString *message = options[@"message"];
//  //NSArray *players = options[@"players"];
//  NSMutableArray *players=@[@"G:8135064222"];
//
//  NSString *achievementId;
//  if(options[@"achievementIdentifier"])achievementId=options[@"achievementIdentifier"];
//    //1
//    GKScore *gkScore = [[GKScore alloc]
//    initWithLeaderboardIdentifier:achievementId]; gkScore.value = playerScore;
//
//    //2
//   UIViewController *rnView = [UIApplication
//   sharedApplication].keyWindow.rootViewController;
//    [gkScore issueChallengeToPlayers:players message:message];
//  GKGameCenterViewController *leaderboardController =
//  [[GKGameCenterViewController alloc] init];
////    [rnView presentViewController: leaderboardController animated: YES
///completion:nil];
//
//  [rnView presentViewController:gkScore animated:YES completion:nil];
//
//  //challengeComposeControllerWithMessage
////  }
//
//}
//
//
////-(void) findScoresOfFriendsToChallenge {
//  RCT_EXPORT_METHOD(findScoresOfFriendsToChallenge:(NSDictionary *)options
//                    resolve:(RCTPromiseResolveBlock)resolve
//                    rejecter:(RCTPromiseRejectBlock)reject){
//
//    // Get leaderboardIdentifier or use default leaderboardIdentifier
//    NSString *achievementId;
//    if(options[@"achievementIdentifier"])achievementId=options[@"achievementIdentifier"];
//    else achievementId=_achievementIdentifier;
//  GKLeaderboard *leaderboard = [[GKLeaderboard alloc] init];
//  leaderboard.identifier = achievementId;
//  leaderboard.playerScope = GKLeaderboardPlayerScopeFriendsOnly;
//  leaderboard.range = NSMakeRange(1, 100);
//  [leaderboard loadScoresWithCompletionHandler:^(NSArray *scores, NSError
//  *error) {
//    BOOL success = (error == nil);
//
//    if (success) {
////      if (!_includeLocalPlayerScore) {
////        NSMutableArray *friendsScores = [NSMutableArray array];
////        for (GKScore *score in scores) {
////          if (![score.playerID isEqualToString:[GKLocalPlayer
///localPlayer].playerID]) { /            [friendsScores addObject:score]; / }
////        }
////        scores = friendsScores;
//      resolve(scores);
//
//    }else{
//       reject(@"Error", @"Error scores",error);
//    }
//  }];
//}
//

/* -----------------------------------------------------------------------------------------------------------------------------------------
 Leaderboard
 -----------------------------------------------------------------------------------------------------------------------------------------*/

/* --------------openLeaderboardModal--------------*/
// RCT_EXPORT_METHOD(openLeaderboardModal:(NSString *)leaderboardIdentifier
RCT_EXPORT_METHOD(
    openLeaderboardModal
    : (NSDictionary *)options resolve
    : (RCTPromiseResolveBlock)resolve
        // RCT_EXPORT_METHOD(openLeaderboardModal:(RCTPromiseResolveBlock)resolve
        rejecter
    : (RCTPromiseRejectBlock)reject)
{

    if (_initCallHasCompleted == NO) {
        UIViewController *rnView =
            [UIApplication sharedApplication].keyWindow.rootViewController;
        UIAlertController *gameCenterIsUnavailablePopup = [UIAlertController
            alertControllerWithTitle:@"GameCenter is not available"
                             message:@"You must be logged in to Game Center!"
                      preferredStyle:UIAlertControllerStyleAlert];
        [gameCenterIsUnavailablePopup
            addAction:[UIAlertAction
                          actionWithTitle:@"Dismiss"
                                    style:UIAlertActionStyleCancel
                                  handler:^(UIAlertAction *action) {
                                    [gameCenterIsUnavailablePopup
                                        dismissViewControllerAnimated:YES
                                                           completion:nil];
                                  }]];

        [rnView presentViewController:gameCenterIsUnavailablePopup
                             animated:YES
                           completion:nil];
        reject(@"Error", @"init() method was not called", nil);
        return;
    }

    UIViewController *rnView =
        [UIApplication sharedApplication].keyWindow.rootViewController;
    GKGameCenterViewController *leaderboardController =
        [[GKGameCenterViewController alloc] init];
    NSString *leaderboardId;
    if (options[@"leaderboardIdentifier"])
        leaderboardId = options[@"leaderboardIdentifier"];
    else
        leaderboardId = _leaderboardIdentifier;
    if (leaderboardController != NULL) {
        leaderboardController.leaderboardIdentifier = leaderboardId;
        leaderboardController.viewState =
            GKGameCenterViewControllerStateLeaderboards;
        leaderboardController.gameCenterDelegate = self;
        [rnView presentViewController:leaderboardController
                             animated:YES
                           completion:nil];
        resolve(@"opened Leaderboard");
    }
}

/* --------------submitLeaderboardScore--------------*/

RCT_EXPORT_METHOD(submitLeaderboardScore
                  : (int64_t)score options
                  : (NSDictionary *)options resolve
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{

    if (_initCallHasCompleted == NO) {
        @try {
            //            UIViewController *rnView = [UIApplication
            //            sharedApplication].keyWindow.rootViewController;
            //            UIAlertController *gameCenterIsUnavailablePopup =
            //            [UIAlertController
            //                                                               alertControllerWithTitle:@"Game
            //                                                               Center
            //                                                               is
            //                                                               unavailable!"
            //                                                               message:@"You
            //                                                               must
            //                                                               be
            //                                                               logged
            //                                                               in
            //                                                               to
            //                                                               Game
            //                                                               Center!"
            //                                                               preferredStyle:UIAlertControllerStyleActionSheet];
            //            [gameCenterIsUnavailablePopup addAction:[UIAlertAction
            //            actionWithTitle:@"Dismiss"
            //                                                                             style:UIAlertActionStyleCancel
            //                                                                           handler:^(UIAlertAction *action) {
            //                                                                               [gameCenterIsUnavailablePopup dismissViewControllerAnimated:YES completion:nil];
            //                                                                           }]];
            //            [rnView
            //            presentViewController:gameCenterIsUnavailablePopup
            //            animated:YES completion:nil];
            reject(@"Error", @"init() method was not called", nil);
            return;
        }
        @catch (NSError *e) {
            reject(@"Error", @"Error submitting score.", e);
        }
    }

    @try {
        // Get leaderboardIdentifier or use default leaderboardIdentifier
        NSString *leaderboardId;
        if (options[@"leaderboardIdentifier"])
            leaderboardId = options[@"leaderboardIdentifier"];
        else
            leaderboardId = _leaderboardIdentifier;

        GKScore *scoreSubmitter =
            [[GKScore alloc] initWithLeaderboardIdentifier:leaderboardId];
        scoreSubmitter.value = score;
        scoreSubmitter.context = 0;

        [GKScore reportScores:@[ scoreSubmitter ]
            withCompletionHandler:^(NSError *error) {
              if (error) {
                  reject(@"Error", @"Error submitting score", error);
              }
              else {
                  resolve(@"Successfully submitted score");
              }
            }];
    }
    @catch (NSError *e) {
        reject(@"Error", @"Error submitting score.", e);
    }
}

/* --------------getLeaderboardPlayers--------------*/

RCT_EXPORT_METHOD(getLeaderboardPlayers
                  : (NSDictionary *)options resolve
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    if (_initCallHasCompleted == NO) {
        reject(@"Error", @"init() method was not called",
               nil);
        return;
    }
    @try {
        NSArray *playerIds = options[@"playerIds"];
        NSString *leaderboardId;
        if (options[@"leaderboardIdentifier"])
            leaderboardId = options[@"leaderboardIdentifier"];
        else
            leaderboardId = _leaderboardIdentifier;
        [GKPlayer
            loadPlayersForIdentifiers:playerIds
                withCompletionHandler:^(NSArray<GKPlayer *> *players,
                                        NSError *error) {
                  GKLeaderboard *query =
                      [[GKLeaderboard alloc] initWithPlayers:players];
                  [query setRange:NSMakeRange(1, 1)];
                  [query setIdentifier:leaderboardId];
                  [query setTimeScope:GKLeaderboardTimeScopeAllTime];
                  [query setPlayerScope:GKLeaderboardPlayerScopeGlobal];
                  if (query != nil) {
                      [query loadScoresWithCompletionHandler:^(NSArray *scores,
                                                               NSError *error) {
                        NSMutableArray<NSDictionary *> *returnInfo =
                            [[NSMutableArray alloc] init];
                        for (GKScore *score in scores) {
                            GKPlayer *player = score.player;
                            NSDictionary *returnScore = @{
                                @"rank" :
                                    [NSNumber numberWithInteger:score.rank],
                                @"value" :
                                    [NSNumber numberWithInteger:score.value],
                                @"displayName" : player.displayName,
                                @"alias" : player.alias,
                                @"playerID" : player.playerID,
                            };
                            [returnInfo addObject:returnScore];
                        }
                        NSArray *returnArray =
                            [NSArray arrayWithArray:returnInfo];
                        if (error != nil)
                            reject(@"Error", [error localizedDescription],
                                   error);
                        else
                            resolve(returnArray);
                      }];
                  }
                  else {
                      reject(@"Error", @"Error creating Leaderboard query",
                             nil);
                  }
                }];
    }
    @catch (NSError *e) {
        reject(@"Error", @"Error getting leaderboard players.", e);
    }
}

/* --------------getTopLeaderboardPlayers--------------*/
RCT_EXPORT_METHOD(getTopLeaderboardPlayers
                  : (NSDictionary *)options resolve
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    if (_initCallHasCompleted == NO) {
        reject(@"Error", @"init() method was not called",
               nil);
        return;
    }
    @try {
        NSInteger count = [options[@"count"] integerValue];
        NSString *leaderboardId;

        if (options[@"leaderboardIdentifier"])
            leaderboardId = options[@"leaderboardIdentifier"];
        else
            leaderboardId = _leaderboardIdentifier;

        GKLeaderboard *query = [[GKLeaderboard alloc] init];
        [query setRange:NSMakeRange(1, count)];
        [query setIdentifier:leaderboardId];
        [query setTimeScope:GKLeaderboardTimeScopeAllTime];
        [query setPlayerScope:GKLeaderboardPlayerScopeGlobal];
        if (query != nil) {
            [query loadScoresWithCompletionHandler:^(NSArray *scores,
                                                     NSError *error) {
              NSMutableArray<NSDictionary *> *returnInfo =
                  [[NSMutableArray alloc] init];
              for (GKScore *score in scores) {
                  GKPlayer *player = score.player;
                  NSDictionary *returnScore = @{
                      @"rank" : [NSNumber numberWithInteger:score.rank],
                      @"value" : [NSNumber numberWithInteger:score.value],
                      @"displayName" : player.displayName,
                      @"alias" : player.alias,
                      @"playerID" : player.playerID,
                  };
                  [returnInfo addObject:returnScore];
              }
              NSArray *returnArray = [NSArray arrayWithArray:returnInfo];
              if (error != nil)
                  reject(@"Error", [error localizedDescription], error);
              else
                  resolve(returnArray);
            }];
        }
        else {
            reject(@"Error", @"Error creating Leaderboard query", nil);
        }
    }
    @catch (NSError *e) {
        reject(@"Error", @"Error getting top leaderboard players.", e);
    }
}

/*
 -----------------------------------------------------------------------------------------------------------------------------------------
 Achievements
 -----------------------------------------------------------------------------------------------------------------------------------------
 */

/* --------------openAchievementModal--------------*/

RCT_EXPORT_METHOD(openAchievementModal
                  : (NSDictionary *)options resolve
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{

    if (_initCallHasCompleted == NO) {
        UIViewController *rnView =
            [UIApplication sharedApplication].keyWindow.rootViewController;
        UIAlertController *gameCenterIsUnavailablePopup = [UIAlertController
            alertControllerWithTitle:@"GameCenter not available"
                             message:@"You must be logged in to Game Center!"
                      preferredStyle:UIAlertControllerStyleActionSheet];
        [gameCenterIsUnavailablePopup
            addAction:[UIAlertAction
                          actionWithTitle:@"Dismiss"
                                    style:UIAlertActionStyleCancel
                                  handler:^(UIAlertAction *action) {
                                    [gameCenterIsUnavailablePopup
                                        dismissViewControllerAnimated:YES
                                                           completion:nil];
                                  }]];
        [rnView presentViewController:gameCenterIsUnavailablePopup
                             animated:YES
                           completion:nil];
        reject(@"Error", @"init() method was not called", nil);
        return;
    }

    @try {
        GKGameCenterViewController *gcViewController =
            [[GKGameCenterViewController alloc] init];
        UIViewController *rnView =
            [UIApplication sharedApplication].keyWindow.rootViewController;
        gcViewController.viewState =
            GKGameCenterViewControllerStateAchievements;
        // Get achievementIdentifier or use default achievementIdentifier
        NSString *achievementId;
        if (options[@"achievementIdentifier"])
            achievementId = options[@"achievementIdentifier"];
        else
            achievementId = _achievementIdentifier;
        gcViewController.leaderboardIdentifier = achievementId;
        // attaches to class to allow dismissal
        gcViewController.gameCenterDelegate = self;
        [rnView presentViewController:gcViewController
                             animated:YES
                           completion:nil];
        resolve(@"Successfully opened achievements");
    }
    @catch (NSError *e) {
        reject(@"Error", @"Error opening achievements.", e);
    }
};

/* --------------getAchievements--------------*/

RCT_EXPORT_METHOD(getAchievements
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{

    if (_initCallHasCompleted == NO) {

        reject(@"Error", @"init() method was not called", nil);
        return;
    }

    NSMutableArray *earntAchievements = [NSMutableArray array];
    [GKAchievement loadAchievementsWithCompletionHandler:^(
                       NSArray *achievements, NSError *error) {
      if (error == nil) {
          for (GKAchievement *achievement in achievements) {
              NSMutableDictionary *entry = [NSMutableDictionary dictionary];
              entry[@"identifier"] = achievement.identifier;
              entry[@"percentComplete"] =
                  [NSNumber numberWithDouble:achievement.percentComplete];
              entry[@"completed"] =
                  [NSNumber numberWithBool:achievement.completed];
              entry[@"lastReportedDate"] =
                  [NSNumber numberWithDouble:[achievement.lastReportedDate
                                                     timeIntervalSince1970] *
                                             1000];
              entry[@"showsCompletionBanner"] =
                  [NSNumber numberWithBool:achievement.showsCompletionBanner];
              //         entry[@"playerID"] = achievement.playerID;
              [earntAchievements addObject:entry];
          }
          resolve(earntAchievements);
      }
      else {
          reject(@"Error", @"Error getting achievements", error);
      }
    }];
}

/* --------------resetAchievements--------------*/
RCT_EXPORT_METHOD(resetAchievements
                  : (NSDictionary *)options resolve
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    if (_initCallHasCompleted == NO) {
        UIViewController *rnView =
            [UIApplication sharedApplication].keyWindow.rootViewController;
        UIAlertController *gameCenterIsUnavailablePopup = [UIAlertController
            alertControllerWithTitle:@"GameCenter not available"
                             message:@"You must be logged in to Game Center!"
                      preferredStyle:UIAlertControllerStyleActionSheet];
        [gameCenterIsUnavailablePopup
            addAction:[UIAlertAction
                          actionWithTitle:@"Dismiss"
                                    style:UIAlertActionStyleCancel
                                  handler:^(UIAlertAction *action) {
                                    [gameCenterIsUnavailablePopup
                                        dismissViewControllerAnimated:YES
                                                           completion:nil];
                                  }]];
        [rnView presentViewController:gameCenterIsUnavailablePopup
                             animated:YES
                           completion:nil];
        reject(@"Error", @"init() method was not called", nil);
        return;
    }
    // Clear all progress saved on Game Center.
    if (!options[@"hideAlert"]) {

        UIViewController *rnView =
            [UIApplication sharedApplication].keyWindow.rootViewController;

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Reset Achievements?"
                             message:@"Are you sure you want to reset your "
                                     @"achievements. This can not be undone."
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertController *yesAlert = [UIAlertController
            alertControllerWithTitle:@"Success!"
                             message:
                                 @"You successfully reset your achievements!"
                      preferredStyle:UIAlertControllerStyleActionSheet];
        [yesAlert
            addAction:[UIAlertAction
                          actionWithTitle:@"Cancel"
                                    style:UIAlertActionStyleCancel
                                  handler:^(UIAlertAction *action) {
                                    [yesAlert
                                        dismissViewControllerAnimated:YES
                                                           completion:nil];
                                  }]];

        UIAlertAction *yesButton = [UIAlertAction
            actionWithTitle:@"Reset"
                      style:UIAlertActionStyleDefault

                    handler:^(UIAlertAction *action) {
                      // Handle your yes please button action here
                      [GKAchievement resetAchievementsWithCompletionHandler:^(
                                         NSError *error) {
                        if (error != nil) {
                            reject(@ "Error", @ "Error resetting achievements",
                                   error);
                        }
                        else {
                            [rnView presentViewController:yesAlert
                                                 animated:YES
                                               completion:nil];
                            NSDictionary *json = @{
                                @"message" : @"User achievements not reset",
                                @"resetAchievements" : @true
                            };
                            resolve(json);
                        }
                      }];
                    }];

        UIAlertAction *noButton = [UIAlertAction
            actionWithTitle:@"No!"
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                      // Handle no, thanks button
                      NSDictionary *json = @{
                          @"message" : @"User achievements not reset",
                          @"resetAchievements" : @false
                      };
                      resolve(json);
                    }];

        [alert addAction:yesButton];
        [alert addAction:noButton];

        [rnView presentViewController:alert animated:YES completion:nil];
    }
    else {
        NSDictionary *json = @{
            @"message" : @"User achievements reset",
            @"resetAchievements" : @true
        };
        resolve(json);
    }
}

/* --------------submitAchievement--------------*/

RCT_EXPORT_METHOD(submitAchievementScore
                  : (NSDictionary *)options resolve
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    if (_initCallHasCompleted == NO) {
        //    UIViewController *rnView = [UIApplication
        //    sharedApplication].keyWindow.rootViewController; UIAlertController
        //    *gameCenterIsUnavailablePopup = [UIAlertController
        //                                                       alertControllerWithTitle:@"Game
        //                                                       Center is
        //                                                       unavailable!"
        //                                                       message:@"You
        //                                                       must be logged
        //                                                       in to Game
        //                                                       Center!"
        //                                                       preferredStyle:UIAlertControllerStyleActionSheet];
        //    [gameCenterIsUnavailablePopup addAction:[UIAlertAction
        //    actionWithTitle:@"Dismiss"
        //                                                                     style:UIAlertActionStyleCancel
        //                                                                   handler:^(UIAlertAction
        //                                                                   *action)
        //                                                                   {
        //                                                                     [gameCenterIsUnavailablePopup dismissViewControllerAnimated:YES completion:nil];
        //                                                                   }]];
        //    [rnView presentViewController:gameCenterIsUnavailablePopup
        //    animated:YES completion:nil];
        reject(@"Error", @"init() method was not called", nil);
        return;
    }
    @try {

        NSString *percent = [options objectForKey:@"percentComplete"];

        RCTLog(@"percent: %@", percent);
        float percentFloat = [percent floatValue];
        RCTLog(@"percentFloat: %f", percentFloat);
        NSString *achievementId;
        if (options[@"achievementIdentifier"])
            achievementId = options[@"achievementIdentifier"];
        else
            achievementId = _achievementIdentifier;
        //
        if (!achievementId)
            return reject(@"Error",
                          @"No Game Center `achievementIdentifier` passed and "
                          @"no default set",
                          nil);
        return;
        BOOL showsCompletionBanner = YES;
        if (options[@"hideCompletionBanner"])
            showsCompletionBanner = NO;
        NSLog(@"showsCompletionBanner %d", showsCompletionBanner);
        GKAchievement *achievement =
            [[GKAchievement alloc] initWithIdentifier:achievementId];
        if (achievement) {
            achievement.percentComplete = percentFloat;
            achievement.showsCompletionBanner = showsCompletionBanner;

            NSArray *achievements = [NSArray arrayWithObjects:achievement, nil];

            [GKAchievement reportAchievements:achievements
                        withCompletionHandler:^(NSError *error) {
                          if (error != nil) {
                              reject(@"Error",
                                     @"Game Center setting Achievement", error);
                          }
                          else {
                              // Achievement notification banners are broken on
                              // iOS 7 so we do it manually here if 100%:
                              if ([[[UIDevice currentDevice] systemVersion]
                                      floatValue] >= 7.0 &&
                                  [[[UIDevice currentDevice] systemVersion]
                                      floatValue] < 8.0 &&
                                  floorf(percentFloat) >= 100) {
                                  [GKNotificationBanner
                                      showBannerWithTitle:@"Achievement"
                                                  message:@"Completed!"
                                        completionHandler:^{
                                        }];
                              }

                              // RCTLog(@"achievements: %@",achievements);
                              NSLog(@"achievements: %@", achievements);
                              resolve(achievements);
                          }
                        }];
        }
    }
    @catch (NSError *e) {
        reject(@"Error", @"Error setting achievement.", e);
    }
}

RCT_EXPORT_METHOD(invite
                  : (NSDictionary *)options resolve
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    if (_initCallHasCompleted == NO) {
        UIViewController *rnView =
            [UIApplication sharedApplication].keyWindow.rootViewController;
        UIAlertController *gameCenterIsUnavailablePopup = [UIAlertController
            alertControllerWithTitle:@"GameCenter not available"
                             message:@"You must be logged in to Game Center!"
                      preferredStyle:UIAlertControllerStyleActionSheet];
        [gameCenterIsUnavailablePopup
            addAction:[UIAlertAction
                          actionWithTitle:@"Dismiss"
                                    style:UIAlertActionStyleCancel
                                  handler:^(UIAlertAction *action) {
                                    [gameCenterIsUnavailablePopup
                                        dismissViewControllerAnimated:YES
                                                           completion:nil];
                                  }]];
        [rnView presentViewController:gameCenterIsUnavailablePopup
                             animated:YES
                           completion:nil];
        reject(@"Error", @"init() method was not called", nil);
        return;
    }

    GKMatchRequest *request = [[GKMatchRequest alloc] init];
    request.minPlayers = 2;
    request.maxPlayers = 4;
    request.recipients = @[ @"G:8135064222" ];
    request.inviteMessage = @"Your Custom Invitation Message Here";
    request.recipientResponseHandler =
        ^(GKPlayer *player, GKInviteeResponse response) {
          resolve(player);
          //  [self updateUIForPlayer: player accepted: (response ==
          //  GKInviteeResponseAccepted)];
        };
}

RCT_EXPORT_METHOD(getPlayerFriends
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    resolve([GKLocalPlayer localPlayer].friends);
    //  [GKLocalPlayer loadPlayersForIdentifiers:players
    //                     withCompletionHandler:^(NSArray<GKPlayer *> *
    //                     _Nullable players, NSError * _Nullable error) {
    //                       if(error)return reject(@"Error", @"Error reporting
    //                       achievement",error); resolve(players);
    //                     }];
}
/*
 RCT_EXPORT_METHOD(challengeComposer:(int64_t) playerScore
 options:(NSDictionary *)options
 resolve:(RCTPromiseResolveBlock)resolve
 rejecter:(RCTPromiseRejectBlock)reject){

 GKLeaderboard *query = [[GKLeaderboard alloc] init];
 // Get achievementIdentifier or use default achievementIdentifier
 NSString *leaderboardId;
 if(options[@"leaderboardIdentifier"])leaderboardId=options[@"leaderboardIdentifier"];
 else leaderboardId=_leaderboardIdentifier;

 query.identifier = leaderboardId;
 query.playerScope = GKLeaderboardPlayerScopeFriendsOnly;
 query.range = NSMakeRange(1,100);
 [query loadScoresWithCompletionHandler:^(NSArray *scores, NSError *error) {
 NSPredicate *filter = [NSPredicate predicateWithFormat:@"value <
 %qi",playerScore]; NSArray *lesserScores = [scores
 filteredArrayUsingPredicate:filter];
 //      UIViewController *rnView = [UIApplication
 sharedApplication].keyWindow.rootViewController;
 // *rnView = [UIApplication sharedApplication].keyWindow.rootViewController;
 //      [self presentChallengeWithPreselectedScores: lesserScores];
 GKScore *gkScore = [[GKScore alloc]
 initWithLeaderboardIdentifier:leaderboardId]; gkScore.value = playerScore;
 NSString *message=@"hey fag, face off?";
 //NSArray *players=@[@"high_scores"];
 NSMutableArray *players=@[@"G:8135064222"];

 //      [gkScore issueChallengeToPlayers:players message:message];
 //      GKScore *gkScore = [[GKInvite alloc]
 initWithLeaderboardIdentifier:leaderboardId];

 [gkScore challengeComposeControllerWithMessage:message
 players:players
 //players:[GKLocalPlayer localPlayer].friends
 completionHandler:^(UIViewController * _Nonnull composeController, BOOL
 didIssueChallenge, NSArray<NSString *> * _Nullable sentPlayerIDs) { if (error)
 reject(@"Error", @"Error reporting achievement",error); else
 resolve(sentPlayerIDs);
 }];
 }];
 }*/
// Get achievementIdentifier or use default achievementIdentifier
//  NSString *achievementId;
//
//  if(options[@"achievementIdentifier"])achievementId=options[@"achievementIdentifier"];
//  else achievementId=_achievementIdentifier;
//
//  NSString *message=@"hey fag, face off?";
//  NSArray *players=@[@"high_scores"];
//  [self abc:@"Yoop"]

//    GKAchievement *achievement = [[GKAchievement alloc]
//    initWithIdentifier:@"MyGame.bossDefeated"]; achievement.percentComplete =
//    100.0; achievement.showsCompletionBanner = NO;
//
//    [achievement reportAchievements: [NSArray arrayWithObjects:achievement,
//    nil] WithCompletionHandler:NULL]; [self
//    performSegueWithIdentifier:@"achievementChallenge" sender:achievement];
//

//  [GKChallenge
//  loadReceivedChallengesWithCompletionHandler:^(NSArray<GKChallenge *> *
//  _Nullable challenges, NSError * _Nullable error) {
//    <#code#>
//  }];
//  UIViewController *rnView = [UIApplication
//  sharedApplication].keyWindow.rootViewController;
// *rnView = [UIApplication sharedApplication].keyWindow.rootViewController;
//  [UIViewController  challengeComposeControllerWithMessage:message
//  players:players
// completionHandler:^(NSError *error) {
//  if (error) reject(@"Error", @"Error reporting achievement",error);
//  else  resolve(@"opened challengeComposer!");
//}];
//

//
//- (void )prepareForSegue:(UIStoryboardSegue *)segue sender:(id)dsender
//{
//  if ([segue.identifier isEqualToString:@"achievementChallenge"])
//  {
////    MyAchievementChallengeViewController* challengeVC =
///(MyAchievementChallengeViewController*) segue.destinationViewController; /
///UIViewController *rnView = [UIApplication
///sharedApplication].keyWindow.rootViewController; /    [challengeVC
///performSegueWithIdentifier:@"startPlaying" sender:self];
//    //challengeVC.delegate = self;
//    //challengeVC.achievement = (GKAchievement*) sender;
//  }
//}
//
//- (void)
//challengeViewController:(MyAchievementChallengeViewController*)controller
//wasDismissedWithChallenge:(BOOL)issued
//{
//  [self dismissViewControllerAnimated:YES completion:NULL];
//  if (issued)
//  {
//    [controller.achievement issueChallengeToPlayers:controller.players
//    message:controller.message];
//  }
//}

RCT_EXPORT_METHOD(challengePlayersToCompleteAchievement
                  : (NSDictionary *)options resolve
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)
{
    if (_initCallHasCompleted == NO) {
        UIViewController *rnView =
            [UIApplication sharedApplication].keyWindow.rootViewController;
        UIAlertController *gameCenterIsUnavailablePopup = [UIAlertController
            alertControllerWithTitle:@"GameCenter is not available"
                             message:@"You must be logged in to Game Center!"
                      preferredStyle:UIAlertControllerStyleActionSheet];
        [gameCenterIsUnavailablePopup
            addAction:[UIAlertAction
                          actionWithTitle:@"Dismiss"
                                    style:UIAlertActionStyleCancel
                                  handler:^(UIAlertAction *action) {
                                    [gameCenterIsUnavailablePopup
                                        dismissViewControllerAnimated:YES
                                                           completion:nil];
                                  }]];
        [rnView presentViewController:gameCenterIsUnavailablePopup
                             animated:YES
                           completion:nil];
        reject(@"Error", @"init() method was not called", nil);
        return;
    }

    GKAchievement *achievement;
    [achievement selectChallengeablePlayers:[GKLocalPlayer localPlayer].friends
                      withCompletionHandler:^(NSArray *challengeablePlayers,
                                              NSError *error) {
                        if (challengeablePlayers) {
                            resolve(challengeablePlayers);
                            //      [self
                            //      presentChallengeWithPreselectedPlayers:
                            //      challengeablePlayers];
                        }
                      }];
}

/* issued when the player completed a challenge sent by a friend

 - (void)player:(GKPlayer *)player didCompleteChallenge:(GKChallenge *)challenge
 issuedByFriend:(GKPlayer *)friendPlayer{ NSLog(@"Challenge %@ sent by %@
 completed", challenge.description , friendPlayer.displayName);
 }
 // issued when a friend of the player completed a challenge sent by the player

 - (void)player:(GKPlayer *)player issuedChallengeWasCompleted:(GKChallenge
 *)challenge byFriend:(GKPlayer *)friendPlayer{ NSLog(@"Your friend %@ has
 successfully completed the %@ challenge", friendPlayer.displayName,
 challenge.description);
 }

 // issued when a player wants to play the challenge and has just started the
 game (from a notification)

 - (void)player:(GKPlayer *)player wantsToPlayChallenge:(GKChallenge
 *)challenge{
 //[self performSegueWithIdentifier:@"startPlaying" sender:self];

 UIViewController *rnView = [UIApplication
 sharedApplication].keyWindow.rootViewController; [rnView
 performSegueWithIdentifier:@"startPlaying" sender:self];
 }

 // issued when a player wants to play the challenge and is in the game (the
 game was running while the challenge was sent)


 - (void)player:(GKPlayer *)player didReceiveChallenge:(GKChallenge *)challenge{

 NSString *friendMsg = [[NSString alloc] initWithFormat:@"Your friend %@ has
 invited you to a challenge: %@", player.displayName, challenge.message];
 UIAlertView *theChallenge = [[UIAlertView alloc] initWithTitle:@"Want to take
 the challenge?" message:friendMsg delegate:self cancelButtonTitle:@"Challenge
 accepted" otherButtonTitles:@"No", nil];

 [theChallenge show];
 }




 - (void)alertView:(UIAlertView *)alertView
 clickedButtonAtIndex:(NSInteger)buttonIndex{
 //if (buttonIndex == 0)  [self
 performSegueWithIdentifier:@"startPlaying"sender:self]; if (buttonIndex == 0) {
 UIViewController *rnView = [UIApplication
 sharedApplication].keyWindow.rootViewController; [rnView
 performSegueWithIdentifier:@"startPlaying" sender:self];
 }
 }
 */
//-(void) submitAchievementScore:(NSString*)identifier
//percentComplete:(float)percent
//{
//  if (isGameCenterAvailable == NO)
//    return;
//
//  GKAchievement* achievement = [self getAchievement:identifier];
//  if (percent > achievement.percentComplete)
//  {
//    NSLog(@"new achievement %@ reported", achievement.identifier);
//    achievement.percentComplete = percent;
//    [achievement reportAchievementWithCompletionHandler:^(NSError* error) {
//      if (achievement.isCompleted) {
//        [delegate onReportAchievement:(GKAchievement*)achievement];
//      }
//    }];
//
//    [self saveAchievements];
//  }
//}
//- (NSString*)getGameCenterSavePath{
//  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
//  NSUserDomainMask, YES); return [NSString
//  stringWithFormat:@"%@/GameCenterSave.txt",[paths objectAtIndex:0]];
//}
//
//
//- (void)saveAchievements:(GKAchievement *)achievement
//{
//  NSString *savePath = [self getGameCenterSavePath];
//
//  // If achievements already exist, append the new achievement.
//  NSMutableArray *achievements = [[NSMutableArray alloc] init];//
//  autorelease]; NSMutableDictionary *dict; if([[NSFileManager defaultManager]
//  fileExistsAtPath:savePath]){
//    dict = [[NSMutableDictionary alloc] initWithContentsOfFile:savePath];//
//    autorelease];
//
//    NSData *data = [dict objectForKey:achievementsArchiveKey];
//    if(data) {
//      NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc]
//      initForReadingWithData:data]; achievements = [unarchiver
//      decodeObjectForKey:achievementsArchiveKey]; [unarchiver finishDecoding];
//      //[unarchiver release];
//      [dict removeObjectForKey:achievementsArchiveKey]; // remove it so we can
//      add it back again later
//    }
//  }else{
//    dict = [[NSMutableDictionary alloc] init];// autorelease];
//
//  }
//      NSLog(@"saveeee%@",dict);
//
//  [achievements addObject:achievement];
//
//  // The achievement has been added, now save the file again
//  NSMutableData *data = [NSMutableData data];
//  NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc]
//  initForWritingWithMutableData:data]; [archiver encodeObject:achievements
//  forKey:achievementsArchiveKey]; [archiver finishEncoding]; [dict
//  setObject:data forKey:achievementsArchiveKey]; [dict writeToFile:savePath
//  atomically:YES];
//  //[archiver release];
//}
//

// Enable the ability to close Achivments/Leaderboard Game Center Popup from
// React Native App
- (void)gameCenterViewControllerDidFinish:
    (GKGameCenterViewController *)viewController {
    [viewController dismissViewControllerAnimated:YES completion:nil];
}

// Enable the ability to close Achivments/Leaderboard Game Center Popup from
// React Native App
- (void)gameCenterViewControllerDidCancel:
    (GKGameCenterViewController *)gameCenterViewController {
    //- (void)gameCenterViewControllerDidCancel:(GKGameCenterViewController
    //*)viewController{
    [gameCenterViewController dismissViewControllerAnimated:YES completion:nil];
}

//-(void)updateAchievements{
//  NSString *achievementIdentifier;
//  float progressPercentage = 0.0;
//  BOOL progressInLevelAchievement = NO;
//
//  GKAchievement *levelAchievement = nil;
//  GKAchievement *scoreAchievement = nil;
//
//  if (_currentAdditionCounter == 0) {
//    if (_level <= 3) {
//      progressPercentage = _level * 100 / 3;
//      achievementIdentifier = @"Achievement_Level3";
//      progressInLevelAchievement = YES;
//    }
//    else if (_level < 6){
//      progressPercentage = _level * 100 / 5;
//      achievementIdentifier = @"Achievement_Level5Complete";
//      progressInLevelAchievement = YES;
//    }
//  }
//
//  if (progressInLevelAchievement) {
//    levelAchievement = [[GKAchievement alloc]
//    initWithIdentifier:achievementIdentifier];
//    levelAchievement.percentComplete = progressPercentage;
//  }
//
//
//  if (_score <= 50) {
//    progressPercentage = _score * 100 / 50;
//    achievementIdentifier = @"Achievement_50Points";
//  }
//  else if (_score <= 120){
//    progressPercentage = _score * 100 / 120;
//    achievementIdentifier = @"Achievement_120Points";
//  }
//  else{
//    progressPercentage = _score * 100 / 180;
//    achievementIdentifier = @"Achievement_180Points";
//  }
//
//  scoreAchievement = [[GKAchievement alloc]
//  initWithIdentifier:achievementIdentifier]; scoreAchievement.percentComplete
//  = progressPercentage;
//
//  NSArray *achievements = (progressInLevelAchievement) ? @[levelAchievement,
//  scoreAchievement] : @[scoreAchievement];
//
//  [GKAchievement reportAchievements:achievements
//  withCompletionHandler:^(NSError *error) {
//    if (error != nil) {
//      NSLog(@"%@", [error localizedDescription]);
//    }
//  }];
//}

//
//- (void)authenticateLocalPlayer
//{

//  [[GKLocalPlayer localPlayer] setAuthenticateHandler:^(UIViewController
//  *viewController, NSError *error) {
//
//    GKScore *score = [[GKScore alloc]
//    initWithLeaderboardIdentifier:@"scoreLeaderboard"]; [score
//    setValue:[[NSUserDefaults standardUserDefaults]
//    integerForKey:@"highScore"]];
//
//    [GKScore reportScores:@[score] withCompletionHandler:^(NSError *error) {
//      NSLog(@"Reporting Error: %@",error);
//    }];
//
//  }];
//}

/*
 https://github.com/garrettmac/react-native-tweet/blob/master/Tweet/ios/RNTweet.m
 */

/*
 //NSError *jsonError;
 //  NSDictionary *json = [NSJSONSerialization
 //                        JSONObjectWithData:localPlayer
 //                        options:0
 //                        error:&jsonError];
 //NSDictionary *json = @{@"localPlayer":localPlayer};



 NSString *leaderboardIdentifier = @"StockShotLeaderboard";*/
/*
 GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
 localPlayer.authenticateHandler = ^(UIViewController *viewController, NSError
 *error){ if (viewController != nil) { [self
 presentViewController:viewController animated:YES completion:nil];
 }
 else{
 if ([GKLocalPlayer localPlayer].authenticated) {
 _gameCenterEnabled = YES;

 // Get the default leaderboard identifier.
 [[GKLocalPlayer localPlayer]
 loadDefaultLeaderboardIdentifierWithCompletionHandler:^(NSString
 *leaderboardIdentifier, NSError *error) {

 if (error != nil) {
 NSLog(@"%@", [error localizedDescription]);
 }
 else{
 _leaderboardIdentifier = leaderboardIdentifier;
 }
 }];
 }

 else{
 _gameCenterEnabled = NO;
 }
 }
 };*/

/*



 -(void)gameCenterViewControllerDidFinish:(GKGameCenterViewController
 *)gameCenterViewController
 {
 [gameCenterViewController dismissViewControllerAnimated:YES completion:nil];
 }
 */

/*

 -(void)updateAchievements{
 NSString *achievementIdentifier;
 float progressPercentage = 0.0;
 BOOL progressInLevelAchievement = NO;

 GKAchievement *levelAchievement = nil;
 GKAchievement *scoreAchievement = nil;

 if (_currentAdditionCounter == 0) {
 if (_level <= 3) {
 progressPercentage = _level * 100 / 3;
 achievementIdentifier = @"Achievement_Level3";
 progressInLevelAchievement = YES;
 }
 else if (_level < 6){
 progressPercentage = _level * 100 / 5;
 achievementIdentifier = @"Achievement_Level5Complete";
 progressInLevelAchievement = YES;
 }
 }

 if (progressInLevelAchievement) {
 levelAchievement = [[GKAchievement alloc]
 initWithIdentifier:achievementIdentifier]; levelAchievement.percentComplete =
 progressPercentage;
 }


 if (_score <= 50) {
 progressPercentage = _score * 100 / 50;
 achievementIdentifier = @"Achievement_50Points";
 }
 else if (_score <= 120){
 progressPercentage = _score * 100 / 120;
 achievementIdentifier = @"Achievement_120Points";
 }
 else{
 progressPercentage = _score * 100 / 180;
 achievementIdentifier = @"Achievement_180Points";
 }

 scoreAchievement = [[GKAchievement alloc]
 initWithIdentifier:achievementIdentifier]; scoreAchievement.percentComplete =
 progressPercentage;

 NSArray *achievements = (progressInLevelAchievement) ? @[levelAchievement,
 scoreAchievement] : @[scoreAchievement];

 [GKAchievement reportAchievements:achievements withCompletionHandler:^(NSError
 *error) { if (error != nil) { NSLog(@"%@", [error localizedDescription]);
 }
 }];
 }
 */

/*

 -(void)updateAchievements{
 NSString *achievementIdentifier;
 float progressPercentage = 0.0;
 BOOL progressInLevelAchievement = NO;

 GKAchievement *levelAchievement = nil;
 GKAchievement *scoreAchievement = nil;

 if (_currentAdditionCounter == 0) {
 if (_level <= 3) {
 progressPercentage = _level * 100 / 3;
 achievementIdentifier = @"Achievement_Level3";
 progressInLevelAchievement = YES;
 }
 else if (_level < 6){
 progressPercentage = _level * 100 / 5;
 achievementIdentifier = @"Achievement_Level5Complete";
 progressInLevelAchievement = YES;
 }
 }

 if (progressInLevelAchievement) {
 levelAchievement = [[GKAchievement alloc]
 initWithIdentifier:achievementIdentifier]; levelAchievement.percentComplete =
 progressPercentage;
 }


 if (_score <= 50) {
 progressPercentage = _score * 100 / 50;
 achievementIdentifier = @"Achievement_50Points";
 }
 else if (_score <= 120){
 progressPercentage = _score * 100 / 120;
 achievementIdentifier = @"Achievement_120Points";
 }
 else{
 progressPercentage = _score * 100 / 180;
 achievementIdentifier = @"Achievement_180Points";
 }

 scoreAchievement = [[GKAchievement alloc]
 initWithIdentifier:achievementIdentifier]; scoreAchievement.percentComplete =
 progressPercentage;

 NSArray *achievements = (progressInLevelAchievement) ? @[levelAchievement,
 scoreAchievement] : @[scoreAchievement];

 [GKAchievement reportAchievements:achievements withCompletionHandler:^(NSError
 *error) { if (error != nil) { NSLog(@"%@", [error localizedDescription]);
 }
 }];
 }
 */

/*

 -(void)resetAchievements{
 [GKAchievement resetAchievementsWithCompletionHandler:^(NSError *error) {
 if (error != nil) {
 NSLog(@"%@", [error localizedDescription]);
 }
 }];
 }

 */

/*
 - (IBAction)showGCOptions:(id)sender {
 ...

 [_customActionSheet showInView:self.view
 withCompletionHandler:^(NSString *buttonTitle, NSInteger buttonIndex) {
 if ([buttonTitle isEqualToString:@"View Leaderboard"]) {
 ...
 }
 else if ([buttonTitle isEqualToString:@"View Achievements"]) {
 ...
 }
 else{
 [self resetAchievements];
 }
 }];
 ....
 }
 */

/*
 - (IBAction)showGCOptions:(id)sender {
 ...
 [_customActionSheet showInView:self.view
 withCompletionHandler:^(NSString *buttonTitle, NSInteger buttonIndex) {

 if ([buttonTitle isEqualToString:@"View Leaderboard"]) {
 [self showLeaderboardAndAchievements:YES];
 }
 else if ([buttonTitle isEqualToString:@"View Achievements"]) {
 [self showLeaderboardAndAchievements:NO];
 }
 else{

 }
 }];
 ...
 }*/
@end

/*



 #import "GameCenterPlugin.h"
 #import <Cordova/CDVViewController.h>

 #define SYSTEM_VERSION_LESS_THAN(v) ([[[UIDevice currentDevice] systemVersion]
 compare:v options:NSNumericSearch] == NSOrderedAscending)

 @interface GameCenterPlugin ()
 @property (nonatomic, retain) GKLeaderboardViewController
 *leaderboardController;
 @property (nonatomic, retain) GKAchievementViewController
 *achievementsController;
 @end

 @implementation GameCenterPlugin

 - (void)dealloc {
 self.leaderboardController = nil;
 self.achievementsController = nil;

 [super dealloc];
 }

 - (void)authenticateLocalPlayer:(CDVInvokedUrlCommand *)command {

 [self.commandDelegate runInBackground:^{

 if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
 [[GKLocalPlayer localPlayer] authenticateWithCompletionHandler:^(NSError
 *error) { if (error == nil) { CDVPluginResult *pluginResult = [CDVPluginResult
 resultWithStatus:CDVCommandStatus_OK]; [self.commandDelegate
 sendPluginResult:pluginResult callbackId:command.callbackId]; } else {
 CDVPluginResult *pluginResult = [CDVPluginResult
 resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error
 localizedDescription]]; [self.commandDelegate sendPluginResult:pluginResult
 callbackId:command.callbackId];
 }
 }];
 } else {
 [[GKLocalPlayer localPlayer] setAuthenticateHandler:^(UIViewController
 *viewcontroller, NSError *error) { CDVPluginResult *pluginResult;

 if ([GKLocalPlayer localPlayer].authenticated) {
 // Already authenticated
 pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
 [self.commandDelegate sendPluginResult:pluginResult
 callbackId:command.callbackId]; } else if (viewcontroller) {
 // Present the login view

 CDVViewController *cont = (CDVViewController *)[super viewController];
 [cont presentViewController:viewcontroller animated:YES completion:^{
 [self.webView
 stringByEvaluatingJavaScriptFromString:@"window.gameCenter._viewDidShow()"];
 }];

 } else {
 // Called the second time with result
 if (error == nil) {
 pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
 } else {
 pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
 messageAsString:[error localizedDescription]];
 }
 [self.commandDelegate sendPluginResult:pluginResult
 callbackId:command.callbackId];

 }

 }];
 }
 }];
 }

 - (void)reportScore:(CDVInvokedUrlCommand *)command {

 [self.commandDelegate runInBackground:^{
 NSString *category = (NSString *) [command.arguments objectAtIndex:0];
 int64_t score = [[command.arguments objectAtIndex:1] integerValue];

 GKScore *scoreReporter = [[[GKScore alloc] initWithCategory:category]
 autorelease]; scoreReporter.value = score;

 [scoreReporter reportScoreWithCompletionHandler:^(NSError *error) {
 CDVPluginResult *pluginResult;
 if (!error) {
 pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
 } else {
 pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
 messageAsString:[error localizedDescription]];
 }
 [self.commandDelegate sendPluginResult:pluginResult
 callbackId:command.callbackId];
 }];
 }];
 }

 - (void)openLeaderboardModal:(CDVInvokedUrlCommand *)command {
 [self.commandDelegate runInBackground:^{
 if ( self.leaderboardController == nil ) {
 self.leaderboardController = [[GKLeaderboardViewController alloc] init];
 self.leaderboardController.leaderboardDelegate = self;
 }

 self.leaderboardController.category = (NSString *) [command.arguments
 objectAtIndex:0]; CDVViewController *cont = (CDVViewController *)[super
 viewController]; [cont presentViewController:self.leaderboardController
 animated:YES completion:^{ [self.webView
 stringByEvaluatingJavaScriptFromString:@"window.gameCenter._viewDidShow()"];
 }];
 }];
 }

 - (void)openAchievementModal:(CDVInvokedUrlCommand *)command {
 [self.commandDelegate runInBackground:^{
 if ( self.achievementsController == nil ) {
 self.achievementsController = [[GKAchievementViewController alloc] init];
 self.achievementsController.achievementDelegate = self;
 }

 CDVViewController *cont = (CDVViewController *)[super viewController];
 [cont presentViewController:self.achievementsController animated:YES
 completion:^{ [self.webView
 stringByEvaluatingJavaScriptFromString:@"window.gameCenter._viewDidShow()"];
 }];
 }];
 }

 - (void)leaderboardViewControllerDidFinish:(GKLeaderboardViewController
 *)viewController { CDVViewController *cont = (CDVViewController *)[super
 viewController]; [cont dismissViewControllerAnimated:YES completion:nil];
 [self.webView
 stringByEvaluatingJavaScriptFromString:@"window.gameCenter._viewDidHide()"];
 }

 - (void)achievementViewControllerDidFinish:(GKAchievementViewController
 *)viewController { CDVViewController* cont = (CDVViewController *)[super
 viewController]; [cont dismissViewControllerAnimated:YES completion:nil];
 [self.webView
 stringByEvaluatingJavaScriptFromString:@"window.gameCenter._viewDidHide()"];
 }

 - (void)reportAchievementIdentifier:(CDVInvokedUrlCommand *)command {
 [self.commandDelegate runInBackground:^{
 NSString *identifier = (NSString *) [command.arguments objectAtIndex:0];
 float percent = [[command.arguments objectAtIndex:1] floatValue];

 GKAchievement *achievement = [[[GKAchievement alloc] initWithIdentifier:
 identifier] autorelease]; if (achievement) { achievement.percentComplete =
 percent; [achievement reportAchievementWithCompletionHandler:^(NSError *error)
 { CDVPluginResult *pluginResult; if (!error) { pluginResult = [CDVPluginResult
 resultWithStatus:CDVCommandStatus_OK]; } else { pluginResult = [CDVPluginResult
 resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error
 localizedDescription]];
 }
 [self.commandDelegate sendPluginResult:pluginResult
 callbackId:command.callbackId];
 }];
 } else {
 CDVPluginResult *pluginResult = [CDVPluginResult
 resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Failed to alloc
 GKAchievement"]; [self.commandDelegate sendPluginResult:pluginResult
 callbackId:command.callbackId];
 }
 }];
 }

 @end


 */
