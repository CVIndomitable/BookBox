# BookBox V2 升级方案

> 本文档描述 BookBox 从当前版本到 V2 的全部改动，供 Claude Code 按步骤执行。
> 改动涉及：数据模型重构、新增书架和操作日志、多模态大模型替代 OCR、语音交互悬浮窗、iOS 端服务器地址硬编码。

---

## 一、核心概念变更

### 1.1 引入"书库"层级

旧结构：`箱子 → 书`（通过 box_books 中间表多对多）

新结构：
```
书库（整个系统即一个书库）
├── 书架（shelves）—— 日常使用，书会经常移动
│   ├── 客厅书架
│   └── 卧室书架
└── 箱子（boxes）—— 归档存储，很少移动
    ├── 20260412-001
    └── 20260412-002
```

关键区分：
- **书架**：活跃区域，AI 语音找书时优先搜索书架
- **箱子**：归档区域，AI 找书时默认跳过箱子（除非用户明确要求"在所有地方找"）
- 一本书**只能在一个位置**（一个书架或一个箱子中），移动是更新操作，不是新增关联

### 1.2 OCR → 多模态大模型

旧流程：拍照 → Vision OCR → 规则提取书名 → 发后端
新流程：拍照 → 图片 base64 直接发给多模态大模型 → 大模型返回书名列表

识别场景不限于整齐排列的书脊，包括：随手摊开的书、封面朝上、歪着放的、多本堆叠等任意姿态。

### 1.3 语音交互

全局悬浮麦克风按钮，任何界面都可使用，支持自然语言操作书库。

---

## 二、数据模型变更

### 2.1 新增 shelves 表

```sql
CREATE TABLE shelves (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(200) NOT NULL,           -- 书架名称，如"客厅书架"
  location VARCHAR(200),                -- 位置描述，如"客厅靠窗"，可为空
  description TEXT,                     -- 备注，可为空
  book_count INT DEFAULT 0,             -- 书籍数量（冗余字段）
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

Prisma schema 对应：
```prisma
model Shelf {
  id          Int       @id @default(autoincrement())
  name        String    @db.VarChar(200)
  location    String?   @db.VarChar(200)
  description String?   @db.Text
  bookCount   Int       @default(0) @map("book_count")
  createdAt   DateTime  @default(now()) @map("created_at")
  updatedAt   DateTime  @updatedAt @map("updated_at")
  books       Book[]

  @@map("shelves")
}
```

### 2.2 修改 books 表：统一位置字段

**删除**旧的关联方式（通过 box_books 中间表），改为在 books 表直接记录位置：

新增字段：
```sql
ALTER TABLE books ADD COLUMN location_type ENUM('shelf', 'box', 'none') DEFAULT 'none';
ALTER TABLE books ADD COLUMN location_id INT DEFAULT NULL;
```

- `location_type = 'shelf'` + `location_id = shelves.id` → 书在某个书架上
- `location_type = 'box'` + `location_id = boxes.id` → 书在某个箱子里
- `location_type = 'none'` + `location_id = NULL` → 书未归入任何位置

Prisma schema 中 Book 模型修改：
```prisma
model Book {
  id            Int       @id @default(autoincrement())
  title         String    @db.VarChar(500)
  author        String?   @db.VarChar(500)
  isbn          String?   @db.VarChar(20)
  publisher     String?   @db.VarChar(200)
  coverUrl      String?   @map("cover_url") @db.Text
  categoryId    Int?      @map("category_id")
  verifyStatus  String?   @map("verify_status") @db.VarChar(20)  // matched/uncertain/not_found/manual
  verifySource  String?   @map("verify_source") @db.VarChar(50)
  rawOcrText    String?   @map("raw_ocr_text") @db.Text
  locationType  String    @default("none") @map("location_type") @db.VarChar(10)  // shelf/box/none
  locationId    Int?      @map("location_id")
  createdAt     DateTime  @default(now()) @map("created_at")
  updatedAt     DateTime  @updatedAt @map("updated_at")

  category      Category? @relation(fields: [categoryId], references: [id])
  shelf         Shelf?    @relation(fields: [locationId], references: [id], map: "fk_book_shelf")
  // 注意：locationId 可能指向 shelf 或 box，ORM 层面只建 shelf 的关系
  // box 关系通过手动查询处理，或者不建外键约束，仅做应用层关联
  logs          BookLog[]

  @@map("books")
}
```

**关于外键的处理**：因为 `location_id` 根据 `location_type` 指向不同的表，不适合建数据库外键约束。建议：
- 不在数据库层建 `location_id` 的外键
- 在应用层（路由/服务代码）中根据 `location_type` 做 JOIN 查询
- Prisma 中可以不声明 relation，用 raw query 或手动拼查询

### 2.3 废弃 box_books 中间表

旧的 `box_books` 表不再使用。迁移步骤：
1. 将 `box_books` 中现有数据迁移到 `books.location_type = 'box'` + `books.location_id = box_books.box_id`
2. 如果同一本书在多个箱子中（理论上不应该，但防御性处理），取最新的 `added_at` 对应的 box_id
3. 迁移完成后删除 `box_books` 表
4. 从 Prisma schema 中移除 BoxBook 模型

### 2.4 新增 book_logs 表（操作日志）

```sql
CREATE TABLE book_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  book_id INT NOT NULL,                              -- 关联书籍
  action ENUM('move', 'add', 'remove', 'edit', 'verify') NOT NULL,  -- 操作类型
  from_type VARCHAR(10),                             -- 来源类型：shelf/box/none，可为空（新增时）
  from_id INT,                                       -- 来源 ID，可为空
  to_type VARCHAR(10),                               -- 目标类型：shelf/box/none，可为空（删除时）
  to_id INT,                                         -- 目标 ID，可为空
  method VARCHAR(20) DEFAULT 'manual',               -- 操作方式：voice / manual / scan
  raw_input TEXT,                                    -- 原始输入（语音转文字内容），可为空
  ai_response TEXT,                                  -- AI 解析结果 JSON，可为空
  note TEXT,                                         -- 备注，可为空
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

