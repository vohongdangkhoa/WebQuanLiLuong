# Database Oracle cho Web quản lý nhân sự và tính lương

Bản 2.0, ngày 09 tháng 10 năm 2026. Thiết kế phục vụ đồ án của Khoa, dùng Oracle 23ai hoặc 26ai Free trên Docker và DBeaver. Đây là bộ SQL và bản thiết kế mới để triển khai trên schema trống; chưa tạo hay thay đổi database trên máy bạn.

## Sản phẩm trong bộ này

- 48 bảng: 47 bảng nghiệp vụ và một bảng khóa kỹ thuật; 105 khóa ngoại.
- DDL, CHECK, UNIQUE, index chống trùng phiên bản và thanh toán.
- 6 package: kiểm tra nội bộ, HR, tính và duyệt lương, thanh toán, đọc phiếu lương, xử lý đơn và tệp đối soát.
- 33 trigger: bất biến, kiểm tra khoảng hiệu lực, chống chồng ca, chống chu trình phòng ban, khóa nguồn, tăng phiên bản đầu vào và audit trước sau.
- Dữ liệu demo 3 phòng ban và 3 nhân viên. SQL test luồng chính; các ca mở rộng và kiểm tra đồng thời được mô tả trong tài liệu Word.
- ERD đầy đủ, ERD theo 8 nhóm, từ điển 404 cột và mô hình JSON.

## Đọc theo thứ tự

1. Tài liệu Word để hiểu các quyết định nghiệp vụ.
2. `erd/ERD00_full.svg` để phóng to toàn hệ thống; ERD nhóm để trình bày báo cáo.
3. `docs/Tu_dien_du_lieu.md` và `schema_model.json` để đối chiếu từng trường.
4. SQL theo quy trình bên dưới. Đừng chạy file admin bằng tài khoản của bài lab.

## Chạy từng bước

1. Mở Docker Desktop và bật container Oracle hiện có. Nếu container tên `oracle23ai`, PowerShell dùng `docker start oracle23ai` khi container đang tắt.
2. DBeaver tạo kết nối SYSTEM, host `localhost`, port `1521`, Service name `FREEPDB1`, Role Normal. Kiểm tra `SELECT SYS_CONTEXT('USERENV','CON_NAME') FROM dual;` phải ra FREEPDB1.
3. File `01_admin.sql` dùng lệnh ACCEPT của SQL*Plus. Trong PowerShell mở `docker exec -it oracle23ai sqlplus system@//localhost:1521/FREEPDB1`, nhập mật khẩu khi được hỏi. Chép thư mục SQL vào container rồi chạy file admin, hoặc tự chạy các câu CREATE USER trong DBeaver sau khi thay hai mật khẩu bằng giá trị riêng. Không chạy nguyên ACCEPT trong DBeaver.
4. Tạo PAYROLL_APP và PAYROLL_API. Nếu đã có schema này, dùng schema thử nghiệm khác và đổi các tên trong file admin/grants; không xóa schema đang có dữ liệu.
5. Kết nối PAYROLL_APP vào FREEPDB1. Kiểm tra user và current schema trước khi chạy file tạo bảng.
6. Nếu dùng SQL*Plus, chép toàn bộ SQL vào một thư mục và chạy `@00_install_owner.sql`. Nếu dùng DBeaver, chạy các file 02, 03, 04, 05, 06, 06b, 07, 10, 11 lần lượt bằng Execute SQL Script. Cấu hình DBeaver nhận `/` là dấu kết thúc khối PL/SQL; các lệnh SET/WHENEVER/PROMPT/@@ là lệnh SQL*Plus, cần bỏ qua trong DBeaver. Không dùng Ctrl+Enter để chạy cả nhiều khối cùng lúc.
7. Kiểm tra USER_ERRORS phải không có dòng và USER_OBJECTS không có INVALID. Chưa qua bước này thì dừng; gửi lỗi tên object, line, position, text để sửa.
8. Chạy `08_demo_data.sql`, rồi `09_oracle_tests.sql`. Test ghi PASS bằng DBMS_OUTPUT, cuối cùng rollback dữ liệu test. Dữ liệu mẫu gốc vẫn còn, số identity có thể nhảy là bình thường.
9. Kết nối Web bằng PAYROLL_API. Account này chỉ được EXECUTE 5 package công khai; không được sửa hay đọc trực tiếp bảng và không được gọi PKG_PAYROLL_INTERNAL.

