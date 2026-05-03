-- 分类系统与图书馆缓存迁移脚本
-- 1. 给 categories 添加 category_type 字段
-- 2. 给 libraries 添加 library_type 字段
-- 3. 给 books 添加 cache_source_book_id 字段
-- 4. 写入 22 条法定分类（中图法）
-- 5. 创建系统隐藏书库"图书馆"

-- 1. categories 表添加 category_type
ALTER TABLE `categories` ADD COLUMN `category_type` VARCHAR(20) NOT NULL DEFAULT 'user' AFTER `parent_id`;
ALTER TABLE `categories` ADD INDEX `categories_category_type_idx` (`category_type`);

-- 2. libraries 表添加 library_type
ALTER TABLE `libraries` ADD COLUMN `library_type` VARCHAR(20) NOT NULL DEFAULT 'user' AFTER `sun_days`;

-- 3. books 表添加 cache_source_book_id
ALTER TABLE `books` ADD COLUMN `cache_source_book_id` INT NULL AFTER `deleted_at`;
ALTER TABLE `books` ADD INDEX `books_cache_source_book_id_idx` (`cache_source_book_id`);

-- 4. 写入 22 条法定分类
INSERT INTO `categories` (`name`, `parent_id`, `category_type`) VALUES
('A-马克思主义', NULL, 'statutory'),
('B-哲学宗教', NULL, 'statutory'),
('C-社会科学总论', NULL, 'statutory'),
('D-政治法律', NULL, 'statutory'),
('E-军事', NULL, 'statutory'),
('F-经济', NULL, 'statutory'),
('G-文化科学教育体育', NULL, 'statutory'),
('H-语言文字', NULL, 'statutory'),
('I-文学', NULL, 'statutory'),
('J-艺术', NULL, 'statutory'),
('K-历史地理', NULL, 'statutory'),
('N-自然科学总论', NULL, 'statutory'),
('O-数理科学和化学', NULL, 'statutory'),
('P-天文学地球科学', NULL, 'statutory'),
('Q-生物科学', NULL, 'statutory'),
('R-医药卫生', NULL, 'statutory'),
('S-农业科学', NULL, 'statutory'),
('T-工业技术', NULL, 'statutory'),
('U-交通运输', NULL, 'statutory'),
('V-航空航天', NULL, 'statutory'),
('X-环境科学', NULL, 'statutory'),
('Z-综合性图书', NULL, 'statutory');

-- 5. 创建系统隐藏书库"图书馆"
INSERT INTO `libraries` (`name`, `description`, `library_type`, `created_at`, `updated_at`)
VALUES ('图书馆', '系统隐藏书库，用作AI识别缓存与书籍回收', 'system', NOW(3), NOW(3));
