# BookBox V2 - 书籍整理与装箱管理系统

## 项目概述

一个用于整理和管理实体书籍的系统。用户通过 iPhone 拍照，由多模态大模型（MiMo）识别书名，支持两种工作模式：预分类模式（快速浏览分类）和装箱模式（将书籍录入数据库并关联到物理箱子或书架）。系统支持语音交互，用户可通过全局悬浮麦克风按钮语音管理书库。

### V2 核心变更
- **多书库（Library）**：支持多个独立书库，顶部切换器选择当前书库，`@AppStorage` 记忆上次查看的书库。分类全局共享，书可跨书库移动。
- **书架（Shelf）**：新增书架概念，与箱子并列作为书籍存放位置。书架为活跃区域，箱子为归档区域。
- **统一位置模型**：一本书只能在一个位置（书架/箱子/未归位），通过 `location_type` + `location_id` 字段关联，废弃旧的 `box_books` 中间表。
- **多模态识别**：用 MiMo 多模态大模型替代旧的 OCR + 规则提取流程，支持任意姿态的书籍识别。LLM 调用在服务器端执行，iOS 客户端不直接调用 AI API。
- **语音交互**：全局悬浮麦克风按钮，支持自然语言操作书库（移动书、查书、新建书架等）。
- **操作日志**：`book_logs` 表记录所有书籍操作历史。
- **服务器地址硬编码**：见 `AppConfig.swift` 和 `docs/部署信息.md`（不提交到 Git）。

## 技术栈

### 后端
- **运行时**：Node.js (LTS)
- **框架**：Express.js 5.x
- **数据库**：MySQL 8.x
- **ORM**：Prisma 6.x
- **部署**：CentOS 服务器（上海，国内网络环境）
- **进程管理**：PM2
- **项目构建**：XcodeGen（通过 project.yml 生成 Xcode 项目）

### iOS 客户端
- **语言**：Swift
- **最低支持**：iOS 17+
- **目标设备**：iPhone 15 及以上
- **AI 识别**：MiMo 多模态大模型（Anthropic 兼容协议）
- **OCR（回退）**：Apple Vision 框架 (VNRecognizeTextRequest)
- **语音**：Speech 框架 (SFSpeechRecognizer)
- **UI 框架**：SwiftUI

## 项目结构

