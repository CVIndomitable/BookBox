-- 补丁脚本：学鼎改为纯文本模型（最高优先级），不再参与视觉识别
-- 背景：之前的 migrate-add-llm-suppliers.sql 给学鼎同时配置了 vision_model，
-- 实际学鼎走的是 Claude 路由，没有 MiMo 的多模态书脊识别能力，故从视觉池中撤出。
-- 对已执行过旧版 migrate-add-llm-suppliers.sql 的库，执行本脚本将其校正。

UPDATE `llm_suppliers`
SET
  `protocol`     = 'anthropic',
  `endpoint`     = 'https://xuedingtoken.com',
  `vision_model` = NULL,
  `text_model`   = 'claude-sonnet-4-5-20250929',
  `priority`     = 1,
  `enabled`      = 1,
  `note`         = '学鼎 Token 聚合站：仅文本模型，不参与视觉识别',
  `updated_at`   = NOW(3)
WHERE `name` = 'xueding';