### Kiểm tra kết nối

```sql
SELECT USER,
       SYS_CONTEXT('USERENV','CURRENT_SCHEMA') AS schema_name,
       SYS_CONTEXT('USERENV','CON_NAME') AS pdb_name
FROM dual;
```

Khi cài bảng, phải là PAYROLL_APP, PAYROLL_APP, FREEPDB1. Giữ SCHOOLDB/SV_LAB riêng cho bài thực hành.

### Chép SQL vào container

Giả sử giải nén vào `C:\PayrollDatabase` và có thư mục `sql` bên trong:

```powershell
docker cp C:\PayrollDatabase\sql oracle23ai:/tmp/payroll_sql
docker exec -it oracle23ai sqlplus system@//localhost:1521/FREEPDB1
```

Trong SQL*Plus chạy `@/tmp/payroll_sql/01_admin.sql`. Sau đó thoát và đăng nhập PAYROLL_APP, chạy `@/tmp/payroll_sql/00_install_owner.sql`. Không ghi mật khẩu thật vào lịch sử lệnh hoặc Git.

## Nghiệp vụ đã cố định

- Một doanh nghiệp, VND, kỳ tháng dương lịch, nhân viên cư trú hưởng lương tháng trong engine demo.
- Khoảng hiệu lực là `[valid_from, valid_to)`. Ngày cuối cùng đi làm nằm trong EMPLOYEE.termination_date; contract.valid_to là ngày đầu tiên không còn áp dụng. Hai hợp đồng tiếp giáp cùng ngày không chồng nhau.
- Mỗi nhân viên có một ca chính và một bản ghi công mỗi ngày; OT được lưu riêng. Ngày nghỉ có bản ghi công 0 để chứng minh đã xử lý.
- Lương cơ bản phân bổ theo tổng phút chuẩn của lịch cả tháng. Có thay đổi lương giữa kỳ thì tính từng ngày theo hợp đồng có hiệu lực ngày đó.
- Phép hưởng lương và ngày lễ hưởng lương cộng vào paid_minutes; OT không cộng vào paid_minutes. HR chứng nhận dữ liệu ngày sau khi đối chiếu đơn và máy chấm công.
- Một bộ PAYROLL_POLICY đã duyệt phải phủ trọn tháng. Nếu chính sách đổi giữa tháng, engine báo lỗi; cần triển khai phiên bản engine mới có phân đoạn chính sách trước khi dùng tình huống đó.
- Bảo hiểm demo dùng mức cơ sở của hợp đồng cuối cùng trong thời gian có việc tháng đó, trần và hai tỷ lệ tổng hợp. Điều kiện miễn/giảm theo số ngày nghỉ, từng quỹ bảo hiểm và trường hợp thuế đặc biệt chưa được mã hóa trong engine này.
- Mốc đêm demo là 22 giờ đến 06 giờ. Confirm OT xử lý một khoảng thực làm liên tục, lấy phần giao với khoảng đăng ký và giới hạn theo phút được duyệt; chia ở 00, 06 và 22 giờ. Nhiều khoảng nghỉ trong OT cần bảng khoảng thực làm riêng trước khi mở rộng.
- Tiền làm tròn trên từng PAYROLL_ITEM theo round_scale; tổng lương là tổng các dòng đã làm tròn. Đây là chính sách đồ án, có thể khác doanh nghiệp thực tế.
- Khấu trừ tự nguyện phải có DEDUCTION_ACCOUNT. Chỉ ghi tăng collected_amount khi giám đốc duyệt, không tăng khi tính nháp hoặc trả tiền. Khoản dư ở tài khoản, muốn thu kỳ sau phải tạo BONUS_DEDUCTION được duyệt cho kỳ sau.
- Không hủy bảng lương đã duyệt trong engine này. Sai sót sau duyệt chuyển thành bút toán điều chỉnh ở kỳ sau, liên kết origin_result_id và có duyệt.
- Phiếu lương phát hành sau phê duyệt; trạng thái thanh toán hiển thị riêng. Nhân viên có thể xem phiếu đã duyệt trước khi ngân hàng xác nhận trả tiền.
- Đây là điều chỉnh so với kế hoạch trước phát hành phiếu sau đối soát: bản 2.0 phát hành phiếu sau duyệt và luôn ghi trạng thái đã trả/chưa trả riêng, để không nhầm phiếu được công bố với tiền đã nhận.
- Tải lại file đã xuất giữ nguyên batch và reference. Các khoản PROCESSING chưa rõ kết quả không được retry. FAILED mới có lần thử tiếp theo.
- Database giữ snapshot ngân hàng mã hóa. API giữ khóa mã hóa và HMAC ngoài database, kiểm tra quyền tải tệp rồi mới giải mã khi tạo file ngân hàng.

