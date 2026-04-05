#import <Foundation/Foundation.h>

@interface APSIDSProxyManager : NSObject
- (void)sendProxyIsConnected:(BOOL)isConnected guid:(NSString *)guid environmentName:(NSString *)environmentName;
@end

@interface APSEnvironment : NSObject
- (NSString *)name;
@end

@interface APSProxyClient : NSObject
- (BOOL)isActive;
- (BOOL)isConnectedOnInterface:(int)interface;
- (BOOL)needsToDisconnectOnInterface:(int)interface;
- (APSIDSProxyManager *)proxyManager;
- (void)incomingPresenceWithCertificate:(NSData *)certificate
                                  nonce:(NSData *)nonce
                              signature:(NSData *)signature
                                  token:(NSData *)token
                              hwVersion:(NSString *)hwVersion
                              swVersion:(NSString *)swVersion
                                swBuild:(NSString *)swBuild;
@end
