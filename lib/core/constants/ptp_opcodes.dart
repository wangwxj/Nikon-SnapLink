/// PTP 标准操作码与 Nikon 厂商私有扩展操作码表
/// 数据源自原 App 核心逆向反编译 (C1117j1.java / C1088a.java)
class PtpOpCodes {
  PtpOpCodes._();

  // ==========================================
  // 1. 标准 PTP / ISO 15740 操作码 (0x1000 - 0x101F)
  // ==========================================
  static const int getDeviceInfo         = 0x1001; // 4097
  static const int openSession           = 0x1002; // 4098
  static const int closeSession          = 0x1003; // 4099
  static const int getStorageIDs         = 0x1004; // 4100
  static const int getStorageInfo        = 0x1005; // 4101
  static const int getNumObjects         = 0x1006; // 4102
  static const int getObjectHandles      = 0x1007; // 4103
  static const int getObjectInfo         = 0x1008; // 4104
  static const int getObject             = 0x1009; // 4105
  static const int getThumb              = 0x100A; // 4106
  static const int deleteObject          = 0x100B; // 4107
  static const int sendObjectInfo        = 0x100C; // 4108
  static const int sendObject            = 0x100D; // 4109
  static const int initiateCapture       = 0x100E; // 4110
  static const int getDevicePropDesc     = 0x1014; // 4116
  static const int getDevicePropValue    = 0x1015; // 4117
  static const int setDevicePropValue    = 0x1016; // 4118
  static const int resetDevicePropValue  = 0x1017; // 4119
  static const int terminateOpenCapture  = 0x1018; // 4120
  static const int getPartialObject      = 0x101B; // 4123 (用于 4MB 分块流式拉取)

  // ==========================================
  // 2. Nikon 厂商专属私有操作码 (0x9000 - 0x94FF)
  // ==========================================
  static const int nikonAfDrive              = 0x90C1; // 37057 驱动对焦马达
  static const int nikonChangeCameraMode     = 0x90C2; // 37058 切换相机模式
  static const int nikonDeviceReady          = 0x90C8; // 37064 查询相机就绪状态
  static const int nikonStartLiveView        = 0x9201; // 37377 开启取景画面
  static const int nikonEndLiveView          = 0x9202; // 37378 结束取景画面
  static const int nikonGetLiveViewImage     = 0x9203; // 37379 经典抓取取景帧 (JPEG)
  static const int nikonChangeAfArea         = 0x9205; // 37381 修改对焦区域坐标
  static const int nikonCaptureToCard        = 0x9207; // 37383 拍照并存入机身卡
  static const int nikonStartMovieRecInCard  = 0x920A; // 37386 启动机内录像
  static const int nikonEndMovieRec          = 0x920B; // 37387 结束机内录像
  static const int nikonEndSpotWhiteBalance  = 0x9403; // 37891 结束点测白平衡
  static const int nikonGetEventEx           = 0x941C; // 37916 扩展事件轮询
  static const int nikonGetObjectSize        = 0x9421; // 37921 获取对象实际尺寸
  static const int nikonLiveViewMaxSize      = 0x9423; // 37923 查询取景缓冲区最大尺寸
  static const int nikonStartTracking        = 0x9424; // 37924 启动对象对焦跟踪
  static const int nikonEndTracking          = 0x9425; // 37925 结束对象对焦跟踪
  static const int nikonGetLiveViewImageEx   = 0x9428; // 37928 扩展抓取取景帧 (优先)
  static const int nikonGetPartialObject64   = 0x9431; // 37937 64位大文件局部读取
  static const int nikonGetObjectMetadata    = 0x9434; // 37940 获取镜头与日期私有元数据
  static const int nikonChangeAppMode        = 0x9435; // 37941 切换应用控制模式
  static const int nikonGetDevicePropDescEx  = 0x943A; // 37946 扩展属性描述查询
  static const int nikonGetDevicePropValueEx = 0x943B; // 37947 扩展属性值查询
  static const int nikonZZoomDrive           = 0x9464; // 37988 电动变焦驱动 (SnapBridge-Enhanced 规范)


  // ==========================================
  // 3. PTP/IP 协议包类型编号 (PacketType)
  // ==========================================
  static const int ptpIpInitCommandRequest   = 1;
  static const int ptpIpInitCommandAck       = 2;
  static const int ptpIpInitEventRequest     = 3;
  static const int ptpIpInitEventAck         = 4;
  static const int ptpIpOperationRequest     = 6;
  static const int ptpIpOperationResponse    = 7;
  static const int ptpIpEvent                = 8;
  static const int ptpIpStartDataPacket      = 9;
  static const int ptpIpDataPacket           = 10;
  static const int ptpIpCancelTransaction    = 11;
  static const int ptpIpEndDataPacket        = 12;

  // ==========================================
  // 4. PTP 响应代码 (Response Codes)
  // ==========================================
  static const int responseOk                    = 0x2001; // 成功
  static const int responseGeneralError          = 0x2002; // 通用错误
  static const int responseSessionNotOpen        = 0x2003; // 会话未建立
  static const int responseInvalidTransactionId  = 0x2004; // 事务ID无效
  static const int responseOperationNotSupported = 0x2005; // 操作不支持 (用于降级)
  static const int responseParameterNotSupported = 0x2006; // 参数不支持
  static const int responseDeviceBusy            = 0x2019; // 相机正忙
  static const int responseSessionAlreadyOpen    = 0x201E; // 会话已开启 (可复用)
  static const int responseStoreFull             = 0x200C; // 存储卡已满
}