```
bookbox/
├── CLAUDE.md                   # 项目说明文档
├── CONFIGURATION.md            # 配置指南
├── project.yml                 # XcodeGen 项目配置
├── server/                     # Node.js 后端
│   ├── prisma/
│   │   └── schema.prisma       # 数据库模型定义
│   ├── src/
│   │   ├── index.js            # 入口文件
│   │   ├── routes/
│   │   │   ├── libraries.js    # 书库 CRUD 路由
│   │   │   ├── boxes.js        # 箱子相关路由
│   │   │   ├── books.js        # 书籍相关路由（含 move、logs）
│   │   │   ├── shelves.js      # 书架相关路由
│   │   │   ├── categories.js   # 分类相关路由
│   │   │   ├── scans.js        # 扫描记录路由
│   │   │   ├── settings.js     # 用户设置路由
│   │   │   ├── logs.js         # 操作日志路由
│   │   │   ├── library.js      # 书库总览路由（支持 libraryId 筛选）
│   │   │   └── llm.js          # AI 识别路由（MiMo 调用）
│   │   ├── middleware/
│   │   │   └── auth.js         # 认证中间件（Bearer Token）
│   │   └── utils/
│   │       └── prisma.js       # Prisma 客户端单例
│   ├── package.json
│   └── .env                    # 环境变量
│
└── BookBox/                    # iOS Xcode 项目
    ├── App/
    │   └── BookBoxApp.swift         # 入口 + 全局语音悬浮按钮
    ├── Models/
    │   ├── AppConfig.swift          # 硬编码配置（服务器地址）
    │   ├── Book.swift               # 书籍模型（含位置字段、libraryId）
    │   ├── BookLog.swift            # 操作日志模型
    │   ├── Box.swift                # 箱子模型（含 libraryId）
    │   ├── Category.swift           # 分类模型（全局共享）
    │   ├── Library.swift            # 书库模型
    │   ├── LibraryOverview.swift    # 书库总览模型
    │   ├── ScanRecord.swift         # 扫描记录模型
    │   ├── Shelf.swift              # 书架模型（含 libraryId）
    │   └── UserSettings.swift       # 用户设置模型
    ├── Views/
    │   ├── HomeView.swift           # 主界面
    │   ├── PreClassify/
    │   │   ├── PreClassifyView.swift     # 预分类模式（服务器 AI + OCR 回退）
    │   │   └── ClassifyResultView.swift  # 分类结果展示
    │   ├── Boxing/
    │   │   ├── BoxingView.swift          # 装箱模式（服务器 AI + OCR 回退）
    │   │   ├── BoxCreateView.swift       # 新建箱子
    │   │   ├── ScanResultView.swift      # 扫描结果（三色标识）
    │   │   └── BookDetailView.swift      # 书籍详情/编辑
    │   ├── Library/
    │   │   ├── LibraryView.swift         # 书库总览（顶部书库切换+书架+箱子+全部书籍）
    │   │   ├── LibraryCreateView.swift   # 新建书库
    │   │   ├── BoxListView.swift         # 箱子列表
    │   │   ├── BoxDetailView.swift       # 单个箱子内容
    │   │   ├── ShelfDetailView.swift     # 书架详情
    │   │   └── ShelfCreateView.swift     # 新建书架
    │   ├── Settings/
    │   │   └── SettingsView.swift        # 设置页（MiMo API Key）
    │   └── Components/
    │       ├── CameraView.swift          # 相机组件
    │       ├── BookRow.swift             # 书籍列表行组件
    │       └── VoiceAssistantButton.swift # 全局语音悬浮按钮
    ├── Services/
    │   ├── AIModels.swift           # AI 识别与语音指令的数据模型（RecognizedBook、VoiceCommandResult、LibraryContext 等）
    │   ├── SpeechService.swift      # 语音识别服务
    │   ├── NetworkService.swift     # 网络请求层（硬编码地址）
    │   ├── OCRService.swift         # Vision OCR（回退方案）
    │   ├── BookExtractor.swift      # OCR 书名提取（回退方案）
    │   ├── LLMService.swift         # 大模型 API 调用
    │   ├── LocalMLService.swift     # 本地 Core ML 模型
    │   └── Error+Chinese.swift      # Error 扩展
    └── Resources/
        └── Assets.xcassets          # 资源文件
```

## 数据库设计

### libraries 表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AUTO_INCREMENT | 主键 |
| name | VARCHAR(200) | 书库名称 |
| location | VARCHAR(200) | 位置描述，可为空 |
| description | TEXT | 备注，可为空 |
| created_at | DATETIME | 创建时间 |
| updated_at | DATETIME | 更新时间 |

### books 表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AUTO_INCREMENT | 主键 |
| title | VARCHAR(500) | 书名 |
| author | VARCHAR(500) | 作者，可为空 |
| isbn | VARCHAR(20) | ISBN，可为空 |
| publisher | VARCHAR(200) | 出版社，可为空 |
| cover_url | TEXT | 封面图 URL，可为空 |
| category_id | INT | 外键关联 categories |
| verify_status | VARCHAR(20) | 校验状态：matched/uncertain/not_found/manual |
| verify_source | VARCHAR(50) | 校验来源：mimo/douban/google/manual |
| raw_ocr_text | TEXT | 原始识别文本 |
| location_type | VARCHAR(10) DEFAULT 'none' | 位置类型：shelf/box/none |
| location_id | INT | 位置 ID（指向 shelves 或 boxes 表） |
| library_id | INT | 所属书库 ID，可为空 |
| created_at | DATETIME | 创建时间 |
| updated_at | DATETIME | 更新时间 |

### shelves 表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AUTO_INCREMENT | 主键 |
| name | VARCHAR(200) | 书架名称 |
| location | VARCHAR(200) | 位置描述，可为空 |
| description | TEXT | 备注，可为空 |
| book_count | INT DEFAULT 0 | 书籍数量（冗余字段） |
| library_id | INT | 所属书库 ID，可为空 |
| created_at | DATETIME | 创建时间 |
| updated_at | DATETIME | 更新时间 |