Prisma schema：
```prisma
model BookLog {
  id          Int       @id @default(autoincrement())
  bookId      Int       @map("book_id")
  action      String    @db.VarChar(20)     // move/add/remove/edit/verify
  fromType    String?   @map("from_type") @db.VarChar(10)
  fromId      Int?      @map("from_id")
  toType      String?   @map("to_type") @db.VarChar(10)
  toId        Int?      @map("to_id")
  method      String    @default("manual") @db.VarChar(20)
  rawInput    String?   @map("raw_input") @db.Text
  aiResponse  String?   @map("ai_response") @db.Text
  note        String?   @db.Text
  createdAt   DateTime  @default(now()) @map("created_at")

  book        Book      @relation(fields: [bookId], references: [id])

  @@map("book_logs")
}
```

### 2.5 boxes 表保持不变

`boxes` 表结构不变，继续使用。只是关联方式从中间表改为 `books.location_type + location_id`。

`boxes` 表的 `book_count` 字段改为通过 `SELECT COUNT(*) FROM books WHERE location_type='box' AND location_id=?` 动态计算，或者在书籍移入/移出时同步更新。

---

## 三、API 变更

### 3.1 新增书架 API

```
GET    /api/shelves            — 获取所有书架列表（含 book_count）
POST   /api/shelves            — 新建书架 { name, location?, description? }
GET    /api/shelves/:id        — 获取书架详情及其中的书（分页）
PUT    /api/shelves/:id        — 更新书架信息
DELETE /api/shelves/:id        — 删除书架（书的 location 重置为 none）
```

路由文件：`src/routes/shelves.js`，在 `src/index.js` 中注册。

### 3.2 修改书籍 API

#### POST /api/books 和 POST /api/books/batch

