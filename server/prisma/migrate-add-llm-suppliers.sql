-- LLM 供应商池迁移脚本
-- 1. 创建 llm_suppliers 表
-- 2. 学鼎 Token：仅作为文本模型，优先级最高（不接入视觉）
-- 3. 从 user_settings 迁移现有 MiMo 配置：视觉 + 文本兜底
-- 优先级数字越小越优先；vision_model / text_model 为 NULL 表示该供应商不参与对应类型的调用。

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

-- 种子：学鼎 Token —— 仅作为文本模型，优先级最高（Anthropic 兼容，Claude Sonnet 4.5）
-- vision_model 留空，视觉调用会自动跳过该供应商。
INSERT INTO `llm_suppliers`
  (`name`, `protocol`, `endpoint`, `api_key`, `vision_model`, `text_model`, `priority`, `enabled`, `note`, `created_at`, `updated_at`)
VALUES
  ('xueding', 'anthropic', 'https://xuedingtoken.com',
   'sk-fdcf098446305478f9918c991c208ab4bb909ec270ce8512973713fc6e37eba0',
   NULL, 'claude-sonnet-4-5-20250929', 1, 1,
   '学鼎 Token 聚合站：仅文本模型，不参与视觉识别', NOW(3), NOW(3));

-- 种子：MiMo —— 从 user_settings 迁移 API Key；视觉 + 文本兜底
-- 视觉：mimo-v2-omni（多模态）；文本：mimo-v2-flash（对话）。
INSERT INTO `llm_suppliers`
  (`name`, `protocol`, `endpoint`, `api_key`, `vision_model`, `text_model`, `priority`, `enabled`, `note`, `created_at`, `updated_at`)
SELECT
  'mimo',
  'anthropic',
  COALESCE(`llm_endpoint`, 'https://api.xiaomimimo.com/anthropic'),
  `llm_api_key`,
  'mimo-v2-omni',
  'mimo-v2-flash',
  100,
  1,
  '小米 MiMo：视觉主力（mimo-v2-omni）+ 文本兜底（mimo-v2-flash）',
  NOW(3), NOW(3)
FROM `user_settings`
WHERE `llm_api_key` IS NOT NULL AND `llm_api_key` <> ''
LIMIT 1;

-- 如果 user_settings 里没有 MiMo 配置，也补一条占位（禁用状态，避免误用）
INSERT INTO `llm_suppliers`
  (`name`, `protocol`, `endpoint`, `api_key`, `vision_model`, `text_model`, `priority`, `enabled`, `note`, `created_at`, `updated_at`)
SELECT
  'mimo', 'anthropic', 'https://api.xiaomimimo.com/anthropic',
  '', 'mimo-v2-omni', 'mimo-v2-flash', 100, 0,
  '占位：尚未填写 API Key，已禁用',
  NOW(3), NOW(3)
WHERE NOT EXISTS (SELECT 1 FROM `llm_suppliers` WHERE `name` = 'mimo');