## Package đã viết và việc Web cần bổ sung

SQL thực hiện save_day, chốt/mở lại công, tính lương, tạo phiên bản, gửi/duyệt/từ chối, tạo batch, xuất/gửi/đối soát, đóng kỳ, đọc phiếu của chính mình, báo cáo, duyệt phép và xác nhận OT. Các procedure nghiệp vụ không COMMIT; API commit một request hoặc rollback khi lỗi.

Schema bao phủ các màn hình đã thiết kế. CRUD hồ sơ, thêm hợp đồng chờ duyệt, phê duyệt chính sách, nhập máy chấm công, quản lý role, cập nhật người phụ thuộc và nghiệp vụ điều chỉnh công đầy đủ vẫn cần API/package theo đặc tả trong Word. Không cấp DML cho PAYROLL_API để làm tắt; bổ sung package có kiểm tra quyền, trạng thái, khoảng ngày và audit. Đồ án chưa có frontend/backend được lập trình từ bộ SQL này.

`p_actor` là danh tính mà API đã xác thực và tự lấy từ claims. Không nhận p_actor từ JSON/URL và không gửi tài khoản Oracle tới trình duyệt. Database kiểm tra vai trò của actor nhưng không tự kiểm chứng JWT. Nếu lộ credential PAYROLL_API, người có credential có thể giả actor; cần giữ credential ở máy chủ. Schema owner có khả năng vô hiệu trigger, nên owner chỉ dùng cài đặt và bảo trì.

## Điều chỉnh so với bộ 28 bảng

POSITION đổi thành JOB_POSITION. DEPENDENT tách DEPENDENT_PERSON và DEPENDENT_CLAIM. ALLOWANCE_TYPE đổi thành PAY_COMPONENT để dùng chung khoản cộng, trừ và chi phí công ty. Các tên còn lại giữ phần nghiệp vụ tương ứng. Thêm lịch, phân bổ phép, sổ phép, định danh tệp, snapshot, lỗi tính, yêu cầu sửa, nợ khấu trừ, bằng chứng ngân hàng, phiếu và thông báo. Không chuyển dữ liệu cũ tự động: bản này chưa có migration từ schema khác.

## Kết quả kiểm tra hiện tại

Đã đối chiếu PK/FK và parse DDL bằng Oracle dialect, kiểm tra công thức mẫu bằng Decimal độc lập. Không có Oracle đang chạy ở môi trường tạo tài liệu, nên chưa biên dịch/chạy package hoặc trigger trên Oracle. `docs/Ket_qua_kiem_tra.md` ghi chính xác phạm vi đã kiểm tra. Bộ 09 là test để chạy trên Docker Oracle của bạn; chưa được tuyên bố là đã PASS trên Oracle.

## Nguồn

Bốn PDF môn học người dùng gửi ngày 09/10/2026 và kế hoạch Web hiện có. Tài liệu Oracle chính thức được đối chiếu: https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html ; https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-INDEX.html ; https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/plsql-triggers.html ; https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/Data-Types.html .
