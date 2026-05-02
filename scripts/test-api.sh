#!/bin/bash
# BookBox 开发环境 API 全面测试
# 使用：先登录（或自动注册新用户），然后测试所有端点并清理数据
# 依赖：curl, python3

BASE="http://47.113.221.26/bookbox-dev/api"
TMP_R="/tmp/_bb_api_test.json"

PASS=0
FAIL=0

# ---- 辅助函数 ----

call() {
    local method="$1" path="$2" data="$3"
    local args=(-s -o "$TMP_R" -w "%{http_code}" -X "$method" "$BASE$path" \
        -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")
    [ -n "$data" ] && args+=(-d "$data")
    curl "${args[@]}"
}

extract() { python3 -c "import json; print(json.load(open('$TMP_R'))$1)" 2>/dev/null; }

status_only() {
    # 只返回 HTTP 状态码，不覆盖 TMP_R（用于 check 读取）
    curl -s -o /dev/null -w "%{http_code}" -X "$1" "$BASE$2" \
        -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
        ${3:+-d "$3"}
}

check() {
    local desc="$1" code="$2" expect="$3"
    if [ "$code" = "$expect" ] \
        || { [ "$expect" = "200|201" ] && { [ "$code" = "200" ] || [ "$code" = "201" ]; }; } \
        || { [ "$expect" = "200|204" ] && { [ "$code" = "200" ] || [ "$code" = "204" ]; }; }; then
        echo "  ✅ $desc → $code"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc → $code (expected $expect)"
        python3 -m json.tool "$TMP_R" 2>/dev/null | head -20
        FAIL=$((FAIL+1))
    fi
}

section() { echo ""; echo "--- $1 ---"; }
summary() {
    echo ""
    echo "========================================="
    echo "  测试完成"
    echo "  通过: $PASS"
    echo "  失败: $FAIL"
    echo "  总计: $((PASS+FAIL))"
    echo "========================================="
}

# ---- 登录/注册 ----

ensure_token() {
    # 先试已有 token，失败则注册新用户
    if [ -f /tmp/bookbox_dev_token.txt ]; then
        TOKEN=$(cat /tmp/bookbox_dev_token.txt)
        local ok
        ok=$(status_only GET /auth/me)
        if [ "$ok" = "200" ]; then
            echo "使用已有 token（用户已登录）"
            return 0
        fi
    fi
    local TS
    TS=$(date +%s)
    echo "注册新用户 apitest_$TS ..."
    local resp
    resp=$(curl -s -X POST "$BASE/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"apitest_$TS\",\"password\":\"testpass123\",\"displayName\":\"测试用户\"}")
    TOKEN=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))")
    if [ -z "$TOKEN" ]; then
        echo "注册失败，尝试登录已有用户..."
        resp=$(curl -s -X POST "$BASE/auth/login" \
            -H "Content-Type: application/json" \
            -d '{"username":"testuser","password":"testpass123"}')
        TOKEN=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))")
    fi
    echo "$TOKEN" > /tmp/bookbox_dev_token.txt
    if [ -z "$TOKEN" ]; then
        echo "❌ 无法获取 token，退出"
        exit 1
    fi
    echo "Token 获取成功"
}

# ---- Main ----

ensure_token

echo ""
echo "========================================="
echo "  BookBox 开发环境 API 全面测试"
echo "  服务器: $BASE"
echo "  时间: $(date)"
echo "========================================="

# ========== 1. 公共端点 ==========
section "1. 公共端点"
R=$(call GET /health)
check "基础健康检查" "$R" 200

R=$(call GET /health/detailed)
check "详细健康检查（DB+AI+供应商）" "$R" 200

# ========== 2. 认证 ==========
section "2. 认证"
R=$(call GET /auth/me)
check "获取当前用户" "$R" 200

# ========== 3. 书库 ==========
section "3. 书库 API"
R=$(call GET /libraries)
check "获取书库列表" "$R" 200

R=$(call POST /libraries '{"name":"API测试书库","description":"由测试脚本创建"}')
check "创建书库" "$R" 201
LIB_ID=$(extract "['id']")
echo "  新建书库ID: $LIB_ID"

