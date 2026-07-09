#import "GameOptimizerGuideViewController.h"

@implementation GameOptimizerGuideViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:scroll];

    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:12.5];
    label.textColor = [UIColor whiteColor];
    label.text = [self guideText];

    CGFloat w = self.view.bounds.size.width - 24;
    CGSize fit = [label sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)];
    label.frame = CGRectMake(12, 8, w, fit.height);
    [scroll addSubview:label];
    scroll.contentSize = CGSizeMake(self.view.bounds.size.width, fit.height + 24);
}

- (NSString *)guideText {
    return
    @"Scale Resolution là gì?\n"
    @"Scale Resolution là tỷ lệ độ phân giải mà phần đồ họa 3D được render trước khi upscale lên độ phân giải màn hình.\n\n"
    @"• Scale 1.00 = render 100% độ phân giải gốc.\n"
    @"• Scale 0.80 = chiều rộng và chiều cao render ở mức 80%.\n"
    @"• Scale 0.70 giảm tải GPU nhiều hơn nhưng hình ảnh có thể mờ hơn.\n"
    @"• Scale 0.50 giảm tải rất mạnh nhưng chất lượng hình ảnh giảm đáng kể.\n\n"
    @"Lưu ý: số lượng pixel không giảm tuyến tính theo phần trăm chiều rộng. Scale 0.70 chỉ còn khoảng 49% số pixel so với gốc, vì 0.70 × 0.70 = 0.49.\n\n"
    @"Cách sử dụng đề xuất\n"
    @"1. Bật \"Tối ưu tổng\" ở thanh tiêu đề.\n"
    @"2. Chọn Target FPS phù hợp với màn hình.\n"
    @"3. Bật Dynamic Resolution.\n"
    @"4. Đặt Minimum Render Scale từ 0.65 đến 0.75.\n"
    @"5. Đặt Maximum Render Scale từ 0.90 đến 1.00.\n"
    @"6. Không nên đặt scale quá thấp nếu chữ hoặc chi tiết hình ảnh trở nên khó nhìn.\n"
    @"7. Nếu thiết bị nóng, nên giảm Target FPS trước khi giảm scale quá thấp.\n"
    @"8. Nếu hình ảnh nhấp nháy hoặc pipeline không tương thích, tắt Dynamic Resolution và dùng Manual Render Scale.\n"
    @"9. Nếu xảy ra lỗi hiển thị, nhấn \"Khôi phục cấu hình an toàn\" ở tab Trạng thái.\n\n"
    @"Tính năng Scale Resolution chủ yếu giảm tải GPU. Tối ưu CPU không thể tự động giảm mọi tải CPU nếu game có logic nặng trên main thread — CPU Optimization chỉ cung cấp callback để ứng dụng tự giảm việc phụ, không can thiệp trực tiếp vào logic game.\n\n"
    @"Cấu hình gợi ý\n\n"
    @"Chất lượng — Target FPS 60, Manual Render Scale 0.90, Min 0.80, Max 1.00.\n\n"
    @"Cân bằng — Target FPS 60, Manual Render Scale 0.75, Min 0.65, Max 0.90.\n\n"
    @"Mượt — Target FPS 45 hoặc 60, Manual Render Scale 0.65, Min 0.55, Max 0.80.\n\n"
    @"Thiết bị nóng — Target FPS 30 hoặc 45, Min 0.60, Max 0.75, bật chế độ tiết kiệm CPU, giảm tần suất cập nhật số liệu giao diện.\n\n"
    @"Các cấu hình trên chỉ là điểm khởi đầu. Kết quả phụ thuộc vào thiết bị, engine, khối lượng đồ họa và cách ứng dụng được tích hợp.\n\n"
    @"Cảnh báo an toàn\n"
    @"• Không thay đổi scale liên tục với tốc độ cao.\n"
    @"• Không đặt Minimum Scale lớn hơn Maximum Scale.\n"
    @"• Không đặt Target FPS cao hơn tần số quét màn hình.\n"
    @"• Không bật nhiều cơ chế điều khiển FPS cùng lúc.\n"
    @"• Không sử dụng trên ứng dụng bên thứ ba khi không có quyền.\n"
    @"• Không dùng để bypass hệ thống bảo vệ hoặc anti-cheat.";
}

@end
