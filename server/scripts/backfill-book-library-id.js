// 历史数据回填：把 books.libraryId 设置为其当前书架/箱子所在书库
// 用法：node server/scripts/backfill-book-library-id.js
import prisma from '../src/utils/prisma.js';

async function main() {
  const shelves = await prisma.shelf.findMany({
    where: { libraryId: { not: null } },
    select: { id: true, libraryId: true },
  });

  let shelfUpdated = 0;
  for (const shelf of shelves) {
    const result = await prisma.book.updateMany({
      where: {
        locationType: 'shelf',
        locationId: shelf.id,
        OR: [{ libraryId: null }, { libraryId: { not: shelf.libraryId } }],
      },
      data: { libraryId: shelf.libraryId },
    });
    shelfUpdated += result.count;
  }

  const boxes = await prisma.box.findMany({
    where: { libraryId: { not: null } },
    select: { id: true, libraryId: true },
  });

  let boxUpdated = 0;
  for (const box of boxes) {
    const result = await prisma.book.updateMany({
      where: {
        locationType: 'box',
        locationId: box.id,
        OR: [{ libraryId: null }, { libraryId: { not: box.libraryId } }],
      },
      data: { libraryId: box.libraryId },
    });
    boxUpdated += result.count;
  }

  console.log(`✅ 回填完成：书架内书籍 ${shelfUpdated} 本、箱子内书籍 ${boxUpdated} 本`);
}

main()
  .catch((err) => {
    console.error('回填失败：', err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