请求体新增可选字段：
```json
{
  "title": "三体",
  "author": "刘慈欣",
  "locationType": "shelf",   // 新增：shelf / box / none（默认 none）
  "locationId": 1            // 新增：对应的 shelf 或 box 的 id
}
```

批量创建时：
```json
{
  "books": [...],
  "locationType": "box",    // 所有书统一放入
  "locationId": 3
}
```

#### GET /api/books

新增查询参数：
- `?locationType=shelf` — 只查书架上的书
- `?locationType=box` — 只查箱子里的书
- `?locationType=none` — 只查未归位的书
- `?locationId=5` — 查指定容器中的书
- `?shelfId=5` — 等价于 `locationType=shelf&locationId=5`
- `?boxId=3` — 等价于 `locationType=box&locationId=3`

#### PUT /api/books/:id

支持更新 `locationType` 和 `locationId`（即移动书籍）。移动时需要：
1. 更新书的 `location_type` 和 `location_id`
2. 更新旧容器和新容器的 `book_count`
3. 写入 `book_logs` 一条 move 记录

### 3.3 新增移动书籍专用 API

```
POST /api/books/:id/move
```

请求体：
```json
{
  "toType": "shelf",        // 目标类型
  "toId": 2,                // 目标 ID
  "method": "voice",        // 操作方式：voice / manual
  "rawInput": "把三体放到卧室书架"  // 原始语音文本，可选
}
```

这个接口内部执行：更新位置 + 更新 book_count + 写日志，作为一个事务。

### 3.4 新增操作日志 API

```
GET /api/books/:id/logs     — 获取单本书的操作历史
GET /api/logs               — 获取全部操作日志（支持分页、按 action/method 筛选）
```

### 3.5 新增语音指令 API

```
POST /api/voice/execute
```

请求体：
```json
{
  "text": "把三体放到卧室书架",       // 语音转文字结果
  "context": {                       // 当前上下文（可选，帮助 AI 理解）
    "currentView": "library",
    "selectedBookId": null
  }
}
```

这个接口的实现逻辑：
1. 从数据库查出当前所有书架名称、箱子名称、书籍列表（仅标题和当前位置）
2. 拼接 system prompt + 用户输入，调用大模型（MiMo）
3. 大模型返回结构化 JSON 指令
4. 后端解析并执行指令（移动、查询、修正等）
5. 返回执行结果 + 写入 book_logs

大模型返回格式约定：
```json
{
  "action": "move",                  // move / query / edit / list
  "bookTitle": "三体",               // 涉及的书名（模糊匹配用）
  "bookId": 12,                      // 如果能确定 ID（AI 根据上下文推断）
  "target": { "type": "shelf", "name": "卧室书架" },
  "reply": "好的，已把《三体》移到卧室书架了"   // 给用户的回复文本
}
```

**注意**：这个接口也可以选择不做在后端，而是在 iOS 端直接调大模型解析意图，再调用已有的 move/query API。两种方案都可以，但放后端的好处是可以在一个事务里完成"解析+执行+日志"，且 iOS 端逻辑更简单。具体选择交给实现时决定。

### 3.6 boxes API 修改

`POST /api/boxes/:id/books` 和 `DELETE /api/boxes/:id/books/:bookId` 这两个接口的内部实现要改：不再操作 `box_books` 中间表，改为更新 `books.location_type` 和 `books.location_id`。

接口签名和行为保持向后兼容。同样为 shelves 新增：
```
POST   /api/shelves/:id/books          — 批量将书放入书架 { bookIds: [1,2,3] }
DELETE /api/shelves/:id/books/:bookId  — 从书架移走一本书（location 重置为 none）
```

### 3.7 书库总览 API（新增）

```
GET /api/library/overview
```

