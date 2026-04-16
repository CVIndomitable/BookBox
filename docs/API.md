# API 设计

> 权威来源是 `server/src/routes/*.js`。此文档为速查版，参数与行为以代码为准。

## 健康检查（无需认证）
- `GET    /api/health`

## 书库管理
- `GET    /api/libraries`          — 获取所有书库列表（附带书籍数量）
- `POST   /api/libraries`          — 新建书库 `{ name, location?, description? }`，同步创建"默认房间"
- `GET    /api/libraries/:id`      — 获取书库详情（含总览统计：书籍数/房间/书架/箱子）
- `PUT    /api/libraries/:id`      — 更新书库信息
- `DELETE /api/libraries/:id`      — 删除书库（关联数据 libraryId 置空；房间随书库 cascade 删除）

## 房间管理
- `GET    /api/rooms?libraryId=`   — 获取房间列表（可按书库筛选）
- `POST   /api/rooms`              — 新建房间 `{ name, libraryId, description? }`
- `GET    /api/rooms/:id`          — 房间详情（含其中的书架/箱子）
- `PUT    /api/rooms/:id`          — 更新房间 `{ name?, description? }`
- `DELETE /api/rooms/:id`          — 删除房间（默认房间不可删；房间下的书架/箱子转移到同书库的默认房间）

## 书架管理
- `GET    /api/shelves?libraryId=&roomId=`  — 获取所有书架列表（可按书库/房间筛选）
- `POST   /api/shelves`            — 新建书架 `{ name, location?, description?, libraryId?, roomId? }`（仅传 libraryId 时自动归入默认房间；传 roomId 时 libraryId 以房间为准）
- `GET    /api/shelves/:id`        — 获取书架详情及其中的书（分页）
- `PUT    /api/shelves/:id`        — 更新书架信息（支持 `roomId` / `libraryId` 搬动到其它房间/书库）
- `DELETE /api/shelves/:id`        — 删除书架（书的 location 重置为 none）
- `POST   /api/shelves/:id/books`  — 批量将书放入书架 `{ bookIds: [1,2,3] }`
- `DELETE /api/shelves/:id/books/:bookId` — 从书架移走一本书

## 箱子管理
- `GET    /api/boxes?libraryId=&roomId=`  — 获取所有箱子列表（可按书库/房间筛选）
- `POST   /api/boxes`            — 新建箱子 `{ name, description?, libraryId?, roomId? }`（同 shelves 的归属规则）
- `GET    /api/boxes/:id`        — 获取箱子详情及其中的书（分页）
- `PUT    /api/boxes/:id`        — 更新箱子信息（支持 `roomId` / `libraryId` 搬动）
- `DELETE /api/boxes/:id`        — 删除箱子（书的 location 重置为 none）
- `POST   /api/boxes/:id/books`  — 向箱子中添加书籍
- `DELETE /api/boxes/:id/books/:bookId` — 从箱子中移除一本书

## 书籍管理
- `GET    /api/books`            — 获取书籍列表（支持 locationType/locationId/shelfId/boxId 筛选）
- `POST   /api/books`            — 新增书籍（支持 locationType/locationId）
- `GET    /api/books/:id`        — 获取书籍详情（含位置信息）
- `PUT    /api/books/:id`        — 更新书籍（支持移动位置）
- `DELETE /api/books/:id`        — 删除书籍
- `POST   /api/books/batch`      — 批量新增（支持 locationType/locationId，兼容旧 boxId）
- `POST   /api/books/:id/move`   — 移动书籍到指定位置
- `GET    /api/books/:id/logs`   — 获取单本书的操作历史

## 操作日志
- `GET    /api/logs`             — 获取全部操作日志（支持分页、按 action/method 筛选）

## 书库总览
- `GET    /api/library/overview` — 书库全貌（支持 `?libraryId=` 按书库筛选）

## AI 识别（服务器端 LLM）
- `POST   /api/llm/recognize`    — 多模态识别书籍 `{ image: "base64..." }` → `{ books: [{title, author, confidence}] }`
- `POST   /api/llm/voice-command` — 语音指令解析 `{ text, systemPrompt }` → `{ action, bookTitle, target, reply }`

## 其它

- 分类、扫描记录、设置、书籍校验接口同 V1，见 `server/src/routes/categories.js` / `scans.js` / `settings.js` / `books.js`
