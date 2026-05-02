// AES-256-GCM 对称加密工具，用于保护敏感字段（当前为供应商 API Key）
// 密钥来自 SUPPLIER_ENCRYPTION_KEY（64 位十六进制 = 32 字节）
//
// 密文格式：enc:v1:<iv_base64>:<tag_base64>:<ciphertext_base64>
// 没有前缀视为明文（历史数据），decrypt 会原样返回。

import crypto from 'crypto';

const PREFIX = 'enc:v1:';
const ALGO = 'aes-256-gcm';
const IV_BYTES = 12; // GCM 推荐

let cachedKey = null;

function getKey() {
  if (cachedKey) return cachedKey;
  const raw = process.env.SUPPLIER_ENCRYPTION_KEY;
  if (!raw) return null;
  const buf = Buffer.from(raw, 'hex');
  if (buf.length !== 32) {
    console.error('❌ SUPPLIER_ENCRYPTION_KEY 必须是 64 位十六进制字符串（32 字节）');
    return null;
  }
  cachedKey = buf;
  return cachedKey;
}

export function isEncryptionConfigured() {
  return getKey() !== null;
}

export function isEncrypted(value) {
  return typeof value === 'string' && value.startsWith(PREFIX);
}

/**
 * 加密明文，返回带前缀的密文串。未配置密钥时抛错。
 */
export function encrypt(plaintext) {
  const key = getKey();
  if (!key) {
    const err = new Error('未配置 SUPPLIER_ENCRYPTION_KEY，无法加密敏感字段');
    err.statusCode = 500;
    throw err;
  }
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGO, key, iv);
  const ct = Buffer.concat([cipher.update(String(plaintext), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${PREFIX}${iv.toString('base64')}:${tag.toString('base64')}:${ct.toString('base64')}`;
}

/**
 * 解密密文。若输入不是带前缀的密文，原样返回（兼容历史明文）。
 * 若密钥缺失或密文损坏，抛出错误。
 */
export function decrypt(value) {
  if (!isEncrypted(value)) return value;
  const key = getKey();
  if (!key) {
    const err = new Error('未配置 SUPPLIER_ENCRYPTION_KEY，无法解密敏感字段');
    err.statusCode = 500;
    throw err;
  }
  const payload = value.slice(PREFIX.length);
  const [ivB64, tagB64, ctB64] = payload.split(':');
  if (!ivB64 || !tagB64 || !ctB64) {
    throw new Error('密文格式损坏');
  }
  const iv = Buffer.from(ivB64, 'base64');
  const tag = Buffer.from(tagB64, 'base64');
  const ct = Buffer.from(ctB64, 'base64');
  const decipher = crypto.createDecipheriv(ALGO, key, iv);
  decipher.setAuthTag(tag);
  const pt = Buffer.concat([decipher.update(ct), decipher.final()]);
  return pt.toString('utf8');
}
