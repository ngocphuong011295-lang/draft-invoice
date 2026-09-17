# Hóa đơn nháp iPOS

Web app 1 file (`index.html`) để lập **hóa đơn GTGT nháp** theo đúng mẫu M-Invoice của iPOS.vn: form bên trái, preview A4 bên phải, xuất PDF qua hộp thoại in của Chrome/Edge. Danh mục hàng hóa, danh mục đối tượng và nháp đã lưu dùng chung cho cả phòng qua Supabase (có đăng nhập).

## Cài đặt lần đầu

> Đã cấu hình xong (09/2026): project Supabase `tvlkclsvomatoaqiwhqb` (Singapore), schema đã chạy, 385 hàng hóa + 18.705 đối tượng đã nhập, `index.html` đã có URL + anon key. Phần dưới chỉ cần khi dựng lại từ đầu.

### 1. Supabase (cơ sở dữ liệu + đăng nhập)
1. Vào https://supabase.com → **New project** (chọn region Singapore cho nhanh).
2. Mở **SQL Editor** → dán toàn bộ file [`supabase/schema.sql`](supabase/schema.sql) → **Run**.
   Script tạo bảng, phân quyền và tài khoản admin mặc định **`admin` / `123`** — đổi mật khẩu ngay sau khi đăng nhập.
3. Vào **Project Settings → API**, copy **Project URL** và **anon public key**.
4. Mở `index.html`, điền vào khối `window.APP_CONFIG` ở gần cuối file:
   ```js
   window.APP_CONFIG = {
     SUPABASE_URL: 'https://xxxx.supabase.co',
     SUPABASE_ANON_KEY: 'eyJ...',
     AUTH_DOMAIN: 'ipos.local'
   };
   ```
   (anon key là khóa công khai; dữ liệu được bảo vệ bằng RLS + đăng nhập.)
5. Commit & push.

### 2. Vercel (link online)
1. https://vercel.com → **Add New → Project** → Import repo GitHub này.
2. Framework: **Other**, không cần build command, Output = thư mục gốc → **Deploy**.
3. Mỗi lần push lên `main`, Vercel tự deploy lại.

## Sử dụng
- Đăng nhập bằng **tên đăng nhập** (không cần email). Admin tạo tài khoản cho người khác tại **⋯ → Quản lý tài khoản đăng nhập**.
- **Danh mục hàng hóa** (mã hàng, tên, ĐVT, thuế suất, đơn giá đã gồm VAT) và **Danh mục đối tượng** (mã đối tượng, tên, MST, địa chỉ…): thêm/sửa/xóa trực tiếp hoặc **Nhập từ Excel** (copy vùng dữ liệu → dán).
- Lập hóa đơn: chọn đối tượng ở ô **Chọn đối tượng từ danh mục** → bấm **Chọn hàng hóa** tick các mặt hàng (hoặc gõ mã/tên ngay trên dòng) → gõ số lượng → **Xuất PDF** (Ctrl+P) → *Lưu dưới dạng PDF*. Tên file gợi ý: `HĐ nháp <Mã hợp đồng>.pdf`.
- ≤ 8 dòng luôn nằm gọn 1 trang A4; nhiều hơn thì tự sang trang.

## Chạy offline
Để trống `SUPABASE_URL` / `SUPABASE_ANON_KEY` → app chạy hoàn toàn trên trình duyệt (dữ liệu lưu trong máy, không cần mạng).

## Lưu ý
- Không commit file Excel/PDF chứa dữ liệu khách hàng thật (đã chặn trong `.gitignore`).
- Mật khẩu đổi trong app phải ≥ 6 ký tự (quy định của Supabase Auth); admin đặt lại mật khẩu cho người khác thì không bị giới hạn này.
