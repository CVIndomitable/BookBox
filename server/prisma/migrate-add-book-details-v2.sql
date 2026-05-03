-- 书籍正式版详情字段迁移：在 books 表增加 改编、译者、作者国籍、出版人、责任编辑等字段
-- 运行方式：mysql -u <user> -p <database> < migrate-add-book-details-v2.sql
--
-- 将 publish_date 重命名为 edition（版次），并新增 16 个正式版字段。

START TRANSACTION;

-- 重命名 publish_date 为 edition
ALTER TABLE `books`
    CHANGE COLUMN `publish_date` `edition` VARCHAR(50) NULL AFTER `publisher`;

-- 新增字段
ALTER TABLE `books`
    ADD COLUMN IF NOT EXISTS `adaptation` VARCHAR(500) NULL AFTER `edition`,
    ADD COLUMN IF NOT EXISTS `translator` VARCHAR(500) NULL AFTER `adaptation`,
    ADD COLUMN IF NOT EXISTS `author_nationality` VARCHAR(100) NULL AFTER `translator`,
    ADD COLUMN IF NOT EXISTS `publisher_person` VARCHAR(200) NULL AFTER `author_nationality`,
    ADD COLUMN IF NOT EXISTS `responsible_editor` VARCHAR(200) NULL AFTER `publisher_person`,
    ADD COLUMN IF NOT EXISTS `responsible_printing` VARCHAR(200) NULL AFTER `responsible_editor`,
    ADD COLUMN IF NOT EXISTS `cover_design` VARCHAR(200) NULL AFTER `responsible_printing`,
    ADD COLUMN IF NOT EXISTS `phone` VARCHAR(50) NULL AFTER `cover_design`,
    ADD COLUMN IF NOT EXISTS `address` VARCHAR(500) NULL AFTER `phone`,
    ADD COLUMN IF NOT EXISTS `postal_code` VARCHAR(20) NULL AFTER `address`,
    ADD COLUMN IF NOT EXISTS `printing_house` VARCHAR(200) NULL AFTER `postal_code`,
    ADD COLUMN IF NOT EXISTS `impression` VARCHAR(50) NULL AFTER `printing_house`,
    ADD COLUMN IF NOT EXISTS `format` VARCHAR(100) NULL AFTER `impression`,
    ADD COLUMN IF NOT EXISTS `printed_sheets` VARCHAR(50) NULL AFTER `format`,
    ADD COLUMN IF NOT EXISTS `word_count` VARCHAR(50) NULL AFTER `printed_sheets`;

COMMIT;
