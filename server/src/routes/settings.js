import { Router } from 'express';
import prisma from '../utils/prisma.js';

const router = Router();

// 获取/初始化用户设置（单用户系统，只有一条记录）
async function getOrCreateSettings() {
  let settings = await prisma.userSetting.findFirst();
  if (!settings) {
    settings = await prisma.userSetting.create({ data: {} });
  }
  return settings;
}

// 获取用户设置
router.get('/', async (req, res, next) => {
  try {
    const settings = await getOrCreateSettings();
    // 不返回 API Key 明文，只返回是否已配置
    res.json({
      ...settings,
      llmApiKey: settings.llmApiKey ? '******' : null,
      hasLlmApiKey: !!settings.llmApiKey,
    });
  } catch (err) {
    next(err);
  }
});

// 更新设置
router.put('/', async (req, res, next) => {
  try {
    const {
      regionMode,
      llmProvider,
      llmApiKey,
      llmEndpoint,
      llmModel,
      llmSupportsSearch,
    } = req.body;

    const settings = await getOrCreateSettings();

    const data = {};
    if (regionMode !== undefined) data.regionMode = regionMode;
    if (llmProvider !== undefined) data.llmProvider = llmProvider;
    if (llmApiKey !== undefined) data.llmApiKey = llmApiKey;
    if (llmEndpoint !== undefined) data.llmEndpoint = llmEndpoint;
    if (llmModel !== undefined) data.llmModel = llmModel;
    if (llmSupportsSearch !== undefined)
      data.llmSupportsSearch = llmSupportsSearch;

    const updated = await prisma.userSetting.update({
      where: { id: settings.id },
      data,
    });

    res.json({
      ...updated,
      llmApiKey: updated.llmApiKey ? '******' : null,
      hasLlmApiKey: !!updated.llmApiKey,
    });
  } catch (err) {
    next(err);
  }
});

export default router;
