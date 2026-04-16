// 书籍联网校验：按地区优先级依次尝试 豆瓣 / Google Books / Open Library，
// 返回统一结构 { status, title, author, isbn, coverUrl, source }。
//
// 地区策略：
//   mainland → 豆瓣 → Open Library
//   overseas → Google Books → 豆瓣 → Open Library
//
// 匹配判定：
//   matched   — 归一化书名与搜索结果书名完全一致
//   uncertain — 存在候选但不完全匹配（部分包含）
//   not_found — 任何来源都无候选

import crypto from 'crypto';

// ---------- 进程内缓存 ----------
// 避免对同一书名重复请求外部服务；TTL 来自 SEARCH_CACHE_TTL（秒），默认 7 天
const CACHE_TTL_MS = (Number(process.env.SEARCH_CACHE_TTL) || 604800) * 1000;
const MAX_CACHE_ENTRIES = 2000;
const cache = new Map();

function cacheKey(title, region) {
  return crypto
    .createHash('md5')
    .update(`${region}|${normalizeTitle(title)}`)
    .digest('hex');
}

function cacheGet(key) {
  const hit = cache.get(key);
  if (!hit) return null;
  if (Date.now() - hit.createdAt > CACHE_TTL_MS) {
    cache.delete(key);
    return null;
  }
  return hit.value;
}

function cacheSet(key, value) {
  if (cache.size >= MAX_CACHE_ENTRIES) {
    // 粗粒度淘汰：删最早插入的一条
    const oldest = cache.keys().next().value;
    if (oldest) cache.delete(oldest);
  }
  cache.set(key, { value, createdAt: Date.now() });
}

