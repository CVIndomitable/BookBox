# BookBox V2 - 书籍整理与装箱管理系统

iPhone 拍照 → 服务器端多模态大模型（MiMo）识别书名 → 录入并关联到书架/箱子。支持语音指令管理书库。

## 技术栈

- **后端**：Node.js + Express 5 + Prisma 6 + MySQL 8，PM2 部署在 CentOS
- **iOS**：Swift / SwiftUI，最低 iOS 17，XcodeGen 生成项目
- **识别**：MiMo 多模态大模型（Anthropic 兼容协议），Apple Vision OCR 作为回退
- **语音**：Speech 框架本地转文字 + 服务器端 LLM 解析指令

## 层级与位置模型

- **层级**：书库（Library） → 房间（Room） → 书架（Shelf）/ 箱子（Box） → 书（Book）
- 新建书库时自动创建一个 `is_default=true` 的默认房间；默认房间不可删；删其它房间时其下的书架/箱子转移到同书库的默认房间
- 书架/箱子跨房间或跨书库搬动时，`libraryId` 以目标房间为准自动更新
- **一本书只能在一个位置**：通过 `books.location_type`（shelf/box/none）+ `books.location_id` 关联，不使用数据库外键，不用中间表
- 分类（Category）全局共享，书可跨书库移动
- 所有 move/add/remove 操作必须更新容器的 `book_count` 并写入 `book_logs`

## 职责边界

- **LLM 调用只在服务器端**（`server/src/routes/llm.js`）：iOS 端通过 `NetworkService` 调 `/api/llm/*`，不直接调第三方 AI
- **API Key 存服务器数据库**，iOS 端不保存
- **服务器地址硬编码**在 `BookBox/Models/AppConfig.swift`（部署信息见 `docs/部署信息.md`，不入 Git）

## 三色标识（UI 约定）

| 色 | AI 模式（置信度） | OCR 回退（联网校验） |
|----|------------------|---------------------|
| 🟢 | high             | matched             |
| 🟡 | medium           | uncertain           |
| 🔴 | low              | not_found           |

## 编码规范

- 代码注释、commit message 用中文；变量/函数名用英文 camelCase
- **Node.js**：ES Modules，统一 try-catch + 全局错误中间件，dotenv 管环境变量
- **Swift**：async/await 做网络，Codable 模型属性名直接对齐服务器 JSON（camelCase，无需自定义 CodingKeys）

## 其它参考

- DB schema 权威来源：`server/prisma/schema.prisma`
- API 路由权威来源：`server/src/routes/*.js`
- 待办：box_books 旧表数据迁移（见 `docs/UPGRADE-V2.md` 第五节）、后端联网校验（豆瓣/Google Books/Open Library）、离线模式
