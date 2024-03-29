//
//  JBXMPPManager.m
//  IMChatDemo
//
//  Created by lujiangbin on 15/10/13.
//  Copyright © 2015年 lujiangbin. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "JBXMPPManager.h"


@interface JBXMPPManager ()

@end


@implementation JBXMPPManager


static JBXMPPManager *_instance;
+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[JBXMPPManager alloc] init];
        [_instance setupStream];
    });
    
    return _instance;
}

-(instancetype)init
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate) name:UIApplicationWillTerminateNotification object:nil];
    }
    return self;
}

#pragma mark -- strean setup

- (void)setupStream
{
    if (!_xmppStream) {
        _xmppStream = [[XMPPStream alloc] init];
        
        [self.xmppStream setHostName:JBXMPP_HOST];
        [self.xmppStream setHostPort:JBXMPP_PORT];
        [self.xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];
        [self.xmppStream setKeepAliveInterval:30000];
        self.xmppStream.enableBackgroundingOnSocket=YES;
        
        //接入断线重连模块
        _xmppReconnect = [[XMPPReconnect alloc] init];
        [_xmppReconnect setAutoReconnect:YES];
        [_xmppReconnect activate:self.xmppStream];
        
        //接入流管理模块
        _storage = [XMPPStreamManagementMemoryStorage new];
        _xmppStreamManagement = [[XMPPStreamManagement alloc] initWithStorage:_storage];
        _xmppStreamManagement.autoResume = YES;
        [_xmppStreamManagement addDelegate:self delegateQueue:dispatch_get_main_queue()];
        [_xmppStreamManagement activate:self.xmppStream];
        
        //接入好友模块
        _xmppRosterMemoryStorage = [[XMPPRosterMemoryStorage alloc] init];
        _xmppRoster = [[XMPPRoster alloc] initWithRosterStorage:_xmppRosterMemoryStorage];
        [_xmppRoster activate:self.xmppStream];
        [_xmppRoster addDelegate:self delegateQueue:dispatch_get_main_queue()];
        
        //接入消息模块
        _xmppMessageArchivingCoreDataStorage = [XMPPMessageArchivingCoreDataStorage sharedInstance];
        _xmppMessageArchiving = [[XMPPMessageArchiving alloc] initWithMessageArchivingStorage:_xmppMessageArchivingCoreDataStorage dispatchQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 9)];
        [_xmppMessageArchiving activate:self.xmppStream];
        
        //接入聊天室管理模块
        _xmppMuc = [[XMPPMUC alloc]init];
        [_xmppMuc addDelegate:self delegateQueue:dispatch_get_main_queue()];
        [_xmppMuc activate:self.xmppStream];
        _xmppRooms = [NSMutableDictionary dictionary];
        
        
                
        

    }
}

#pragma mark --join Group Chat

- (void)joinGroupChatWithRoomJid:(NSArray *)jids {
    
    for (NSString *jid in jids) {
        
        XMPPJID *roomJid = [XMPPJID jidWithString:jid];
        //接入聊天模块
        XMPPRoomMemoryStorage *roomStorage = [[XMPPRoomMemoryStorage alloc]init];
        XMPPRoom *room = [[XMPPRoom alloc]initWithRoomStorage:roomStorage jid:roomJid];
        [room addDelegate:self delegateQueue:dispatch_get_main_queue()];
        [room activate:self.xmppStream];
        [room joinRoomUsingNickname:self.xmppStream.myJID.user history:nil];
        [self.xmppRooms setObject:room forKey:jid];

    }
    
}

- (XMPPRoom *)getRoomWithRoomJid:(NSString *)roomJid{
    
    return [self.xmppRooms objectForKey:roomJid];
}

- (void)setCurrentChattingRoomId:(NSString *)roomJid {
    
    XMPPRoom *currentRoom = [self.xmppRooms objectForKey:roomJid];
    [[NSUserDefaults standardUserDefaults] setObject:currentRoom.myRoomJID.full forKey:CHATTING_ROOM_ID];
    [[NSUserDefaults standardUserDefaults] synchronize];
}



#pragma mark -- go onlie, offline

-(void)loginWithName:(NSString *)userName andPassword:(NSString *)password
{
    _myJID = [XMPPJID jidWithUser:userName domain:JBXMPP_DOMAIN resource:@"iOS"];
    self.myPassword = password;
    [self.xmppStream setMyJID:_myJID];
    NSError *error = nil;
    if (![_xmppStream connectWithTimeout:XMPPStreamTimeoutNone error:&error])
    {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error connecting"
                                                            message:@"please connect host in a same gateway!"
                                                           delegate:nil
                                                  cancelButtonTitle:@"Ok"
                                                  otherButtonTitles:nil];
        [alertView show];
    }
}

-(void)logOut
{
    [self goOffline];
    [_xmppStream disconnectAfterSending];
    [self.xmppRooms removeAllObjects];
}


- (void)goOnline
{
    XMPPPresence *presence = [XMPPPresence presence]; // type="available" is implicit
    [[self xmppStream] sendElement:presence];
}

- (void)goOffline
{
    XMPPPresence *presence = [XMPPPresence presenceWithType:@"unavailable"];
    
    [[self xmppStream] sendElement:presence];
}

- (void)sendMessage:(NSString *)message to:(XMPPJID *)jid
{
    XMPPMessage* newMessage = [[XMPPMessage alloc] initWithType:@"chat" to:jid];
    [newMessage addBody:message];
    [_xmppStream sendElement:newMessage];
}


#pragma mark -- connect delegate

- (void)xmppStream:(XMPPStream *)sender socketDidConnect:(GCDAsyncSocket *)socket
{
    NSLog(@"%s",__func__);
}

