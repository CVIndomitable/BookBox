# BookBox — 书籍整理与装箱管理系统

拍照识别书名，语音管理书库。把实体书整理到书架或箱子里，再也不怕找不到书。

## 功能

- **拍照识别** — 对着一排书拍张照，AI 多模态大模型自动识别所有书名，识别失败时自动回退到本地 OCR
- **多书库** — 支持家、办公室等多个独立书库，顶部一键切换，分类全局共享
- **书架 + 箱子** — 书架放常看的书（活跃区），箱子装暂存的书（归档区），一本书只在一个位置
- **两种工作模式** — 预分类模式快速浏览分类，装箱模式将书籍录入数据库
- **AI 供应商池** — 按优先级多供应商故障转移，视觉 / 纯文本任务分别路由，单点故障自动降级
- **语音交互** — 全局悬浮麦克风 + Siri 快捷指令（查找书、移动书、新建书架、查询书库)
- **三色标识** — 绿/黄/红直观标记识别置信度，一眼分辨哪些书需要人工确认
- **操作日志** — 每次移动、添加、编辑都有记录，可追溯
- **连接测试** — 设置页一键检测服务器 / 数据库 / AI 服务连通性

## 技术栈

| 层 | 技术 |
|---|---|
| iOS 客户端 | Swift · SwiftUI · iOS 17+ |
| 后端 | Node.js · Express 5 · Prisma 6 |
| 数据库 | MySQL 8 |
| AI 识别 | MiMo 多模态 + 学鼎纯文本（供应商池，服务器端调用） |
| OCR 回退 | Apple Vision 框架 |
| 语音 | Apple Speech 框架 · App Intents（Siri 快捷指令） |
| 项目构建 | XcodeGen |
| 进程管理 | PM2 |

## 快速开始

### 1. 后端

```bash
cd server
cp .env.example .env   # 编辑 .env，填入数据库连接和 API Token
npm install
npx prisma db push     # 初始化数据库表
npm run dev            # 启动开发服务器
```

`.env` 必填项：

```env
DATABASE_URL=mysql://用户名:密码@localhost:3306/bookbox
API_TOKEN=你的认证密钥
```

数据库需提前创建：

```sql
CREATE DATABASE bookbox CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### 2. iOS 客户端

```bash
# 安装 XcodeGen（如果没有）
brew install xcodegen

# 生成 Xcode 项目
xcodegen generate

# 用 Xcode 打开
open BookBox.xcodeproj
```

服务器地址在 `BookBox/Models/AppConfig.swift` 中配置。

### 3. 验证

```bash
curl http://localhost:3000/api/health
```

## 项目结构

```
├── BookBox/                # iOS 客户端
│   ├── App/                #   应用入口
│   ├── Intents/            #   Siri 快捷指令（查找 / 移动 / 建架 / 查询）
│   ├── Models/             #   数据模型
│   ├── Views/              #   SwiftUI 视图
│   │   ├── PreClassify/    #     预分类模式
│   │   ├── Boxing/         #     装箱模式
│   │   ├── Library/        #     书库 / 书架 / 箱子 / 分类 / 日志
│   │   ├── Settings/       #     设置 + 连接测试
│   │   └── Components/     #     公共组件
│   └── Services/           #   网络、OCR、语音等服务
├── server/                 # Node.js 后端
│   ├── prisma/             #   数据库 schema
│   └── src/
│       ├── routes/         #   API 路由（含 suppliers 供应商池)
│       └── services/search #   书籍联网校验
├── project.yml             # XcodeGen 配置
└── CLAUDE.md               # 项目详细文档
```

## API 概览

所有接口（除健康检查）需 `Authorization: Bearer <token>` 认证。

| 模块 | 端点 | 说明 |
|------|------|------|
| 健康检查 | `GET /api/health` | 无需认证 |
| 书库 | `/api/libraries` · `/api/library/overview` | 多书库 CRUD + 全局统计 |
| 书架 | `/api/shelves` | CRUD + 书籍关联 |
| 箱子 | `/api/boxes` | CRUD + 书籍关联 |
| 书籍 | `/api/books` | CRUD + 移动 + 批量添加 + 日志 |
| 分类 | `/api/categories` | 全局分类管理 |
| AI 识别 | `POST /api/llm/recognize` | 拍照识别书名 |
| 语音指令 | `POST /api/llm/voice-command` | 自然语言解析 |
| AI 供应商 | `/api/suppliers` | 供应商池配置与优先级 |
| 操作日志 | `GET /api/logs` | 历史记录 |
| 扫描记录 | `GET /api/scans` | 拍照历史 |

## 生产部署

```bash
# 使用 PM2 管理进程
pm2 start src/index.js --name bookbox
pm2 startup && pm2 save
```

建议使用 Nginx 反向代理并配置 HTTPS。

## 许可证

私有项目，仅供个人使用。
