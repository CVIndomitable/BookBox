-- 房间层级迁移：在书库和书架/箱子之间新增房间
-- 运行方式：mysql -u <user> -p <database> < migrate-add-rooms.sql
--
-- 逻辑：
-- 1. 新建 rooms 表
-- 2. 在 shelves / boxes 表上添加 room_id 字段
-- 3. 为每个现有书库创建一个"默认房间"
-- 4. 将现有的 shelves / boxes 的 room_id 指向各自书库的默认房间
--    （libraryId 为 NULL 的 shelves/boxes 保持 room_id = NULL）

START TRANSACTION;

-- 1. 创建 rooms 表
CREATE TABLE IF NOT EXISTS `rooms` (
    `id`          INT AUTO_INCREMENT PRIMARY KEY,
    `name`        VARCHAR(200) NOT NULL,
    `description` TEXT NULL,
    `is_default`  BOOLEAN NOT NULL DEFAULT FALSE,
    `library_id`  INT NOT NULL,
    `created_at`  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updated_at`  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    INDEX `rooms_library_id_idx` (`library_id`),
    CONSTRAINT `rooms_library_id_fkey`
        FOREIGN KEY (`library_id`) REFERENCES `libraries`(`id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- 2. shelves 加 room_id
ALTER TABLE `shelves`
    ADD COLUMN IF NOT EXISTS `room_id` INT NULL AFTER `library_id`,
    ADD INDEX IF NOT EXISTS `shelves_room_id_idx` (`room_id`),
    ADD CONSTRAINT `shelves_room_id_fkey`
        FOREIGN KEY (`room_id`) REFERENCES `rooms`(`id`)
        ON DELETE SET NULL ON UPDATE CASCADE;

-- 3. boxes 加 room_id
ALTER TABLE `boxes`
    ADD COLUMN IF NOT EXISTS `room_id` INT NULL AFTER `library_id`,
    ADD INDEX IF NOT EXISTS `boxes_room_id_idx` (`room_id`),
    ADD CONSTRAINT `boxes_room_id_fkey`
        FOREIGN KEY (`room_id`) REFERENCES `rooms`(`id`)
        ON DELETE SET NULL ON UPDATE CASCADE;

-- 4. 为每个现有书库创建"默认房间"
INSERT INTO `rooms` (`name`, `is_default`, `library_id`, `created_at`, `updated_at`)
SELECT '默认房间', TRUE, `id`, NOW(3), NOW(3)
FROM `libraries`
WHERE `id` NOT IN (
    SELECT DISTINCT `library_id` FROM `rooms` WHERE `is_default` = TRUE
);

-- 5. 回填现有 shelves.room_id 为所属书库的默认房间
UPDATE `shelves` s
JOIN `rooms` r ON r.`library_id` = s.`library_id` AND r.`is_default` = TRUE
SET s.`room_id` = r.`id`
WHERE s.`library_id` IS NOT NULL AND s.`room_id` IS NULL;

-- 6. 回填现有 boxes.room_id 为所属书库的默认房间
UPDATE `boxes` b
JOIN `rooms` r ON r.`library_id` = b.`library_id` AND r.`is_default` = TRUE
SET b.`room_id` = r.`id`
WHERE b.`library_id` IS NOT NULL AND b.`room_id` IS NULL;

COMMIT;

-- 验证（可选）
-- SELECT l.name AS library, r.name AS room, r.is_default
-- FROM libraries l LEFT JOIN rooms r ON r.library_id = l.id;
