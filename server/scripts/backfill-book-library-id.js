// 历史数据回填：把 books.libraryId 与当前位置对齐
//   - 在书架/箱子里的书 → 容器所在书库
//   - 未归位（location_type='none'）的书 → libraryId 置 null
// 用法：node server/scripts/backfill-book-library-id.js
import prisma from '../src/utils/prisma.js';

async function main() {
  const stats = await prisma.$transaction(async (tx) => {
    let shelfUpdated = 0;
    let boxUpdated = 0;
    let noneCleared = 0;

    const shelves = await tx.shelf.findMany({
      where: { libraryId: { not: null } },
      select: { id: true, libraryId: true },
    });
    for (const shelf of shelves) {
      const result = await tx.book.updateMany({
        where: {
          locationType: 'shelf',
          locationId: shelf.id,
          OR: [{ libraryId: null }, { libraryId: { not: shelf.libraryId } }],
        },
        data: { libraryId: shelf.libraryId },
      });
      shelfUpdated += result.count;
    }

    const boxes = await tx.box.findMany({
      where: { libraryId: { not: null } },
      select: { id: true, libraryId: true },
    });
    for (const box of boxes) {
      const result = await tx.book.updateMany({
        where: {
          locationType: 'box',
          locationId: box.id,
          OR: [{ libraryId: null }, { libraryId: { not: box.libraryId } }],
        },
        data: { libraryId: box.libraryId },
      });
      boxUpdated += result.count;
    }

    // 未归位的书没有容器 → 没有书库归属
    const noneResult = await tx.book.updateMany({
      where: { locationType: 'none', libraryId: { not: null } },
      data: { libraryId: null },
    });
    noneCleared = noneResult.count;

    return { shelfUpdated, boxUpdated, noneCleared };
  });

  console.log(
    `✅ 回填完成：书架 ${stats.shelfUpdated} 本、箱子 ${stats.boxUpdated} 本、未归位清空 ${stats.noneCleared} 本`
  );
}

main()
  .catch((err) => {
    console.error('回填失败：', err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