返回书库全貌，供首页和语音 AI 上下文使用：
```json
{
  "totalBooks": 156,
  "unlocated": 3,
  "shelves": [
    { "id": 1, "name": "客厅书架", "location": "客厅靠窗", "bookCount": 45 },
    { "id": 2, "name": "卧室书架", "location": "卧室床头", "bookCount": 23 }
  ],
  "boxes": [
    { "id": 1, "boxUid": "20260412-001", "name": "文学类", "bookCount": 30 },
    { "id": 2, "boxUid": "20260412-002", "name": "技术类", "bookCount": 55 }
  ]
}
```

---

## 四、iOS 端变更

### 4.1 服务器地址硬编码

在 `NetworkService.swift`（或新建 `AppConfig.swift`）中将服务器地址写为常量：

```swift
enum AppConfig {
    static let serverBaseURL = "http://47.113.221.26/bookbox/api"
    static let apiToken = "bookbox-dev-token"  // 或者 token 仍然从设置读取
}
```

设置页中移除"服务器地址"输入框。API Token 看情况是否也写死（目前只有一个用户）。

### 4.2 多模态大模型替代 OCR

#### 新增 MiMoService.swift

封装对 MiMo API 的调用，走 Anthropic 兼容协议：

```swift
// MiMoService.swift
// 对 MiMo API 的 Anthropic 兼容协议封装

class MiMoService {
    // Base URL 和 API Key 从 UserSettings 读取
    // 默认 Base URL: https://api.xiaomimimo.com/anthropic

    /// 多模态识别：发送图片，返回书籍列表
    func recognizeBooks(imageData: Data) async throws -> [RecognizedBook]

    /// 纯文本对话：发送文字指令，返回结构化操作
    func processVoiceCommand(text: String, context: LibraryContext) async throws -> VoiceCommandResult
}
```

识别书籍的 API 调用格式（Anthropic 协议）：
```json
{
  "model": "mimo-v2-omni",
  "max_tokens": 2048,
  "messages": [{
    "role": "user",
    "content": [
      {
        "type": "image",
        "source": {
          "type": "base64",
          "media_type": "image/jpeg",
          "data": "<base64编码的图片>"
        }
      },
      {
        "type": "text",
        "text": "请识别这张照片中所有可见的书籍。书籍可能以任意角度、姿态出现，包括书脊朝外、封面朝上、摊开、歪斜、堆叠等。请返回 JSON 数组，每项包含：title（书名）、author（作者，看不到则为 null）、confidence（high/medium/low）。只返回 JSON，不要其他文字。"
      }
    ]
  }]
}
```

语音指令的 API 调用使用 `mimo-v2-flash`（快且便宜）：
```json
{
  "model": "mimo-v2-flash",
  "max_tokens": 1024,
  "system": "你是 BookBox 书库助手。用户通过语音管理自己的书库。当前书库状态：\n书架：客厅书架（45本）、卧室书架（23本）\n箱子（已归档）：20260412-001 文学类（30本）、20260412-002 技术类（55本）\n\n请根据用户指令返回 JSON：\n{\"action\": \"move|query|edit|list\", \"bookTitle\": \"书名\", \"target\": {\"type\": \"shelf|box\", \"name\": \"名称\"}, \"reply\": \"回复用户的话\"}\n只返回 JSON。",
  "messages": [{
    "role": "user",
    "content": "把三体放到卧室书架"
  }]
}
```

#### 修改拍照识别流程

- `CameraView.swift`：拍照后不再调 `OCRService`，改为将图片压缩后调 `MiMoService.recognizeBooks()`
- `OCRService.swift` 和 `BookExtractor.swift`：保留代码作为 fallback，当用户未配置大模型 API Key 时使用旧流程
- `ScanResultView.swift`：适配新的返回格式（多模态返回的 confidence 映射到三色标识：high→绿、medium→黄、low→红）

### 4.3 设置页修改

大模型配置部分改为：
- **MiMo API Key**（必填，用于多模态识别和语音指令）
- **视觉识别模型**：默认 `mimo-v2-omni`（一般不需要改）
- **文本对话模型**：默认 `mimo-v2-flash`（一般不需要改）

