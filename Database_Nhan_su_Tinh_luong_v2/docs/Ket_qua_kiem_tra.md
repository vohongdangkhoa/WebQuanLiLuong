# Kết quả kiểm tra thiết kế

- table_count: 48
- foreign_key_count: 105
- column_count: 404
- trigger_count: 33
- parsed_statement_counts: {'02_tables.sql': 605, '03_indexes.sql': 98}
- static_assertions_passed: 839
- oracle_executed: False
- oracle_compiled: False

DDL đã qua parser Oracle dialect. PK và FK được đối chiếu từ mô hình. Các phép tính mẫu được tính độc lập bằng Decimal. Đây không phải bằng chứng PL/SQL đã biên dịch hay chạy trên Oracle. Chạy 09_oracle_tests.sql trên Oracle để xác nhận.
