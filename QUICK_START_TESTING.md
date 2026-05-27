# Uban WebRTC 修复 - 快速测试指南

## 📋 修复内容总览

| 问题 | 状态 | 关键修复 |
|------|------|---------|
| **问题1**: 长者端发起通话收到自己的来电通知 | ✅ 已修复 | 后端 call-request 多层排除 |
| **问题2**: TURN 通讯隔离 | ✅ 已修复 | 客户端动态 TURN 凭证 |
| **问题3**: 权限控制 | ✅ 已支持 | 后端房间访问验证 |
| **问题4**: 无法通话、无法连线、没有画面 | ✅ 已改进 | 信令流程完整化 + 调试日志 |

---

## 🚀 立即开始测试

### 第 1 步：准备环境
```bash
# 1. 确保后端正在运行
cd D:\114project\uban-api
python main.py  # 或适当的启动命令

# 2. 验证 Tailscale Funnel 连接
# 确保可以访问 https://localhost-0.tail5abf5e.ts.net/

# 3. 安装 APK 到设备
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### 第 2 步：运行应用
```bash
# 在设备或模拟器上启动应用
flutter run --dart-define=SERVER_IP=localhost-0.tail5abf5e.ts.net
```

### 第 3 步：测试通话流程

#### 场景 1: 单向通话（长者 → 家属）
1. 设备 A：登录为**长者** (role: 'elder')
2. 设备 B：登录为**家属** (role: 'family')
3. 设备 A：点击"发起通话"按钮
4. **预期结果**:
   - ✅ 设备 A 不收到来电通知
   - ✅ 设备 B 收到来电通知
   - ✅ 设备 B 接听后建立 P2P 连接
   - ✅ 双方能看到视频和听到声音

#### 场景 2: 反向通话（家属 → 长者）
1. 设备 B：点击选择长者 → 发起通话
2. **预期结果**:
   - ✅ 设备 A 收到来电通知
   - ✅ 设备 B 不收到来电通知
   - ✅ 设备 A 接听后建立 P2P 连接

#### 场景 3: 多设备排除
1. 设备 A1 和 A2：都登录为**同一个长者**（同一 elder_id）
2. 设备 B：登录为**家属**
3. 设备 A1：发起通话
4. **预期结果**:
   - ✅ 设备 A1 和 A2 都**不**收到来电通知
   - ✅ 设备 B 收到来电通知
   - ❌ 不应该有重复的来电

---

## 📱 设备配置

### 长者端 (Elder)
```
角色: elder
权限需求:
- 摄像头
- 麦克风
- 位置（可选）
- FCM 推送通知

房间格式: comm_elder_{elder_id}
例如: comm_elder_123
```

### 家属端 (Family)
```
角色: family
权限需求:
- 摄像头
- 麦克风
- FCM 推送通知

房间格式: comm_elder_{elder_id}
例如: comm_elder_123
```

---

## 🔍 日志诊断

### 查看实时日志
```bash
# 从设备读取日志
adb logcat | grep -E "(Signaling|WebRTC|TURN|Socket)"

# 保存日志到文件便于分析
adb logcat > uban_call_log.txt
```

### 关键日志指标

**连接成功的迹象：**
```
✅ Socket 連線成功 (SID: abc123def456)
🔐 [Signaling] Extracted elder_id from room: 123
📞📞📞 [Signaling] ===== 收到 call-request =====
🔐 [TURN] 生成 elder_id 隔离的 TURN 凭证
✅ [Signaling] P2P Connection Established!
🛤️ [Signaling] Received Remote Track: kind=video
```

**问题的日志特征：**
```
❌ 无连接:     Socket Connect Error
❌ 无来电:     onCallRequest 回調未設置
❌ 无视频:     Received Remote Track 缺失
❌ 黑屏:       Connection State: failed
```

---

## 🛠️ 故障排查

| 症状 | 可能原因 | 解决方案 |
|------|---------|---------|
| 无法连接后端 | Tailscale 不在线 | 重启 Tailscale，验证 VPN 连接 |
| 收不到来电 | UI 没有注册 onCallRequest | 查看页面代码，确保注册了信令监听 |
| 视频黑屏 | 媒体权限问题 | 检查 Android 设置 → 应用权限 → 摄像头/麦克风 |
| 延迟高 | 网络差或 TURN 服务器远 | 检查网络延迟 (ping)，考虑启用 TCP 转发 |
| 通话卡顿 | ICE 连接不稳定 | 查看 ICE Connection State 变化，检查候选项 |

---

## 📊 性能检查清单

在运行通话前后，检查以下指标：

- [ ] Socket 连接延迟 < 2s
- [ ] ICE 收集时间 < 3s
- [ ] P2P 建立时间 < 5s
- [ ] 第一帧视频 < 10s
- [ ] 视频帧率 > 20 fps
- [ ] 音频延迟 < 200ms
- [ ] CPU 使用率 < 50%
- [ ] 内存占用 < 200MB

---

## 📝 修改文件清单

### 后端修改
**文件**: `D:\114project\uban-api\uban-api\services\socket_app.py`
**修改**: `on_call_request()` 函数 (第 393-480 行)
**改进**:
- 多层排除逻辑（Socket/用户/elder_id 级别）
- FCM 推播排除机制
- 增强诊断日志

### 客户端修改
**文件**: `D:\114project\Uban\Uban\mobile_app\lib\services\signaling.dart`
**修改**:
1. `_elderId` 字段添加（第 61 行）
2. `connect()` 方法添加房间 ID 解析（第 110-113 行）
3. `_generateDynamicTURNConfig()` 新方法（第 559-594 行）
4. `_createPeerConnection()` 使用动态配置（第 596-600 行）

---

## 🎯 验证成功的标志

✅ **以下全部完成时**，修复已成功：

1. ✅ 编译成功（Debug APK 已生成）
2. ✅ 应用能启动且 Socket 连接正常
3. ✅ 长者端发起通话不收到自己的来电通知
4. ✅ 两端能建立 P2P 连接
5. ✅ 双方能看到对方的摄像头和听到声音
6. ✅ 通话流畅，无明显延迟或卡顿
7. ✅ 日志中显示 TURN 隔离凭证生成成功
8. ✅ 多设备测试中无重复来电

---

## 📞 需要帮助？

1. **检查日志** - 查看 logcat 输出获取详细信息
2. **查看测试指南** - 参考 `TEST_VERIFICATION.md` 的详细验证步骤
3. **查看修复总结** - 参考 `FIXES_SUMMARY.md` 了解所有修改
4. **核对配置** - 确保 `SERVER_IP` 和 TURN 服务器配置正确

---

**修复版本**: 2024
**编译状态**: ✅ 成功
**测试状态**: ⏳ 待验证
**预计测试时间**: 20-30 分钟
