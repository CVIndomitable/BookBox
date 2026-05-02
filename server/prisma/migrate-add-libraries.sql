-- 多书库支持迁移脚本
-- 1. 创建 libraries 表
-- 2. 给 books/shelves/boxes 添加 library_id 字段
-- 3. 创建默认书库，将现有数据归入

-- 创建 libraries 表
CREATE TABLE IF NOT EXISTS `libraries` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(200) NOT NULL,
  `location` VARCHAR(200) NULL,
  `description` TEXT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL,
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 给 books 添加 library_id
ALTER TABLE `books` ADD COLUMN `library_id` INT NULL;
ALTER TABLE `books` ADD INDEX `books_library_id_idx` (`library_id`);

-- 给 shelves 添加 library_id
ALTER TABLE `shelves` ADD COLUMN `library_id` INT NULL;
ALTER TABLE `shelves` ADD INDEX `shelves_library_id_idx` (`library_id`);

-- 给 boxes 添加 library_id
ALTER TABLE `boxes` ADD COLUMN `library_id` INT NULL;
ALTER TABLE `boxes` ADD INDEX `boxes_library_id_idx` (`library_id`);

-- 创建默认书库
INSERT INTO `libraries` (`name`, `location`, `description`, `created_at`, `updated_at`)
VALUES ('默认书库', NULL, '系统自动创建的默认书库', NOW(3), NOW(3));

-- 将现有数据归入默认书库（ID=1）
SET @default_lib_id = LAST_INSERT_ID();
UPDATE `books` SET `library_id` = @default_lib_id WHERE `library_id` IS NULL;
UPDATE `shelves` SET `library_id` = @default_lib_id WHERE `library_id` IS NULL;
UPDATE `boxes` SET `library_id` = @default_lib_id WHERE `library_id` IS NULL;
