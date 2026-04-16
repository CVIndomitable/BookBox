// 一次性迁移：把 llm_suppliers.api_key 的明文加密为 enc:v1:... 格式
//
// 运行方式（在 server/ 目录下）：
//   node prisma/migrate-encrypt-api-keys.js
//
// 需要提前在 .env 中配置 SUPPLIER_ENCRYPTION_KEY（64 位十六进制）。
// 已加密的行会被跳过，可以重复执行。

import 'dotenv/config';
import prisma from '../src/utils/prisma.js';
import { encrypt, isEncrypted, isEncryptionConfigured } from '../src/utils/crypto.js';

async function main() {
  if (!isEncryptionConfigured()) {
    console.error('❌ SUPPLIER_ENCRYPTION_KEY 未配置，无法迁移');
    process.exit(1);
  }

  const suppliers = await prisma.llmSupplier.findMany({
    select: { id: true, name: true, apiKey: true },
  });

  let encrypted = 0;
  let skipped = 0;
  for (const s of suppliers) {
    if (!s.apiKey) {
      skipped++;
      continue;
    }
    if (isEncrypted(s.apiKey)) {
      skipped++;
      continue;
    }
    const cipher = encrypt(s.apiKey);
    await prisma.llmSupplier.update({
      where: { id: s.id },
      data: { apiKey: cipher },
    });
    console.log(`✓ 已加密 ${s.name} (id=${s.id})`);
    encrypted++;
  }

  console.log(`\n迁移完成：加密 ${encrypted} 条，跳过 ${skipped} 条`);
  await prisma.$disconnect();
}

main().catch(async (err) => {
  console.error('迁移失败:', err);
  await prisma.$disconnect();
  process.exit(1);
});
