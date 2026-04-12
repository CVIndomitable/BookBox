# BookBox - 书籍整理与装箱管理系统

## 项目概述

一个用于整理和管理实体书籍的系统。用户通过 iPhone 拍照识别书脊/封面上的书名，支持两种工作模式：预分类模式（快速浏览分类）和装箱模式（将书籍录入数据库并关联到物理箱子）。装箱模式下会联网校验识别结果的准确性。

## 技术栈

### 后端
- **运行时**：Node.js (LTS)
- **框架**：Express.js
- **数据库**：MySQL 8.x
- **ORM**：Prisma
- **部署**：CentOS 服务器（上海，国内网络环境）
- **进程管理**：PM2

### iOS 客户端
- **语言**：Swift
- **最低支持**：iOS 17+
- **目标设备**：iPhone 15 及以上
- **OCR**：Apple Vision 框架 (VNRecognizeTextRequest)
- **本地AI**：Core ML（可选，用于书名提取和分类）
- **UI 框架**：SwiftUI

## 项目结构

```
bookbox/
├── server/                     # Node.js 后端
│   ├── prisma/
│   │   └── schema.prisma       # 数据库模型定义
│   ├── src/
│   │   ├── index.js            # 入口文件
│   │   ├── routes/
│   │   │   ├── boxes.js        # 箱子相关路由
│   │   │   ├── books.js        # 书籍相关路由
│   │   │   ├── categories.js   # 分类相关路由
│   │   │   ├── scan.js         # 扫描与识别路由
│   │   │   └── settings.js     # 用户设置路由
│   │   ├── services/
│   │   │   ├── search/
│   │   │   │   ├── douban.js       # 豆瓣搜索（爬取）
│   │   │   │   ├── googleBooks.js  # Google Books API
│   │   │   │   ├── openLibrary.js  # Open Library API
│   │   │   │   └── searchManager.js # 搜索策略调度器
│   │   │   ├── llm.js          # 大模型 API 转发
│   │   │   └── verify.js       # 书籍校验服务
│   │   ├── middleware/
│   │   │   └── auth.js         # 认证中间件（简单 token）
│   │   └── utils/
│   │       ├── cache.js        # 搜索结果缓存
│   │       └── rateLimit.js    # 请求频率控制
│   ├── package.json
│   └── .env                    # 环境变量
│
└── BookBox/                    # iOS Xcode 项目
    ├── App/
    │   └── BookBoxApp.swift
    ├── Models/
    │   ├── Book.swift
    │   ├── Box.swift
    │   └── Category.swift
    ├── Views/
    │   ├── HomeView.swift           # 主界面，选择模式
    │   ├── PreClassify/
    │   │   ├── PreClassifyView.swift     # 预分类模式主界面
    │   │   └── ClassifyResultView.swift  # 分类结果展示
    │   ├── Boxing/
    │   │   ├── BoxingView.swift          # 装箱模式主界面
    │   │   ├── BoxCreateView.swift       # 新建箱子
    │   │   ├── ScanResultView.swift      # 扫描结果（三色标识）
    │   │   └── BookDetailView.swift      # 书籍详情/编辑
    │   ├── Library/
    │   │   ├── LibraryView.swift         # 我的书库总览
    │   │   ├── BoxListView.swift         # 箱子列表
    │   │   └── BoxDetailView.swift       # 单个箱子内容
    │   ├── Settings/
    │   │   └── SettingsView.swift        # 设置页
    │   └── Components/
    │       ├── CameraView.swift          # 相机组件
    │       └── BookRow.swift             # 书籍列表行组件
    ├── Services/
    │   ├── OCRService.swift         # Vision OCR 封装
    │   ├── BookExtractor.swift      # 从 OCR 文本提取书名（规则+可选模型）
    │   ├── NetworkService.swift     # 网络请求层
    │   ├── LLMService.swift         # 大模型 API 调用
    │   └── LocalMLService.swift     # 本地 Core ML 模型调用
    └── Resources/
        └── (可选的 Core ML 模型文件)
```

## 数据库设计

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
| verify_status | ENUM('matched','uncertain','not_found','manual') | 校验状态 |
| verify_source | VARCHAR(50) | 校验来源：douban/google/openlibrary/llm/manual |
| raw_ocr_text | TEXT | 原始 OCR 识别文本，保留用于回溯 |
| created_at | DATETIME | 创建时间 |
| updated_at | DATETIME | 更新时间 |

