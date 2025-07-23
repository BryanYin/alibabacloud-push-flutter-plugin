import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  NewWantListener,
} from '@ohos/flutter_ohos';

import {
  aliyunPush,
  Channel,
  ExtensionNotification,
  IPushListener,
  PushDataType,
  PushError,
  PushMessage,
  PushNotification,
  PushNotificationHandler
} from '@aliyun/push';
import { pushService } from '@kit.PushKit';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';

/** AliyunPushPlugin **/
export default class AliyunPushPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware, NewWantListener, IPushListener, PushNotificationHandler {
  public static instance: AliyunPushPlugin;
  private channel: MethodChannel | null = null;
  private context: Context | null = null;
  private launchWant: Want | null = null;
  private deviceId: string | undefined;
  private static CODE_SUCCESS = "10000";
  private static CODE_PARAM_ILLEGAL = "10001";
  private static CODE_FAILED = "10002";
  private static CODE_NOT_SUPPORT = "10005";
  private static CODE_KEY = "code";
  private static ERROR_MSG_KEY = "errorMsg";

  constructor() {
    AliyunPushPlugin.instance = this;
  }

  getUniqueClassName(): string {
    return "AliyunPushPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "aliyun_push");
    this.channel.setMethodCallHandler(this)
    this.context = binding.getApplicationContext();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    console.log("调用方法：" + call.method)
    if (call.method == "getPlatformVersion") {
      result.success("OpenHarmony ^ ^ ")
    } else if (call.method == "initPushSdk") {
      this.initPushSdk(call, result)
    } else if (call.method == "getDeviceId") {
      this.getDeviceId(result)
    } else if (call.method == "addAlias") {
      this.addAlias(call, result)
    } else if (call.method == "removeAlias") {
      this.removeAlias(call, result)
    } else if (call.method == "setBadgeNum"){
      this.setBadgeNum(call,result)
    } else {
      console.error("调用方法：" + call.method + " 未实现")
      result.notImplemented()
    }
  }

  public callFlutterMethod(method: string, params: Map<string, ESObject>) {

    if (!method) {
      return;
    }

    let promise: Promise<void> = new Promise<void>(() => {
      this.channel?.invokeMethod(method, params)
    });

    promise.then(() => console.log('执行 Flutter 方法：'+ method)).catch((r: Error) => {
      console.error(r.message);
    })
  }

