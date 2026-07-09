# GameOptimizer

Thư viện iOS (Objective-C++ / C++ / Metal) cho Dynamic Resolution Scaling + tối ưu CPU/frame pacing, kèm menu overlay UIKit. Chỉ dùng cho app/game bạn sở hữu hoặc có quyền kiểm thử — không inject vào app bên thứ ba, không bypass anti-cheat/DRM/jailbreak-detection/sandbox/code-signing, không sửa gameplay.

## Vì sao không có `.xcodeproj` / `CMakeLists.txt`

Thay vào đó dự án dùng **Swift Package Manager** (`Package.swift`):
- Không cần Xcode để tạo/sửa — `.xcodeproj` (định dạng `pbxproj`) rất dễ hỏng nếu chỉnh tay mà không có Xcode kiểm tra lại.
- `xcodebuild` mở và build `Package.swift` trực tiếp, không cần generate project.
- GitHub Actions (macOS runner) build thẳng ra `.xcframework` — đúng thứ bạn cần vì không có máy Mac.

Shader Metal (`UpscaleShaders.metal`) được giữ lại làm tài liệu tham khảo, nhưng lúc chạy thực tế thư viện tự compile shader từ một chuỗi string giống hệt nội dung file đó (`GameOptimizerMetalRenderer.mm`) — để việc build không phụ thuộc vào việc SPM có xử lý `.metal` tốt hay không.

## Build

**Cách 1 — GitHub Actions (không cần máy Mac):** push repo lên GitHub, workflow `.github/workflows/build.yml` tự chạy, tải artifact `GameOptimizer-xcframework` ở tab Actions → workflow run → Artifacts. Kéo `GameOptimizer.xcframework` vào project Xcode của bạn (Frameworks, Libraries... → Add).

**Cách 2 — Xcode (nếu có Mac sau này):** mở thẳng `Package.swift` bằng Xcode, chọn scheme `GameOptimizer`, Product → Archive, hoặc chạy lệnh `xcodebuild` như trong `build.yml`.

**Deployment target:** iOS 14+. Toàn bộ API dùng (CADisplayLink, Metal, os_unfair_lock, UIWindowScene, ProcessInfo.thermalState...) đã ổn định từ iOS 13-15, nên chạy tốt trên mọi bản iOS hiện hành kể cả 18.4.1. Riêng `CAFrameRateRange` (iOS 15+) có fallback `preferredFramesPerSecond` cho máy cũ hơn.

## Tích hợp nhanh

```objc
#include <GameOptimizer/GameOptimizer.h>

// Sau khi tạo device + command queue:
GameOptimizerInitialize();
GameOptimizerAttachMetalDevice((__bridge void *)device, (__bridge void *)commandQueue);

// Mỗi frame (xem Example/IntegrationExample.mm để có ví dụ đầy đủ):
GameOptimizerRenderSize size = GameOptimizerBeginFrame(drawableW, drawableH);
// render scene vào texture kích thước size.width x size.height ...
GameOptimizerEncodeUpscale(cb, sceneTexture, drawableTexture); // nếu size != drawable size
// trong completion handler của command buffer:
GameOptimizerEndFrame(cpuMS, gpuMS);

// Mở menu debug (vd gán vào 1 nút riêng của bạn):
GameOptimizerToggleMenu();

// Khi thoát app:
GameOptimizerShutdown();
```

Muốn tự quản lý toàn bộ pipeline render/upscale của riêng bạn thay vì gọi `EncodeUpscale`? Chỉ cần dùng `GameOptimizerGetMetrics().currentRenderScale` để biết scale hiện tại và tự dựng shader riêng — mọi API cấu hình/metrics vẫn hoạt động độc lập.

## Quyết định kiến trúc đáng chú ý