// ---------- 归一化 / 匹配 ----------
function normalizeTitle(raw) {
  return String(raw || '')
    .toLowerCase()
    .replace(/\s+/g, '')
    .replace(/[《》〈〉「」『』"'‘’“”:：,，.。!！?？\-–—()（）\[\]【】]/g, '')
    .trim();
}

function matchStatus(queryTitle, candidateTitle) {
  const q = normalizeTitle(queryTitle);
  const c = normalizeTitle(candidateTitle);
  if (!q || !c) return 'not_found';
  if (q === c) return 'matched';
  if (c.includes(q) || q.includes(c)) return 'uncertain';
  return 'not_found';
}

// ---------- 通用带超时 fetch ----------
async function fetchWithTimeout(url, { timeoutMs = 5000, headers = {} } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      headers,
      signal: controller.signal,
    });
    if (!res.ok) {
      const err = new Error(`HTTP ${res.status}`);
      err.httpStatus = res.status;
      throw err;
    }
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

// ---------- 豆瓣（subject_suggest） ----------
// 豆瓣有反爬：串行调用 + 最小间隔（DOUBAN_REQUEST_INTERVAL ms）
const DOUBAN_INTERVAL = Number(process.env.DOUBAN_REQUEST_INTERVAL) || 3000;
let doubanLastCallAt = 0;
let doubanChain = Promise.resolve();

function throttleDouban() {
  doubanChain = doubanChain.then(async () => {
    const now = Date.now();
    const wait = Math.max(0, doubanLastCallAt + DOUBAN_INTERVAL - now);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    doubanLastCallAt = Date.now();
  });
  return doubanChain;
}

async function searchDouban(title) {
  await throttleDouban();
  const url = `https://book.douban.com/j/subject_suggest?q=${encodeURIComponent(title)}`;
  try {
    const data = await fetchWithTimeout(url, {
      timeoutMs: 6000,
      headers: {
        // 豆瓣 suggest 接口对无 UA 请求会返回空；使用常见浏览器 UA
        'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
        Accept: 'application/json, text/plain, */*',
        Referer: 'https://book.douban.com/',
      },
    });
    if (!Array.isArray(data) || data.length === 0) return null;
    const first = data[0];
    return {
      title: first.title || '',
      author: first.author_name || null,
      isbn: null, // suggest 接口不返回 ISBN
      coverUrl: first.pic || null,
      source: 'douban',
    };
  } catch (err) {
    console.warn('[verify/douban] 请求失败:', err.message);
    return null;
  }
}

// ---------- Google Books ----------
async function searchGoogleBooks(title) {
  const key = process.env.GOOGLE_BOOKS_API_KEY;
  const params = new URLSearchParams({ q: `intitle:${title}`, maxResults: '3' });
  if (key) params.append('key', key);
  const url = `https://www.googleapis.com/books/v1/volumes?${params.toString()}`;
  try {
    const data = await fetchWithTimeout(url, { timeoutMs: 6000 });
    const items = Array.isArray(data?.items) ? data.items : [];
    if (items.length === 0) return null;
    const info = items[0].volumeInfo || {};
    const identifiers = Array.isArray(info.industryIdentifiers) ? info.industryIdentifiers : [];
    const isbn13 = identifiers.find((i) => i.type === 'ISBN_13')?.identifier;
    const isbn10 = identifiers.find((i) => i.type === 'ISBN_10')?.identifier;
    return {
      title: info.title || '',
      author: Array.isArray(info.authors) ? info.authors.join(', ') : null,
      isbn: isbn13 || isbn10 || null,
      coverUrl: info.imageLinks?.thumbnail || info.imageLinks?.smallThumbnail || null,
      source: 'google_books',
    };
  } catch (err) {
    console.warn('[verify/google_books] 请求失败:', err.message);
    return null;
  }
}

// ---------- Open Library ----------
async function searchOpenLibrary(title) {
  const url = `https://openlibrary.org/search.json?title=${encodeURIComponent(title)}&limit=3`;
  try {
    const data = await fetchWithTimeout(url, { timeoutMs: 6000 });
    const docs = Array.isArray(data?.docs) ? data.docs : [];
    if (docs.length === 0) return null;
    const first = docs[0];
    const isbn = Array.isArray(first.isbn) ? first.isbn[0] : null;
    const coverUrl = first.cover_i
      ? `https://covers.openlibrary.org/b/id/${first.cover_i}-M.jpg`
      : null;
    return {
      title: first.title || '',
      author: Array.isArray(first.author_name) ? first.author_name.join(', ') : null,
      isbn,
      coverUrl,
      source: 'open_library',
    };
  } catch (err) {
    console.warn('[verify/open_library] 请求失败:', err.message);
    return null;
  }
}

// ---------- 主入口 ----------
const VERIFIERS = {
  mainland: [searchDouban, searchOpenLibrary],
  overseas: [searchGoogleBooks, searchDouban, searchOpenLibrary],
};

/**
 * 校验书籍信息
 * @param {string} title 原始书名
 * @param {'mainland'|'overseas'} region 地区模式
 * @returns {Promise<{status:string,title:string,author:string|null,isbn:string|null,coverUrl:string|null,source:string|null}>}
 */
export async function verifyBook(title, region = 'mainland') {
  const trimmed = String(title || '').trim();
  if (!trimmed) {
    return { status: 'not_found', title: '', author: null, isbn: null, coverUrl: null, source: null };
  }

  const key = cacheKey(trimmed, region);
  const cached = cacheGet(key);
  if (cached) return cached;

  const verifiers = VERIFIERS[region] || VERIFIERS.mainland;
  // 记录最佳候选：优先 matched，否则留第一个 uncertain 作为兜底
  let bestUncertain = null;

  for (const verify of verifiers) {
    const candidate = await verify(trimmed);
    if (!candidate || !candidate.title) continue;

    const status = matchStatus(trimmed, candidate.title);
    if (status === 'matched') {
      const result = {
        status: 'matched',
        title: candidate.title,
        author: candidate.author,
        isbn: candidate.isbn,
        coverUrl: candidate.coverUrl,
        source: candidate.source,
      };
      cacheSet(key, result);
      return result;
    }
    if (status === 'uncertain' && !bestUncertain) {
      bestUncertain = {
        status: 'uncertain',
        title: candidate.title,
        author: candidate.author,
        isbn: candidate.isbn,
        coverUrl: candidate.coverUrl,
        source: candidate.source,
      };
    }
  }

  const result = bestUncertain || {
    status: 'not_found',
    title: trimmed,
    author: null,
    isbn: null,
    coverUrl: null,
    source: null,
  };
  cacheSet(key, result);
  return result;
}