去掉原来的"服务商选择"（openai/claude/other），简化为只支持 MiMo。如果后续要支持多服务商再扩展。

API 端点写死为 `https://api.xiaomimimo.com/anthropic`（或者留一个高级设置给用户改）。

### 4.4 新增书架相关界面

- `Views/Library/ShelfListView.swift` — 书架列表
- `Views/Library/ShelfDetailView.swift` — 书架详情（其中的书）
- `Views/Library/ShelfCreateView.swift` — 新建书架
- `Models/Shelf.swift` — 书架数据模型

`LibraryView.swift` 改为分两个 section 展示：上面是书架列表，下面是箱子列表。

### 4.5 全局悬浮麦克风按钮

在 `BookBoxApp.swift` 的根视图上加 `.overlay`：

```swift
@main
struct BookBoxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay(alignment: .bottomTrailing) {
                    VoiceAssistantButton()
                        .padding()
                }
        }
    }
}
```

`Views/Components/VoiceAssistantButton.swift`：
- 默认显示为一个小麦克风悬浮按钮（可拖动位置）
- 点击后展开为一个小面板，显示：正在录音动画 / 转文字结果 / AI 回复
- 使用 `Speech` 框架做语音转文字（`SFSpeechRecognizer`）
- 松开后发送文字给 `MiMoService.processVoiceCommand()`
- 收到回复后显示结果，并可选用 `AVSpeechSynthesizer` 语音播报

`Services/SpeechService.swift`：
- 封装 `SFSpeechRecognizer` + `AVAudioEngine`
- 支持中文识别
- 实时显示识别中的文字

交互流程：
1. 用户按住麦克风按钮（或点击一次开始、再点一次结束）
2. 实时语音转文字，显示在面板上
3. 松开/停止后，文字发给 MiMo
4. MiMo 返回指令 JSON
5. iOS 端解析指令，调用后端对应 API 执行
6. 显示执行结果："好的，已把《三体》移到卧室书架了"
7. 写入 book_logs（通过 move API 自动记录）

支持的语音指令场景：
- "把《三体》放到卧室书架" → 调用 `POST /api/books/:id/move`
- "三体在哪" → 调用 `GET /api/books?search=三体`，读取 location 信息回复
- "客厅书架上有什么书" → 调用 `GET /api/shelves/:id`
- "刚才第三本识别错了，应该叫《百年孤独》" → 调用 `PUT /api/books/:id`
- "新建一个书架叫书房书架" → 调用 `POST /api/shelves`

### 4.6 数据模型更新

`Models/Book.swift` 新增字段：
```swift
struct Book: Codable, Identifiable {
    // ... 原有字段
    var locationType: String?   // "shelf" / "box" / "none"
    var locationId: Int?
}
```

新增 `Models/Shelf.swift`：
```swift
struct Shelf: Codable, Identifiable {
    var id: Int
    var name: String
    var location: String?
    var description: String?
    var bookCount: Int
    var createdAt: Date
    var updatedAt: Date
}
```

新增 `Models/BookLog.swift`：
```swift
struct BookLog: Codable, Identifiable {
    var id: Int
    var bookId: Int
    var action: String
    var fromType: String?
    var fromId: Int?
    var toType: String?
    var toId: Int?
    var method: String
    var rawInput: String?
    var aiResponse: String?
    var note: String?
    var createdAt: Date
}
```

---

## 五、数据迁移步骤

在服务器上执行，按顺序操作：

### Step 1：备份数据库
```bash
mysqldump -h 127.0.0.1 -u root -p bookbox > /tmp/bookbox_backup_$(date +%Y%m%d).sql
```

### Step 2：新建 shelves 表
通过 Prisma schema 修改后 `npx prisma db push` 自动创建。

### Step 3：给 books 表加字段
```sql
ALTER TABLE books ADD COLUMN location_type VARCHAR(10) DEFAULT 'none';
ALTER TABLE books ADD COLUMN location_id INT DEFAULT NULL;
```