### boxes 表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AUTO_INCREMENT | 主键 |
| box_uid | VARCHAR(20) UNIQUE | 唯一编号，格式 YYYYMMDD-NNN |
| name | VARCHAR(200) | 箱子名称 |
| description | TEXT | 备注，可为空 |
| book_count | INT DEFAULT 0 | 书籍数量（冗余字段，方便查询） |
| created_at | DATETIME | 创建时间 |
| updated_at | DATETIME | 更新时间 |

### box_books 表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AUTO_INCREMENT | 主键 |
| box_id | INT | 外键关联 boxes |
| book_id | INT | 外键关联 books |
| added_at | DATETIME | 入箱时间 |

### categories 表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AUTO_INCREMENT | 主键 |
| name | VARCHAR(100) | 分类名 |
| parent_id | INT | 父分类 ID，支持多级分类，可为空 |

### scan_records 表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AUTO_INCREMENT | 主键 |
| mode | ENUM('preclassify','boxing') | 扫描模式 |
| box_id | INT | 关联箱子（装箱模式），可为空 |
| photo_path | TEXT | 原始照片存储路径 |
| ocr_result | JSON | OCR 完整识别结果 |
| extracted_titles | JSON | 提取出的书名列表 |
| created_at | DATETIME | 扫描时间 |

### user_settings 表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AUTO_INCREMENT | 主键 |
| region_mode | ENUM('mainland','overseas') DEFAULT 'mainland' | 地区模式 |
| llm_provider | VARCHAR(50) | 大模型服务商：openai/claude/other，可为空 |
| llm_api_key | VARCHAR(500) | 加密存储的 API Key，可为空 |
| llm_endpoint | VARCHAR(500) | 自定义 API 地址，可为空 |
| llm_model | VARCHAR(100) | 模型名称，可为空 |
| llm_supports_search | BOOLEAN DEFAULT FALSE | 该模型是否支持联网搜索 |

## API 设计

### 箱子管理
- `GET    /api/boxes`            — 获取所有箱子列表
- `POST   /api/boxes`            — 新建箱子（返回自动生成的 box_uid）
- `GET    /api/boxes/:id`        — 获取箱子详情及其中的书
- `PUT    /api/boxes/:id`        — 更新箱子信息
- `DELETE /api/boxes/:id`        — 删除箱子（书不删除，只解除关联）

### 书籍管理
- `GET    /api/books`            — 获取书籍列表（支持分页、搜索、按分类筛选）
- `POST   /api/books`            — 新增书籍
- `GET    /api/books/:id`        — 获取书籍详情
- `PUT    /api/books/:id`        — 更新书籍信息
- `DELETE /api/books/:id`        — 删除书籍
- `POST   /api/books/batch`      — 批量新增书籍（装箱模式一次拍照多本）

### 书籍校验
- `POST   /api/books/verify`     — 校验书名，返回匹配结果
  - 请求体：`{ "title": "识别出的书名", "region": "mainland" | "overseas" }`
  - 响应体：`{ "status": "matched|uncertain|not_found", "title": "", "author": "", "isbn": "", "cover_url": "", "source": "douban|google|openlibrary|llm" }`

### 分类
- `GET    /api/categories`       — 获取分类树
- `POST   /api/categories`       — 新增分类
- `PUT    /api/categories/:id`   — 更新分类
- `DELETE /api/categories/:id`   — 删除分类

### 扫描记录
- `POST   /api/scans`            — 保存一次扫描记录
- `GET    /api/scans`            — 获取扫描历史

### 设置
- `GET    /api/settings`         — 获取用户设置
- `PUT    /api/settings`         — 更新设置（地区模式、API 配置等）

### 大模型转发
- `POST   /api/llm/extract`     — 用大模型从 OCR 文本提取书名列表
- `POST   /api/llm/classify`    — 用大模型对书籍进行分类
- `POST   /api/llm/search`      — 用大模型联网搜索书籍信息（如果支持）

## 书籍搜索策略

