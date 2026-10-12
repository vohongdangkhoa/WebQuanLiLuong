# Cách đọc ERD

ERD00_full có đủ 48 bảng, 404 cột và 105 FK. Dùng SVG để phóng to. Các ERD01 đến ERD08 hiện các cột trọng yếu và quan hệ trong nhóm; FK đi ra ngoài nhóm đọc ở ERD00 hoặc từ điển dữ liệu. PK là khóa chính, FK là khóa ngoại, ? là trường có thể NULL. Quan hệ biểu thị tham chiếu của mỗi dòng con tới 1 hoặc 0..1 dòng cha; cha có 0..* hoặc 0..1 dòng con theo unique key. DOT và PlantUML là mã nguồn chỉnh sửa được. Tên ngắn trong nhóm không thay thế DDL.