### boxes 表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AUTO_INCREMENT | 主键 |
| box_uid | VARCHAR(20) UNIQUE | 唯一编号，格式 YYYYMMDD-NNN |
| name | VARCHAR(200) | 箱子名称 |
| description | TEXT | 备注，可为空 |
| book_count | INT DEFAULT 0 | 书籍数量（冗余字段） |
| library_id | INT | 所属书库 ID，可为空 |
| created_at | DATETIME | 创建时间 |
| updated_at | DATETIME | 更新时间 |

### book_logs 表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AUTO_INCREMENT | 主键 |
| book_id | INT | 关联书籍 |
| action | VARCHAR(20) | 操作类型：move/add/remove/edit/verify |
| from_type | VARCHAR(10) | 来源位置类型，可为空 |
| from_id | INT | 来源 ID，可为空 |
| to_type | VARCHAR(10) | 目标位置类型，可为空 |
| to_id | INT | 目标 ID，可为空 |
| method | VARCHAR(20) DEFAULT 'manual' | 操作方式：voice/manual/scan |
| raw_input | TEXT | 原始输入（语音文字），可为空 |
| ai_response | TEXT | AI 解析结果，可为空 |
| note | TEXT | 备注，可为空 |
| created_at | DATETIME | 创建时间 |

### categories 表（不变）
### scan_records 表（不变）
### user_settings 表（不变）

## API 设计

### 健康检查（无需认证）
- `GET    /api/health`

### 书库管理
- `GET    /api/libraries`          — 获取所有书库列表（附带书籍数量）
- `POST   /api/libraries`          — 新建书库 `{ name, location?, description? }`
- `GET    /api/libraries/:id`      — 获取书库详情（含总览统计：书籍数/书架/箱子）
- `PUT    /api/libraries/:id`      — 更新书库信息
- `DELETE /api/libraries/:id`      — 删除书库（关联数据 libraryId 置空）

### 书架管理
- `GET    /api/shelves`            — 获取所有书架列表
- `POST   /api/shelves`            — 新建书架 `{ name, location?, description? }`
- `GET    /api/shelves/:id`        — 获取书架详情及其中的书（分页）
- `PUT    /api/shelves/:id`        — 更新书架信息
- `DELETE /api/shelves/:id`        — 删除书架（书的 location 重置为 none）
- `POST   /api/shelves/:id/books`  — 批量将书放入书架 `{ bookIds: [1,2,3] }`
- `DELETE /api/shelves/:id/books/:bookId` — 从书架移走一本书

### 箱子管理
- `GET    /api/boxes`            — 获取所有箱子列表
- `POST   /api/boxes`            — 新建箱子
- `GET    /api/boxes/:id`        — 获取箱子详情及其中的书（分页）
- `PUT    /api/boxes/:id`        — 更新箱子信息
- `DELETE /api/boxes/:id`        — 删除箱子（书的 location 重置为 none）
- `POST   /api/boxes/:id/books`  — 向箱子中添加书籍
- `DELETE /api/boxes/:id/books/:bookId` — 从箱子中移除一本书

### 书籍管理
- `GET    /api/books`            — 获取书籍列表（支持 locationType/locationId/shelfId/boxId 筛选）
- `POST   /api/books`            — 新增书籍（支持 locationType/locationId）
- `GET    /api/books/:id`        — 获取书籍详情（含位置信息）
- `PUT    /api/books/:id`        — 更新书籍（支持移动位置）
- `DELETE /api/books/:id`        — 删除书籍
- `POST   /api/books/batch`      — 批量新增（支持 locationType/locationId，兼容旧 boxId）
- `POST   /api/books/:id/move`   — 移动书籍到指定位置
- `GET    /api/books/:id/logs`   — 获取单本书的操作历史

### 操作日志
- `GET    /api/logs`             — 获取全部操作日志（支持分页、按 action/method 筛选）

### 书库总览
- `GET    /api/library/overview` — 书库全貌（支持 `?libraryId=` 按书库筛选）

### AI 识别（服务器端 LLM）
- `POST   /api/llm/recognize`    — 多模态识别书籍 `{ image: "base64..." }` → `{ books: [{title, author, confidence}] }`
- `POST   /api/llm/voice-command` — 语音指令解析 `{ text, systemPrompt }` → `{ action, bookTitle, target, reply }`