### Step 4：迁移 box_books 数据
```sql
-- 将 box_books 中的关联写入 books 表
-- 如果一本书在多个箱子中，取最新的
UPDATE books b
JOIN (
  SELECT book_id, box_id
  FROM box_books
  WHERE id IN (
    SELECT MAX(id) FROM box_books GROUP BY book_id
  )
) bb ON b.id = bb.book_id
SET b.location_type = 'box', b.location_id = bb.box_id;
```

### Step 5：验证迁移结果
```sql
-- 确认迁移数据量一致
SELECT COUNT(DISTINCT book_id) FROM box_books;
SELECT COUNT(*) FROM books WHERE location_type = 'box';
```

### Step 6：创建 book_logs 表
通过 Prisma schema 修改后 `npx prisma db push` 自动创建。

### Step 7：删除 box_books 表
确认迁移无误后：
```sql
DROP TABLE box_books;
```

从 Prisma schema 中移除 BoxBook 模型。

---

## 六、开发执行顺序

### Phase A：数据模型和后端（先做）

1. 修改 `server/prisma/schema.prisma`：新增 Shelf、BookLog 模型，修改 Book 模型加 locationType/locationId，移除 BoxBook 模型
2. 执行数据迁移（按第五节步骤）
3. 新建 `server/src/routes/shelves.js`：书架 CRUD
4. 修改 `server/src/routes/books.js`：适配新的位置字段，新增 move 接口和 logs 查询
5. 修改 `server/src/routes/boxes.js`：内部实现从操作 box_books 改为更新 books.location_*
6. 新建 `server/src/routes/logs.js`：操作日志查询
7. 新建 `server/src/routes/library.js`：书库总览接口
8. 在 `server/src/index.js` 中注册新路由

### Phase B：iOS 数据层适配

1. 更新 `Models/Book.swift` 加位置字段
2. 新建 `Models/Shelf.swift`、`Models/BookLog.swift`
3. `NetworkService.swift` 中新增书架 API、move API、logs API、library overview API 的调用方法
4. 硬编码服务器地址到 `AppConfig`

### Phase C：iOS 多模态识别

1. 新建 `Services/MiMoService.swift`
2. 修改拍照流程，用 MiMo 替代 OCR
3. 适配 `ScanResultView.swift` 展示识别结果
4. 设置页简化大模型配置

### Phase D：iOS 书库界面重构

1. 改造 `LibraryView.swift`：分书架/箱子两个区域
2. 新建书架相关界面（列表/详情/新建）
3. 书籍详情页展示当前位置和操作日志

### Phase E：语音交互

1. 新建 `Services/SpeechService.swift`：语音转文字封装
2. 新建 `Views/Components/VoiceAssistantButton.swift`：悬浮按钮 + 面板
3. 在 MiMoService 中实现 `processVoiceCommand()`
4. 串联完整流程：语音 → 文字 → AI解析 → API调用 → 结果展示

---

## 七、注意事项

1. **MiMo API Key 由用户在 iOS 设置页配置**，iOS 端直接调用 MiMo API，不经过 BookBox 后端转发
2. **服务器地址写死**：`http://47.113.221.26/bookbox/api`，后端 API Token 也可以写死（`bookbox-dev-token`）
3. **图片压缩**：发给 MiMo 前要压缩图片，建议 JPEG quality 0.6-0.8，长边不超过 2048px，控制 base64 大小
4. **语音权限**：iOS 需要在 Info.plist 中声明麦克风和语音识别权限（`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`）
5. **错误兜底**：MiMo API 调用失败时（网络错误、Key无效等），给用户明确的中文错误提示，拍照识别场景可 fallback 到旧的 OCR 流程
6. **book_count 同步**：每次 move/add/remove 操作都要更新 shelves 和 boxes 表的 `book_count`，建议在事务中处理
7. **旧的 scan_records 表保留**，但 `ocr_result` 字段可以改为存大模型的原始返回 JSON