  ///////////// AbilityAware 接口实现
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    binding.addOnNewWantListener(this)
    this.launchWant = binding.getAbility().launchWant
  }

  onDetachedFromAbility(): void {
    throw new Error('Method not implemented.');
  }

  ///////////// NewWantListener 接口实现
  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    aliyunPush.handleClickNotification(want, this)
  }

  ///////////// IPushListener 接口实现
  onReceiveNotification(data: PushNotification | ExtensionNotification): boolean {
    console.error('onReceiveNotification:' + JSON.stringify(data))
    if (data.type === PushDataType.Notification) {
      // 处理推送通知
    } else if (data.type === PushDataType.ExtensionNotification) {
      // 处理通知扩展消息
    }
    return false;
  }

  onShowNotification(data: PushNotification | ExtensionNotification): void {
    // 处理通知展示事件
    console.error('onShowNotification:' + JSON.stringify(data))
  }

  onReceiveMessage(data: PushMessage): void {
    // 处理推送消息
    console.error('onReceiveMessage:' + JSON.stringify(data))
  }

  ///////////// PushNotificationHandler 接口实现
  onClickNotification(data: PushNotification | PushMessage | ExtensionNotification, from: Channel): void {
    // 由用户点击通知拉起的页面，获取推送数据，处理业务逻辑
    console.error('onClickNotification:' + JSON.stringify(data))
    let params: Map<string, ESObject> = new Map();
    params.set('title', data.title)
    params.set('content', data.content)

    if (data.type === PushDataType.Notification) {
      params.set('ext', (data as PushNotification).ext)
    }

    this.callFlutterMethod('onNotificationOpened', params);
  }

  noPushData(): void {
    // 不是由用户点击通知拉的页面, 或者不是阿里云推送的数据
    console.error('noPushData')
  }

  ///////////// EMAS 接口
  private async initPushSdk(call: MethodCall, result: MethodResult) {
    let appKey: string|null = call.argument('appKey')
    let appSecret: string|null = call.argument('appSecret')

    let map: Map<string, string> = new Map()
    if (!appKey || !appSecret) {
      this.paramError(map, "appKey or appSecret can not be empty", result)
      return;
    }

    aliyunPush.init({ appKey, appSecret, context: this.context })
    aliyunPush.setPushListener(this)
    aliyunPush.handleClickNotification(this.launchWant, this)

    // ************* 注册设备获取设备ID *************
    try {
      await aliyunPush.register();
      this.deviceId = aliyunPush.getDeviceId();
      console.log("aliyun 设备注册成功：" + this.deviceId)

      await this.registerThirdPush();
      this.success(map, result)
    } catch (err) {
      if (err instanceof PushError) {
        this.aliyunError(map, result, err)
      }
    }
  }

  private async registerThirdPush() {
    return pushService.getToken().then((pushToken) => {
      // ************* 注册PushToken begin *************
      return aliyunPush.registerThirdToken(pushToken).then(() => {
        console.info(`注册PushToken成功`);
      }).catch((err: BusinessError) => {
        console.error(`注册PushToken失败，错误码:${err.code} 错误信息${err.message}`);
        throw new PushError(err.code.toString(), err.message)
      })
      // ************* 注册PushToken end *************
    }).catch((error: BusinessError) => {
      console.error(`获取PushToken失败，错误码:${error.code} 错误信息${error.message}`);
      throw new PushError(error.code.toString(), error.message)
    })
  }

  /**
   * 工具方法，输入参数错误
   */
  private paramError(map: Map<string, string>, msg: string, result: MethodResult) {
    map.set(AliyunPushPlugin.CODE_KEY, AliyunPushPlugin.CODE_PARAM_ILLEGAL)
    map.set(AliyunPushPlugin.ERROR_MSG_KEY, msg)
    result.success(map)
  }

  /**
   * 工具方法，aliyun sdk 中的错误
   */
  private aliyunError(map: Map<string, string>, result: MethodResult, err?: PushError,) {
    if (err) {
      map.set(AliyunPushPlugin.CODE_KEY, err.code)
      map.set(AliyunPushPlugin.ERROR_MSG_KEY, err.message)
      result.success(map)
    } else {
      this.success(map, result)
    }
  }

  private success(map: Map<string, string>, result: MethodResult) {
    map.set(AliyunPushPlugin.CODE_KEY, AliyunPushPlugin.CODE_SUCCESS)
    result.success(map)
  }

  private getDeviceId(result: MethodResult) {
    if (this.deviceId) {
      result.success(this.deviceId)
    } else {
      let deviceId = aliyunPush.getDeviceId()
      result.success(deviceId ?? "")
    }
  }

  private addAlias(call: MethodCall, result: MethodResult) {
    let map: Map<string, string> = new Map();
    let alias: string|null = call.argument('alias');

    if (!alias) {
      this.paramError(map, "alias can not be empty", result)
      return
    }

    aliyunPush.addAlias(alias, (err) => {
      this.aliyunError(map, result, err)
    })
  }

  private removeAlias(call: MethodCall, result: MethodResult) {
    let map: Map<string, string> = new Map();
    let alias: string|null = call.argument('alias');

    if (!alias) {
      this.paramError(map, "alias can not be empty", result)
      return
    }

    aliyunPush.removeAlias(alias, (err) => {
      this.aliyunError(map, result, err)
    })
  }

  private setBadgeNum(call:MethodCall,result:MethodResult){
    let map: Map<string, string> = new Map();
    let num:number|null = call.argument("badgeNum")

    if(num == null){
      this.paramError(map,"badge num can not be empty",result)
      return
    }

    notificationManager.setBadgeNumber(num,()=>{
      this.success(map,result)
    })
  }
}