### 分类、扫描记录、设置、书籍校验（同 V1）

## 三色标识系统

MiMo 模式：置信度 → 三色
- 🟢 **绿色 (high)**：AI 高置信度识别
- 🟡 **黄色 (medium)**：AI 中置信度
- 🔴 **红色 (low)**：AI 低置信度

OCR 回退模式：联网校验 → 三色
- 🟢 **绿色 (matched)**：联网校验成功
- 🟡 **黄色 (uncertain)**：部分匹配
- 🔴 **红色 (not_found)**：未找到匹配

## 识别流程

1. **AI 模式**（服务器已配置 API Key）：拍照 → iOS 压缩图片 → base64 发到服务器 `/llm/recognize` → 服务器调用 MiMo → 返回书名列表（含置信度）
2. **OCR 回退**（AI 调用失败时自动回退）：拍照 → 本地 Vision OCR → 规则提取 → 联网校验

## 语音交互流程

1. 用户点击悬浮麦克风按钮开始录音
2. SpeechService 实时语音转文字（本地）
3. 停止录音后，文字 + 书库上下文发到服务器 `/llm/voice-command`
4. 服务器调用 MiMo flash 模型，返回 JSON 指令（action/bookTitle/target/reply）
5. iOS 端解析指令，调用后端 API 执行
6. 显示执行结果

## 开发顺序

### Phase 1-4：V1 基础 ✅ 已完成

### Phase V2-A：数据模型和后端 ✅ 已完成
1. ✅ 修改 Prisma schema（新增 Shelf、BookLog，修改 Book，移除 BoxBook）
2. ✅ 新建 shelves.js 路由
3. ✅ 修改 books.js（位置字段 + move + logs）
4. ✅ 修改 boxes.js（从 box_books 改为 location 字段）
5. ✅ 新建 logs.js 和 library.js 路由

### Phase V2-B：iOS 数据层 ✅ 已完成
1. ✅ 新增 Shelf/BookLog/LibraryOverview/AppConfig 模型
2. ✅ 更新 Book 模型（位置字段）
3. ✅ NetworkService 新增所有 V2 API
4. ✅ 硬编码服务器地址

### Phase V2-C：多模态识别 ✅ 已完成
1. ✅ 新建 AIModels.swift（数据模型）
2. ✅ 修改拍照流程（服务器 AI + OCR 回退）
3. ✅ 设置页简化为 AI 配置
4. ✅ LLM 调用移至服务器端（llm.js），iOS 端不再直接调 AI API

### Phase V2-D：书库界面重构 ✅ 已完成
1. ✅ LibraryView 分书架/箱子/全部书籍三视图
2. ✅ 新建 ShelfDetailView/ShelfCreateView

### Phase V2-E：语音交互 ✅ 已完成
1. ✅ SpeechService.swift
2. ✅ VoiceAssistantButton.swift
3. ✅ BookBoxApp 添加全局悬浮按钮

### 待做
- 数据迁移（box_books → books.location_*，见 docs/UPGRADE-V2.md 第五节）
- 后端搜索服务（豆瓣/Google Books/Open Library）
- UI 动画和打磨
- 离线模式

## 编码规范

### 通用
- 代码注释使用中文
- Git commit message 使用中文
- 变量名和函数名使用英文，采用 camelCase

### Node.js 后端
- 使用 ES Modules (import/export)
- 错误处理统一用 try-catch + 全局错误中间件
- 环境变量通过 dotenv + .env 文件管理
- 书籍位置通过 `books.location_type` + `books.location_id` 关联，不使用数据库外键
- 所有移动/添加/删除操作需更新容器 `book_count` 并写入 `book_logs`

### Swift iOS
- 遵循 Swift 命名规范
- UI 使用 SwiftUI
- 网络请求使用 async/await
- 数据模型遵循 Codable 协议（属性名使用 camelCase，与服务器 JSON 键一致，无需自定义 CodingKeys）
- AI API Key 存储在服务器数据库，iOS 端不保存密钥
- 服务器地址通过 AppConfig 硬编码
- AI 识别通过 NetworkService 调用服务器端 `/api/llm/*` 接口，不直接调用第三方 AI API