### 大陆模式（mainland）
搜索优先级：
1. **豆瓣搜索**（爬取 `search.douban.com`）— 中文书最全
2. **Open Library API** (`openlibrary.org/search.json`) — 英文书补充
3. **大模型联网搜索**（如果用户配了且支持联网）— 兜底
4. 以上都未匹配 → 标红 `not_found`

### 非大陆模式（overseas）
搜索优先级：
1. **Google Books API** (`googleapis.com/books/v1/volumes`) — 数据最全
2. **豆瓣搜索** — 中文书补充
3. **Open Library API** — 补充
4. **大模型联网搜索** — 兜底
5. 以上都未匹配 → 标红 `not_found`

### 搜索实现注意事项
- 豆瓣爬取需要：随机 User-Agent、请求间隔 2-3 秒、失败重试
- 所有搜索结果缓存到 MySQL（书名 → 结果），避免重复请求
- 搜索用模糊匹配，OCR 识别的书名可能有错别字
- 瀑布式查询：上一个源匹配到就停止，不继续请求

## iOS 端核心逻辑

### OCR 流程
1. 使用 `VNRecognizeTextRequest`，设置 `recognitionLanguages = ["zh-Hans", "zh-Hant", "en"]`
2. 设置 `recognitionLevel = .accurate`（精确模式）
3. 拍照后自动识别，返回文本块列表及其坐标位置

### 书名提取（本地）
优先级：
1. **规则提取**：按行分割 OCR 文本，书脊上通常每行就是一个信息项（书名、作者、出版社），取最长/最显眼的行作为书名
2. **本地小模型**（可选）：如果用户设备支持，用 Core ML 跑一个文本提取模型
3. **外接大模型 API**（可选）：将完整 OCR 文本发给大模型，提取结构化信息

### 三色标识系统
- 🟢 **绿色 (matched)**：联网校验成功，书名和作者都匹配上
- 🟡 **黄色 (uncertain)**：部分匹配或大模型给出的低置信度结果
- 🔴 **红色 (not_found)**：未找到匹配，需要人工确认

用户可以点击任何一条结果手动编辑修正。

## 开发顺序

### Phase 1：后端基础
1. 初始化 Node.js 项目，配置 Prisma + MySQL
2. 创建数据库表结构
3. 实现箱子、书籍、分类的基础 CRUD API
4. 简单的 token 认证

### Phase 2：后端搜索服务
1. 实现豆瓣爬取模块
2. 实现 Google Books API 模块
3. 实现 Open Library API 模块
4. 实现搜索策略调度器（区域模式切换）
5. 实现搜索缓存

### Phase 3：iOS 基础
1. 搭建 SwiftUI 项目框架
2. 实现相机拍照功能
3. 实现 Vision OCR
4. 实现规则式书名提取
5. 对接后端 API 的网络层

### Phase 4：iOS 功能完善
1. 实现预分类模式完整流程
2. 实现装箱模式完整流程（含三色标识）
3. 实现设置页面（区域切换、API Key 配置）
4. 实现书库浏览和搜索

### Phase 5：智能增强
1. 对接大模型 API（书名提取、分类、联网搜索）
2. 可选：集成本地 Core ML 模型
3. 优化 OCR 识别准确率

### Phase 6：打磨
1. UI 优化和动画
2. 离线模式支持（先存本地，有网时同步）
3. 错误处理和边界情况
4. 数据导出功能（CSV/Excel）

## 编码规范

### 通用
- 代码注释使用中文
- Git commit message 使用中文
- 变量名和函数名使用英文，采用 camelCase

### Node.js 后端
- 使用 ES Modules (import/export)
- 错误处理统一用 try-catch + 错误中间件
- 环境变量通过 .env 文件管理
- 日志使用 console.log（开发阶段），生产环境用 winston

### Swift iOS
- 遵循 Swift 命名规范
- UI 使用 SwiftUI
- 网络请求使用 async/await
- 数据模型遵循 Codable 协议

## 环境变量 (.env)

```
# 服务器
PORT=3000
NODE_ENV=production

# 数据库
DATABASE_URL=mysql://user:password@localhost:3306/bookbox

# 搜索相关
GOOGLE_BOOKS_API_KEY=（非大陆模式使用）
DOUBAN_REQUEST_INTERVAL=3000
SEARCH_CACHE_TTL=604800

# 认证
API_TOKEN=（简单 token 认证）
```