- **Công tắc "Tối ưu tổng"** nằm ở thanh tiêu đề của menu (luôn thấy được ở mọi tab) thay vì chỉ nằm trong tab "Tối ưu hiệu năng", để bật/tắt nhanh mà không cần chuyển tab.
- **Cử chỉ khôi phục nút OPT** (chạm 3 ngón, 2 lần) được gắn (`addGestureRecognizer:`) trực tiếp vào key window của app, với `cancelsTouchesInView = NO` — không dùng swizzling `sendEvent:`. Cách này để cử chỉ nhận được ở toàn màn hình mà không chặn bất kỳ touch nào của game, và không cần kỹ thuật private-API/hacky.
- **Metal upscale API công khai** (`GameOptimizerEncodeUpscale` v.v.) nhận `void*` đã bridge từ `id<MTLxxx>` — theo đúng chuẩn ABI C, thư viện không giữ ownership các object này.
- **Bicubic Lite** = Catmull-Rom 16-tap thủ công (không dùng “4-tap hardware trick” vì công thức đó dễ sai nếu không test bằng mắt được) — đúng về toán học nhưng tốn hơn 1 chút so với bilinear, chỉ nên bật khi dư hiệu năng.
- **`maxTextureDimension2D`**: Metal không có property runtime cho giá trị này, nên dùng hằng số an toàn 8192 thay vì bịa API.
- **`memoryUsageBytes`** trong metrics chỉ tính texture do chính thư viện cấp phát (cộng dồn theo kích thước), không phải tổng bộ nhớ toàn app.

## Checklist chống crash (đã áp dụng trong code)

- Mọi API public kiểm tra `initialized`, null pointer, `isfinite`, range trước khi dùng.
- Không `dispatch_sync` lên main queue ở bất kỳ đâu — chỉ `dispatch_async` hoặc chạy thẳng nếu đã ở main thread.
- Config đọc/ghi qua `os_unfair_lock` + snapshot theo giá trị (không giữ lock khi encode Metal).
- Texture cũ chỉ giải phóng sau khi generation tương ứng được `RetireGeneration()` xác nhận GPU đã dùng xong (gọi từ `GameOptimizerEndFrame`, vốn được gọi trong completion handler).
- Giới hạn 3 generation texture đang chờ giải phóng — vượt quá thì tạm hoãn resize thay vì tạo thêm.
- `CADisplayLink` chỉ tạo 1 cái, dùng proxy object riêng để tránh retain cycle, invalidate khi Stop()/Shutdown().
- 5 lần lỗi Metal liên tiếp → tự tắt Dynamic Resolution, không crash.

## Checklist memory leak

- `SafeResourcePool`/`GameOptimizerMetalRenderer` dùng `__bridge_retained`/`__bridge_transfer` cân bằng nhau ở mọi nhánh.
- Notification observers và CADisplayLink được gỡ trong `Stop()`, gọi từ `Shutdown()`.
- Gesture recognizer khôi phục nút OPT được gỡ khỏi app window trong `teardown`.
- Không capture `self`/con trỏ ObjC mạnh trong completion handler theo cách gây cycle — các block trong `FrameMetricsCollector` chỉ capture con trỏ C++ thuần (không tham gia ARC).

## Hạn chế đã biết

- **CPU fallback timing**: khi không có GPU timing thật (`gpuFrameTimeMS < 0`), controller dùng CPU frame time thay thế — nếu nghẽn cổ chai thực sự là CPU (không phải GPU), giảm render scale có thể không cải thiện FPS. Đây là giới hạn vật lý, không phải bug.
- **Đa cửa sổ/đa scene**: cử chỉ khôi phục nút OPT chỉ gắn vào 1 key window tại thời điểm khởi tạo; app dùng nhiều `UIWindowScene` cùng lúc cần tự mở rộng.
- Chưa test compile thật (môi trường viết code này không có Xcode/macOS) — nhiều khả năng cần sửa nhỏ ở lần build đầu tiên trên Actions; xem log lỗi và tôi có thể sửa tiếp.
- Test trong `Tests/` viết theo XCTest nhưng chưa nối vào `Package.swift` (tránh rủi ro cho phần build chính) — thêm thủ công vào 1 Unit Testing Bundle trong Xcode nếu muốn chạy.

## Cấu trúc

Xem sơ đồ đầy đủ trong lịch sử chat — toàn bộ nằm dưới `Sources/GameOptimizer/{Public,Core,Metal,UI,Utilities,Example}` + `Tests/` + `Package.swift` + `.github/workflows/build.yml`.