R=$(call GET /libraries/$LIB_ID)
check "获取书库详情" "$R" 200

R=$(call PUT /libraries/$LIB_ID '{"name":"API测试书库-已更新"}')
check "更新书库" "$R" 200

# ========== 4. 房间 ==========
section "4. 房间 API"
R=$(call GET /rooms)
check "获取房间列表" "$R" 200
ROOM_ID=$(extract "[0]['id']")

R=$(call POST /rooms '{"name":"API测试房间","libraryId":'"$LIB_ID"'}')
check "创建房间" "$R" 200|201
ROOM_ID2=$(extract "['id']")

R=$(call PUT /rooms/$ROOM_ID '{"name":"默认房间-已更新"}')
check "更新房间" "$R" 200

# ========== 5. 书架 ==========
section "5. 书架 API"
R=$(call GET /shelves)
check "获取书架列表" "$R" 200

R=$(call POST /shelves '{"name":"API测试书架","libraryId":'"$LIB_ID"',"roomId":'"$ROOM_ID"'}')
check "创建书架" "$R" 200|201
SHELF_ID=$(extract "['id']")
echo "  新建书架ID: $SHELF_ID"

R=$(call GET /shelves/$SHELF_ID)
check "获取书架详情" "$R" 200

R=$(call PUT /shelves/$SHELF_ID '{"name":"API测试书架-已更新"}')
check "更新书架" "$R" 200

# ========== 6. 箱子 ==========
section "6. 箱子 API"
R=$(call GET /boxes)
check "获取箱子列表" "$R" 200

R=$(call POST /boxes '{"name":"API测试箱子","libraryId":'"$LIB_ID"',"roomId":'"$ROOM_ID"'}')
check "创建箱子" "$R" 200|201
BOX_ID=$(extract "['id']")
BOX_UID=$(extract "['boxUid']")
echo "  新建箱子ID: $BOX_ID  UID: $BOX_UID"

R=$(call GET /boxes/$BOX_ID)
check "获取箱子详情" "$R" 200

R=$(call PUT /boxes/$BOX_ID '{"name":"API测试箱子-已更新"}')
check "更新箱子" "$R" 200

# ========== 7. 书籍 ==========
section "7. 书籍 API"
R=$(call GET "/books?libraryId=$LIB_ID")
check "获取书籍列表（分页）" "$R" 200

R=$(call POST /books '{"title":"测试书籍","author":"测试作者","libraryId":'"$LIB_ID"'}')
check "创建书籍" "$R" 200|201
BOOK_ID=$(extract "['id']")
echo "  新建书籍ID: $BOOK_ID"

R=$(call GET /books/$BOOK_ID)
check "获取书籍详情" "$R" 200

R=$(call PUT /books/$BOOK_ID '{"title":"测试书籍-已更新","author":"测试作者"}')
check "更新书籍" "$R" 200

R=$(call POST /books/batch '{"books":[{"title":"批量大A","libraryId":'"$LIB_ID"'},{"title":"批量大B","libraryId":'"$LIB_ID"'}]}')
check "批量创建书籍" "$R" 200|201

R=$(call POST /books/check-duplicates '{"books":[{"title":"测试书籍"}]}')
check "查重检测" "$R" 200

R=$(call GET /books/duplicates)
check "全库查重" "$R" 200

R=$(call GET /books/trash)
check "回收站列表" "$R" 200

R=$(call POST /books/verify '{"title":"三体","region":"cn"}')
check "书籍校验（豆瓣/Google）" "$R" 200

# ========== 8. 分类 ==========
section "8. 分类 API"
R=$(call GET /categories)
check "获取分类列表" "$R" 200

R=$(call POST /categories '{"name":"API测试分类"}')
check "创建分类" "$R" 200|201
CAT_ID=$(extract "['id']")
echo "  新建分类ID: $CAT_ID"

R=$(call PUT /categories/$CAT_ID '{"name":"API测试分类-已更新"}')
check "更新分类" "$R" 200

