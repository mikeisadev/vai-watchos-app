# VAI WatchOS App - Setup Instructions

## Required Permissions and Configurations

To enable all features of the VAI WatchOS app, you need to configure the following permissions in Xcode.

### 1. Location Permissions

The app requires location permissions to capture GPS coordinates when a shake is detected.

#### Steps to add in Xcode:

1. Open the project in Xcode
2. Select the **vai-watchos-app Watch App** target
3. Go to the **Info** tab
4. Add the following keys under **Custom iOS Target Properties**:

| Key | Type | Value |
|-----|------|-------|
| `NSLocationWhenInUseUsageDescription` | String | "VAI needs your location to send alerts when you shake your watch" |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | String | "VAI needs your location to send emergency alerts" |

**Or add to Info.plist:**
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>VAI needs your location to send alerts when you shake your watch</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>VAI needs your location to send emergency alerts</string>
```

### 2. Motion Permissions

The app uses the accelerometer to detect shake gestures.

#### Steps to add in Xcode:

1. Go to **Info** tab of the Watch App target
2. Add this key:

| Key | Type | Value |
|-----|------|-------|
| `NSMotionUsageDescription` | String | "VAI needs motion access to detect shake gestures for emergency alerts" |

**Or add to Info.plist:**
```xml
<key>NSMotionUsageDescription</key>
<string>VAI needs motion access to detect shake gestures for emergency alerts</string>
```

### 3. Network Configuration

The app connects to a WebSocket server at `wss://dev.appvai.it/user-location`.

#### For Development (HTTP debugging if needed):

1. Go to **Info** tab
2. Add:

| Key | Type | Value |
|-----|------|-------|
| `NSAppTransportSecurity` | Dictionary | |
| └─ `NSAllowsArbitraryLoads` | Boolean | `NO` |
| └─ `NSExceptionDomains` | Dictionary | |
|    └─ `dev.appvai.it` | Dictionary | |
|       └─ `NSExceptionAllowsInsecureHTTPLoads` | Boolean | `NO` |
|       └─ `NSIncludesSubdomains` | Boolean | `YES` |

**Note:** Since you're using `wss://` (secure WebSocket), this is optional. Only add if you need to allow insecure connections for development.

### 4. Background Modes (Optional - for background location)

If you want the app to work in the background:

1. Select the **vai-watchos-app Watch App** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **Background Modes**
5. Check:
   - ✅ **Location updates**

### 5. Required Frameworks

The following frameworks are already used in the code and should be automatically linked:

- **CoreLocation** (for GPS)
- **CoreMotion** (for accelerometer)
- **Foundation** (for WebSocket)
- **SwiftUI** (for UI)
- **Combine** (for reactive updates)

---

## Quick Setup Checklist

- [ ] Add `NSLocationWhenInUseUsageDescription` to Info
- [ ] Add `NSMotionUsageDescription` to Info
- [ ] Verify network connectivity (wss:// should work by default)
- [ ] Test on a real Apple Watch (shake detection requires physical device)
- [ ] Ensure location services are enabled in Settings on the watch

---

## Testing

### On Simulator:
- ⚠️ **Shake detection will NOT work** (no accelerometer simulation)
- ⚠️ **Location may be simulated** (use Debug > Location in simulator)
- ✅ WebSocket connection should work

### On Real Device:
1. Build and run on your Apple Watch
2. Tap **Start** to begin monitoring
3. Shake your watch vigorously
4. You should see:
   - Status change to "Shake detected!"
   - Status change to "Sending alert..."
   - Status change to "Alert sent!"
   - Alert count increment

---

## Architecture Overview

The app consists of 4 main components:

### 1. **LocationManager.swift**
- Manages GPS location services
- Uses `CLLocationManager` with best accuracy
- Provides async/await API for one-shot location requests
- Includes 10-second timeout
- Handles authorization states

### 2. **MotionManager.swift**
- Monitors accelerometer data
- Detects shake gestures (threshold: 2.5g)
- 1-second cooldown between detections
- Callback-based architecture

### 3. **WebSocketManager.swift**
- Manages WebSocket connection to `wss://dev.appvai.it/user-location`
- Auto-reconnection with exponential backoff
- Emits alert events with JSON payload:
```json
{
  "event": "alert",
  "data": {
    "user_id": "UUID",
    "coords": {
      "latitude": "lat_string",
      "longitude": "lon_string"
    }
  }
}
```

### 4. **AlertService.swift**
- Main coordinator service
- Orchestrates: shake → location → alert emission
- State management for UI
- Error handling and recovery

### 5. **ContentView.swift**
- SwiftUI interface
- Real-time status updates
- Start/Stop monitoring
- Alert statistics display

---

## Production Readiness Checklist

- [x] Error handling implemented
- [x] Logging added for debugging
- [x] State management with @Published properties
- [x] Memory management (weak self, deinit)
- [x] Timeout handling for location requests
- [x] Cooldown for shake detection
- [x] Reconnection logic for WebSocket
- [x] Permission checking and user feedback
- [ ] Add to Xcode project target (add new Swift files)
- [ ] Configure Info.plist permissions
- [ ] Test on real hardware
- [ ] Verify WebSocket server endpoint

---

## File Structure

```
vai-watchos-app Watch App/
├── LocationManager.swift      # GPS tracking
├── MotionManager.swift         # Shake detection
├── WebSocketManager.swift      # Network communication
├── AlertService.swift          # Main coordinator
├── ContentView.swift           # UI
└── vai_watchos_appApp.swift   # App entry point
```

---

## Troubleshooting

### Location not working
- Check that location permissions are granted
- Verify `NSLocationWhenInUseUsageDescription` is in Info.plist
- Check that Location Services are enabled on the watch

### Shake not detected
- Must test on **real Apple Watch** (simulator doesn't support)
- Try shaking more vigorously (threshold is 2.5g)
- Check that motion permissions are granted

### WebSocket connection fails
- Verify the server `wss://dev.appvai.it/user-location` is running
- Check network connectivity on the watch
- Review WebSocketManager logs in console

### Files not appearing in Xcode
1. Right-click on the Watch App folder in Xcode
2. Select **Add Files to "vai-watchos-app"...**
3. Select all .swift files
4. Make sure **Target** is checked for "vai-watchos-app Watch App"

---

## Next Steps

1. **Open the project in Xcode**
2. **Add the permission keys to Info.plist** (see above)
3. **Build and run on a real Apple Watch**
4. **Test the shake detection feature**
5. **Monitor console logs for debugging**

---

## Support

For questions or issues, check:
- Console logs (contain detailed debugging info)
- Location Services settings on the watch
- Network connectivity
- Server availability at dev.appvai.it
