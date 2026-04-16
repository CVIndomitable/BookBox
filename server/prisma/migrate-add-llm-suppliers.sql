-- LLM 供应商池迁移脚本
-- 1. 创建 llm_suppliers 表
-- 2. 将学鼎 Token 作为优先级 1（最高）的供应商接入
-- 3. 从 user_settings 迁移现有 MiMo 配置为优先级 200 的供应商
-- 优先级数字越小越优先。

CREATE TABLE IF NOT EXISTS `llm_suppliers` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(100) NOT NULL,
  `protocol` VARCHAR(20) NOT NULL DEFAULT 'anthropic',
  `endpoint` VARCHAR(500) NOT NULL,
  `api_key` VARCHAR(500) NOT NULL,
  `vision_model` VARCHAR(100) NULL,
  `text_model` VARCHAR(100) NULL,
  `priority` INT NOT NULL DEFAULT 100,
  `enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `timeout_ms` INT NOT NULL DEFAULT 120000,
  `note` TEXT NULL,
  `last_ok_at` DATETIME(3) NULL,
  `last_fail_at` DATETIME(3) NULL,
  `last_error` TEXT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `llm_suppliers_enabled_priority_idx` (`enabled`, `priority`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 种子：学鼎 Token（OpenAI 兼容协议，最高优先级）
INSERT INTO `llm_suppliers`
  (`name`, `protocol`, `endpoint`, `api_key`, `vision_model`, `text_model`, `priority`, `enabled`, `note`, `created_at`, `updated_at`)
VALUES
  ('xueding', 'openai', 'https://xuedingtoken.com/v1',
   'sk-fdcf098446305478f9918c991c208ab4bb909ec270ce8512973713fc6e37eba0',
   'gpt-4o', 'gpt-4o-mini', 1, 1,
   '学鼎 Token 聚合站，OpenAI 兼容协议', NOW(3), NOW(3));

-- 种子：MiMo —— 从 user_settings 迁移，没有则跳过
INSERT INTO `llm_suppliers`
  (`name`, `protocol`, `endpoint`, `api_key`, `vision_model`, `text_model`, `priority`, `enabled`, `note`, `created_at`, `updated_at`)
SELECT
  'mimo',
  'anthropic',
  COALESCE(`llm_endpoint`, 'https://api.xiaomimimo.com/anthropic'),
  `llm_api_key`,
  COALESCE(`llm_model`, 'mimo-v2-omni'),
  'mimo-v2-flash',
  200,
  1,
  '小米 MiMo 多模态，作为备用供应商',
  NOW(3), NOW(3)
FROM `user_settings`
WHERE `llm_api_key` IS NOT NULL AND `llm_api_key` <> ''
LIMIT 1;

-- 如果 user_settings 里没有 MiMo 配置，也补一条占位（禁用状态，避免误用）
INSERT INTO `llm_suppliers`
  (`name`, `protocol`, `endpoint`, `api_key`, `vision_model`, `text_model`, `priority`, `enabled`, `note`, `created_at`, `updated_at`)
SELECT
  'mimo', 'anthropic', 'https://api.xiaomimimo.com/anthropic',
  '', 'mimo-v2-omni', 'mimo-v2-flash', 200, 0,
  '占位：尚未填写 API Key，已禁用',
  NOW(3), NOW(3)
WHERE NOT EXISTS (SELECT 1 FROM `llm_suppliers` WHERE `name` = 'mimo');