# ========== 9. 设置 ==========
section "9. 设置 API"
R=$(call GET /settings)
check "获取用户设置" "$R" 200
R=$(call PUT /settings '{"preferredLanguage":"zh-Hans"}')
check "更新用户设置" "$R" 200

# ========== 10. 扫描记录 ==========
section "10. 扫描记录 API"
R=$(call POST /scans '{"mode":"preclassify"}')
check "创建扫描记录(预分类)" "$R" 200|201

R=$(call POST /scans '{"mode":"boxing"}')
check "创建扫描记录(装箱)" "$R" 200|201

R=$(call GET /scans)
check "获取扫描记录列表" "$R" 200

# ========== 11. 供应商 ==========
section "11. 供应商 API"
R=$(call GET /suppliers)
check "获取供应商列表" "$R" 200

# ========== 12. LLM 缓存统计 ==========
section "12. LLM 缓存统计"
R=$(call GET /llm/cache-stats)
check "获取缓存统计" "$R" 200
R=$(call POST /llm/cache-stats/reset)
check "重置缓存统计" "$R" 200

# ========== 13. 操作日志 ==========
section "13. 操作日志 API"
R=$(call GET /logs)
check "获取全部操作日志" "$R" 200
R=$(call GET /books/$BOOK_ID/logs)
check "获取书籍操作日志" "$R" 200

# ========== 14. 书库总览 ==========
section "14. 书库总览"
R=$(call GET "/library/overview?libraryId=$LIB_ID")
check "获取书库总览" "$R" 200

# ========== 15. 书籍移动 ==========
section "15. 书籍移动"
R=$(call POST /books/$BOOK_ID/move '{"toType":"shelf","toId":'"$SHELF_ID"'}')
check "移动书籍到书架" "$R" 200

R=$(call POST /books/$BOOK_ID/move '{"toType":"box","toId":'"$BOX_ID"'}')
check "移动书籍到箱子" "$R" 200

# ========== 16. 箱/架书籍管理 ==========
section "16. 箱/架书籍管理"
R=$(call POST /boxes/$BOX_ID/books '{"bookIds":['"$BOOK_ID"']}')
check "添加书籍到箱子" "$R" 200

R=$(call DELETE /boxes/$BOX_ID/books/$BOOK_ID)
check "从箱子移除书籍" "$R" 200|204

R=$(call POST /shelves/$SHELF_ID/books '{"bookIds":['"$BOOK_ID"']}')
check "添加书籍到书架" "$R" 200

R=$(call DELETE /shelves/$SHELF_ID/books/$BOOK_ID)
check "从书架移除书籍" "$R" 200|204

# ========== 17. 回收站操作 ==========
section "17. 回收站操作"
R=$(call DELETE /books/$BOOK_ID)
check "软删书籍（进回收站）" "$R" 200

R=$(call POST /books/$BOOK_ID/restore)
check "恢复书籍" "$R" 200

R=$(call DELETE /books/$BOOK_ID)
check "再次软删" "$R" 200

R=$(call DELETE /books/$BOOK_ID/purge)
check "彻底删除（purge）" "$R" 200

# ========== 18. 删除测试数据 ==========
section "18. 删除测试数据"
[ -n "$CAT_ID" ] && { R=$(call DELETE /categories/$CAT_ID); check "删除测试分类" "$R" 200|204; }
[ -n "$BOX_ID" ] && { R=$(call DELETE /boxes/$BOX_ID); check "删除测试箱子" "$R" 200|204; }
[ -n "$SHELF_ID" ] && { R=$(call DELETE /shelves/$SHELF_ID); check "删除测试书架" "$R" 200|204; }
[ -n "$ROOM_ID2" ] && { R=$(call DELETE /rooms/$ROOM_ID2); check "删除测试房间" "$R" 200|204; }
[ -n "$LIB_ID" ] && { R=$(call DELETE /libraries/$LIB_ID); check "删除测试书库" "$R" 200; }

# ========== 统计 ==========
summary
rm -f "$TMP_R"
exit $FAIL
