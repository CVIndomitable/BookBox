-- 书籍补充详情迁移：在 books 表增加出版时间和价格字段
-- 运行方式：mysql -u <user> -p <database> < migrate-add-book-details.sql
--
-- publish_date 用 VARCHAR 而不是 DATE：出版时间来源格式多样（豆瓣/当当/版权页），
-- 有时只有年份或"2023年5月"这种非标日期，强转 DATE 会丢信息。
-- price 用 DECIMAL(10,2) 精确存储人民币定价。

START TRANSACTION;

ALTER TABLE `books`
    ADD COLUMN IF NOT EXISTS `publish_date` VARCHAR(50) NULL AFTER `publisher`,
    ADD COLUMN IF NOT EXISTS `price` DECIMAL(10, 2) NULL AFTER `publish_date`;

COMMIT;