- (void)xmppStreamDidConnect:(XMPPStream *)sender
{
    NSError *error = nil;
    if (![[self xmppStream] authenticateWithPassword:_myPassword error:&error])
    {
        NSLog(@"Error authenticating: %@", error);
    }
}

- (void)xmppStreamDidDisconnect:(XMPPStream *)sender withError:(NSError *)error
{
    NSLog(@"%s",__func__);
}

- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender
{
    NSLog(@"%s",__func__);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DIDLogIn" object:nil];
    
    [self goOnline];
    
    //启用流管理
    [_xmppStreamManagement enableStreamManagementWithResumption:YES maxTimeout:0];
}

- (void)xmppStream:(XMPPStream *)sender didNotAuthenticate:(NSXMLElement *)error
{
    NSLog(@"%s",__func__);
    NSXMLElement *xElement = [error elementForName:@"x" xmlns:@"http://jabber.org/protocol/muc#user"];
    NSXMLElement *statusElement = [xElement elementForName:@"status"];
    NSString *statusCode = [statusElement attributeStringValueForName:@"code"];
    if ([statusCode isEqualToString:@"110"]) {
        [self xmppStreamDidAuthenticate:nil];
    }
}


#pragma mark -- XMPPMessage Delegate


- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
    NSLog(@"%s",__func__);
}

- (void)xmppStream:(XMPPStream *)sender didSendMessage:(XMPPMessage *)message
{
    NSLog(@"%s--%@",__FUNCTION__, message);
}

- (void)xmppStream:(XMPPStream *)sender didFailToSendMessage:(XMPPMessage *)message error:(NSError *)error
{
    NSLog(@"%s--%@",__FUNCTION__, message);
}

#pragma mark -- XMPPRoom Delegate


- (void)xmppRoomDidJoin:(XMPPRoom *)sender {
    NSLog(@"user has join room");
}
- (void)xmppRoomDidLeave:(XMPPRoom *)sender {
    NSLog(@"user has left room");
//    [self.xmppRoom removeDelegate:self delegateQueue:dispatch_get_main_queue()];
//    [self.xmppRoom deactivate];
//    [self.xmppRoom destroyRoom];
//    self.xmppRoom = nil;
//    self.xmppRoomMemoryStorage = nil;
}


#pragma mark -- Roster

- (void)xmppStream:(XMPPStream *)sender didReceivePresence:(XMPPPresence *)presence
{
    //对方上线或离线,更新状态
    //xmppRosterDidChange
}

- (void)xmppRosterDidChange:(XMPPRoster *)sender
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RosterChanged" object:nil];
}

#pragma mark -- Room chat
- (void)xmppMUC:(XMPPMUC *)sender didDiscoverServices:(NSArray *)services {
    for (NSXMLElement *element in services) {
        
        NSString *serviceName = [element attributeForName:@"jid"].stringValue;
        [self.xmppMuc discoverRoomsForServiceNamed:serviceName];
    }
    
}

- (void)xmppMUC:(XMPPMUC *)sender didDiscoverRooms:(NSArray *)rooms forServiceNamed:(NSString *)serviceName {
    NSLog(@"serviceName:%@,room:%@",serviceName,rooms);
    NSMutableArray *roomArray = [NSMutableArray arrayWithCapacity:1];
    for (NSXMLElement *element in rooms) {
        [roomArray addObject:[element attributeStringValueForName:@"jid"]];
    }
    NSDictionary *dic = @{@"roomNames":roomArray};
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GroupListChaged" object:self userInfo:dic];
    [self joinGroupChatWithRoomJid:roomArray];
}
#pragma mark ===== 文件接收=======

//是否同意对方发文件
- (void)xmppIncomingFileTransfer:(XMPPIncomingFileTransfer *)sender didReceiveSIOffer:(XMPPIQ *)offer
{
    NSLog(@"%s",__FUNCTION__);
    [self.xmppIncomingFileTransfer acceptSIOffer:offer];
}

//存储文件 音频为amr格式  图片为jpg格式
- (void)xmppIncomingFileTransfer:(XMPPIncomingFileTransfer *)sender didSucceedWithData:(NSData *)data named:(NSString *)name
{
    XMPPJID *jid = [sender.senderJID copy];
    NSString *subject;
    NSString *extension = [name pathExtension];
    if ([@"amr" isEqualToString:extension]) {
        subject = @"voice";
    }else if([@"jpg" isEqualToString:extension]){
        subject = @"picture";
    }
    
    XMPPMessage *message = [XMPPMessage messageWithType:@"chat" to:jid];
    
    [message addAttributeWithName:@"from" stringValue:sender.senderJID.bare];
    [message addSubject:subject];
    
    NSString *path =  [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    path = [path stringByAppendingPathComponent:[XMPPStream generateUUID]];
    path = [path stringByAppendingPathExtension:extension];
    [data writeToFile:path atomically:YES];
    
    [message addBody:path.lastPathComponent];
    
    [self.xmppMessageArchivingCoreDataStorage archiveMessage:message outgoing:NO xmppStream:self.xmppStream];
}

#pragma mark -- terminate
/**
 *  申请后台时间来清理下线的任务
 */
-(void)applicationWillTerminate
{
    UIApplication *app=[UIApplication sharedApplication];
    UIBackgroundTaskIdentifier taskId;
    
    taskId=[app beginBackgroundTaskWithExpirationHandler:^(void){
        [app endBackgroundTask:taskId];
    }];
    
    if(taskId==UIBackgroundTaskInvalid){
        return;
    }
    
    //只能在主线层执行
    [_xmppStream disconnectAfterSendingEndStream];
}

@end
