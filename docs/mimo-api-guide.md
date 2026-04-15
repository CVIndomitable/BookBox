# 小米 MiMo API 平台 — Anthropic API 兼容接入指南

> 本文档整理自 [platform.xiaomimimo.com](https://platform.xiaomimimo.com/#/docs/api/chat/anthropic-api) 及社区实践，供 Claude Code 配置参考。

---

## 1. 平台概览

小米 MiMo API 开放平台同时兼容 **OpenAI API** 和 **Anthropic API** 两种主流协议格式，可直接接入 Claude Code、OpenClaw、Cline、KiloCode 等 Agent 框架。

- **官网**: <https://platform.xiaomimimo.com>
- **API Key 管理**: <https://platform.xiaomimimo.com/#/console/api-keys>
- **模型体验 (MiMo Studio)**: <https://aistudio.xiaomimimo.com>

---

## 2. 可用模型

| 模型 ID | 总参数 | 激活参数 | 上下文长度 | 特点 |
|---|---|---|---|---|
| `mimo-v2-flash` | 309B (MoE) | 15B | 262K | 高速、高性价比，开源 (MIT) |
| `mimo-v2-pro` | 1T+ (MoE) | 42B | 1M | 旗舰，Agent 场景深度优化 |
| `mimo-v2-omni` | — | — | 256K | 全模态（图/视频/音频/文本） |

---

## 3. Anthropic API 兼容接入

### 3.1 Base URL

```
https://api.xiaomimimo.com/anthropic
```

### 3.2 认证方式

使用 API Key 进行 Bearer Token 认证，与 Anthropic 原生方式一致：

- Header: `x-api-key: <YOUR_MIMO_API_KEY>`
- 或通过 SDK 的 `api_key` 参数传入

### 3.3 Python SDK 示例

```python
from anthropic import Anthropic

client = Anthropic(
    api_key="sk-你的MiMo_API_Key",
    base_url="https://api.xiaomimimo.com/anthropic"
)

message = client.messages.create(
    model="mimo-v2-pro",        # 或 mimo-v2-flash / mimo-v2-omni
    max_tokens=1024,
    system="You are a helpful assistant.",
    messages=[
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "你好，请介绍一下你自己。"}
            ]
        }
    ],
    temperature=0.8,
    top_p=0.95,
    thinking={"type": "disabled"}   # 建议在 Claude Code 场景下关闭 thinking
)

print(message.content)
```

### 3.4 OpenAI 兼容（备选）

```
Base URL: https://api.xiaomimimo.com/v1
```

---

## 4. Claude Code 接入配置

### 4.1 方式一：编辑 settings.json（推荐）

编辑 `~/.claude/settings.json`：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.xiaomimimo.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "sk-你的MiMo_API_Key",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "mimo-v2-pro",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "mimo-v2-pro",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "mimo-v2-flash"
  }
}
```

> **说明**：Claude Code 内部有 Opus / Sonnet / Haiku 三个模型槽位，需要分别映射到 MiMo 的模型 ID。推荐将 Opus 和 Sonnet 映射到 `mimo-v2-pro`，Haiku 映射到 `mimo-v2-flash` 以节省成本。如果只用一个模型，三个槽位填同一个模型名即可。

### 4.2 方式二：跳过登录 + 环境变量

如遇登录问题（如 `Failed to connect to api.anthropic.com`），在 `~/.claude.json` 中添加：

```json
{
  "hasCompletedOnboarding": true
}
```

也可以通过 Shell 包装脚本注入环境变量：

```bash
#!/usr/bin/env bash
export ANTHROPIC_AUTH_TOKEN="sk-你的MiMo_API_Key"
export ANTHROPIC_BASE_URL="https://api.xiaomimimo.com/anthropic"
export ANTHROPIC_DEFAULT_OPUS_MODEL="mimo-v2-pro"
export ANTHROPIC_DEFAULT_SONNET_MODEL="mimo-v2-pro"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="mimo-v2-flash"
exec claude "$@"
```

### 4.3 方式三：CC Switch 等工具

使用 [CC Switch](https://github.com/nicekid1/claude-code-switch) / CCR 等切换工具可免手动编辑配置文件，创建配置后一键 Switch。

### 4.4 验证配置

启动 Claude Code 后：
- 输入 `/model` 查看当前使用的模型名
- 输入 `/status` 查看 API 端点等信息

---

## 5. 注意事项

### 5.1 Thinking 模式

- MiMo-V2-Flash 在 Claude Code 中使用 Thinking 模式**可能报错**，建议关闭：`thinking={"type": "disabled"}`
- MiMo-V2-Pro 官方声称支持 Thinking，但兼容性需实测验证

### 5.2 Tool Calling

- MiMo-V2-Pro 支持 Tool Calling（Function Calling）
- 如使用 OpenAI 兼容协议，需配置 `--tool-call-parser mimo`

### 5.3 模型名称

- 模型名称必须小写，如 `mimo-v2-pro`、`mimo-v2-flash`、`mimo-v2-omni`
- 不可随意修改拼写

### 5.4 API Key 安全

- API Key 仅在创建时可见，请立即保存
- 建议通过环境变量而非硬编码方式使用 Key

---

## 6. 定价参考

### 按量计费

| 模型 | 输入 (¥/百万 token) | 输出 (¥/百万 token) | 缓存命中输入 |
|---|---|---|---|
| mimo-v2-flash | 0.7 | 2.1 | 0.07 |
| mimo-v2-pro (≤256K ctx) | ~1 ($1/M) | ~3 ($3/M) | — |
| mimo-v2-pro (≤1M ctx) | ~2 ($2/M) | ~6 ($6/M) | — |
| mimo-v2-omni | ~0.4 ($0.4/M) | ~2 ($2/M) | — |

### Token Plan（月度订阅）

| 套餐 | 月费 | Credits | 适用场景 |
|---|---|---|---|
| Lite | ¥39 | 60M | 轻度探索 |
| Standard | ¥99 | 200M | 日常办公开发 |
| Pro | ¥329 | 700M | 专业开发 |
| Max | ¥659 | 1600M | 高强度使用 |

> Token Plan 的 API Key 与按量计费的 API Key 相互独立，需生成新 Key。
> 首次购买享 88 折优惠。

---

## 7. OpenClaw 配置参考

如果使用 OpenClaw 框架接入 MiMo：

```json5
{
  env: {
    XIAOMI_API_KEY: "your-key"
  },
  agents: {
    defaults: {
      model: {
        primary: "xiaomi/mimo-v2-flash"
      }
    }
  },
  models: {
    mode: "merge",
    providers: {
      xiaomi: {
        baseUrl: "https://api.xiaomimimo.com/anthropic",
        api: "anthropic-messages",
        apiKey: "XIAOMI_API_KEY",
        models: [
          {
            id: "mimo-v2-flash",
            name: "Xiaomi MiMo V2 Flash",
            reasoning: false,
            input: ["text"],
            cost: { input: 0.7, output: 2.1, cacheRead: 0.07, cacheWrite: 0 },
            contextWindow: 262144,
            maxTokens: 8192
          }
        ]
      }
    }
  }
}
```

---

## 8. 常见问题

**Q: 提示 `Failed to connect to api.anthropic.com` 怎么办？**
A: 在 `~/.claude.json` 中添加 `"hasCompletedOnboarding": true`，确保 `ANTHROPIC_BASE_URL` 配置正确。

**Q: 可以同时使用 MiMo 和 Anthropic 官方 API 吗？**
A: 可以。通过 CC Switch 等工具管理多配置，按需切换。

**Q: 模型推荐？**
A: 日常编码用 `mimo-v2-flash`（快且便宜）；复杂任务用 `mimo-v2-pro`（能力更强，接近 Opus 水平）；多模态场景用 `mimo-v2-omni`。

---

*文档更新日期：2026-04-12*
*信息来源：小米 MiMo 官方文档、社区实践整理，具体以官方最新文档为准。*
