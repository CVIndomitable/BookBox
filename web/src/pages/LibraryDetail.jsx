import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { libraries, books, members } from '../services/api';
import { useAuth } from '../hooks/useAuth';
import ImportExport from '../components/ImportExport';
import './LibraryDetail.css';

export default function LibraryDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [library, setLibrary] = useState(null);
  const [bookList, setBookList] = useState([]);
  const [memberList, setMemberList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('books');
  const [searchQuery, setSearchQuery] = useState('');
  const [showAddMember, setShowAddMember] = useState(false);
  const [newMemberUsername, setNewMemberUsername] = useState('');
  const [newMemberRole, setNewMemberRole] = useState('member');
  const [showAddBook, setShowAddBook] = useState(false);
  const [newBookTitle, setNewBookTitle] = useState('');
  const [newBookAuthor, setNewBookAuthor] = useState('');
  const [newBookPublisher, setNewBookPublisher] = useState('');
  const [newBookIsbn, setNewBookIsbn] = useState('');

  useEffect(() => {
    loadLibrary();
    loadMembers();
  }, [id]);

  // 搜索输入 debounce 500ms 再请求后端，避免每次按键打网
  useEffect(() => {
    const h = setTimeout(() => { loadBooks(); }, searchQuery ? 500 : 0);
    return () => clearTimeout(h);
  }, [id, searchQuery]);

  const loadLibrary = async () => {
    try {
      const data = await libraries.get(id);
      setLibrary(data);
    } catch (err) {
      console.error('加载书库失败:', err);
      alert(err.error || '加载失败');
      navigate('/');
    } finally {
      setLoading(false);
    }
  };

  const loadBooks = async () => {
    try {
      const params = { libraryId: id, pageSize: 100 };
      if (searchQuery.trim()) params.search = searchQuery.trim();
      // 后端返回 { data: [...], pagination }；提取 data 数组
      const resp = await books.list(params);
      setBookList(Array.isArray(resp) ? resp : (resp?.data || []));
    } catch (err) {
      console.error('加载书籍失败:', err);
    }
  };

  const loadMembers = async () => {
    try {
      const data = await members.list(id);
      setMemberList(data.members || []);
    } catch (err) {
      console.error('加载成员失败:', err);
    }
  };

  const handleAddMember = async (e) => {
    e.preventDefault();
    try {
      await members.add(id, { username: newMemberUsername, role: newMemberRole });
      setShowAddMember(false);
      setNewMemberUsername('');
      setNewMemberRole('member');
      loadMembers();
    } catch (err) {
      alert(err.error || '添加失败');
    }
  };

  const handleRemoveMember = async (userId) => {
    if (!confirm('确定移除此成员？')) return;
    try {
      await members.remove(id, userId);
      loadMembers();
    } catch (err) {
      alert(err.error || '移除失败');
    }
  };

  const handleDeleteBook = async (bookId) => {
    if (!confirm('确定删除此书？')) return;
    try {
      await books.delete(bookId);
      loadBooks();
    } catch (err) {
      alert(err.error || '删除失败');
    }
  };

  const handleAddBook = async (e) => {
    e.preventDefault();
    if (!newBookTitle.trim()) return;
    try {
      await books.create({
        libraryId: parseInt(id),
        title: newBookTitle.trim(),
        author: newBookAuthor.trim() || undefined,
        publisher: newBookPublisher.trim() || undefined,
        isbn: newBookIsbn.trim() || undefined,
        verifyStatus: 'manual',
      });
      setShowAddBook(false);
      setNewBookTitle('');
      setNewBookAuthor('');
      setNewBookPublisher('');
      setNewBookIsbn('');
      loadBooks();
    } catch (err) {
      alert(err.error || '添加失败');
    }
  };

  // 后端已按 search 过滤，前端直接渲染
  const filteredBooks = bookList;

  const canManage = library?.role === 'owner' || library?.role === 'admin';

  if (loading) {
    return <div className="loading">加载中...</div>;
  }

  if (!library) {
    return null;
  }

  return (
    <div className="library-detail">
      <header className="detail-header">
        <button onClick={() => navigate('/')} className="back-btn">← 返回</button>
        <div className="header-info">
          <h1>{library.name}</h1>
          {library.location && <p className="location">{library.location}</p>}
        </div>
      </header>

      <div className="tabs">
        <button
          className={activeTab === 'books' ? 'active' : ''}
          onClick={() => setActiveTab('books')}
        >
          书籍 ({library.totalBooks})
        </button>
        <button
          className={activeTab === 'members' ? 'active' : ''}
          onClick={() => setActiveTab('members')}
        >
          成员 ({memberList.length})
        </button>
        <button
          className={activeTab === 'import' ? 'active' : ''}
          onClick={() => setActiveTab('import')}
        >
          导入/导出
        </button>
        <button
          className={activeTab === 'stats' ? 'active' : ''}
          onClick={() => setActiveTab('stats')}
        >
          统计
        </button>
      </div>

      <div className="tab-content">
        {activeTab === 'books' && (
          <div className="books-tab">
            <div className="toolbar">
              <input
                type="text"
                placeholder="搜索书名或作者..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="search-input"
              />
              <button className="btn-primary" onClick={() => setShowAddBook(true)}>+ 添加书籍</button>
            </div>

            {showAddBook && (
              <form className="add-book-form" onSubmit={handleAddBook}>
                <input
                  type="text"
                  placeholder="书名（必填）"
                  value={newBookTitle}
                  onChange={(e) => setNewBookTitle(e.target.value)}
                  required
                />
                <input
                  type="text"
                  placeholder="作者"
                  value={newBookAuthor}
                  onChange={(e) => setNewBookAuthor(e.target.value)}
                />
                <input
                  type="text"
                  placeholder="出版社"
                  value={newBookPublisher}
                  onChange={(e) => setNewBookPublisher(e.target.value)}
                />
                <input
                  type="text"
                  placeholder="ISBN"
                  value={newBookIsbn}
                  onChange={(e) => setNewBookIsbn(e.target.value)}
                />
                <div className="form-actions">
                  <button type="submit" className="btn-primary">保存</button>
                  <button type="button" className="btn-secondary" onClick={() => setShowAddBook(false)}>取消</button>
                </div>
              </form>
            )}

            {filteredBooks.length === 0 ? (
              <div className="empty">暂无书籍</div>
            ) : (
              <div className="book-list">
                {filteredBooks.map((book) => (
                  <div key={book.id} className="book-item">
                    <div className="book-info">
                      <h3>{book.title}</h3>
                      {book.author && <p className="author">{book.author}</p>}
                      <p className="meta">
                        {book.locationType === 'shelf' && `书架 #${book.locationId}`}
                        {book.locationType === 'box' && `箱子 #${book.locationId}`}
                        {book.locationType === 'none' && '未放置'}
                      </p>
                    </div>
                    {canManage && (
                      <button
                        onClick={() => handleDeleteBook(book.id)}
                        className="btn-danger-small"
                      >
                        删除
                      </button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {activeTab === 'members' && (
          <div className="members-tab">
            {canManage && (
              <div className="toolbar">
                <button onClick={() => setShowAddMember(true)} className="btn-primary">
                  + 添加成员
                </button>
              </div>
            )}

            <div className="member-list">
              {memberList.map((member) => (
                <div key={member.id} className="member-item">
                  <div className="member-info">
                    <h3>{member.user.displayName || member.user.username}</h3>
                    <span className={`role-badge ${member.role}`}>
                      {member.role === 'owner' ? '所有者' : member.role === 'admin' ? '管理员' : '成员'}
                    </span>
                  </div>
                  {canManage && member.role !== 'owner' && member.user.id !== user.id && (
                    <button
                      onClick={() => handleRemoveMember(member.user.id)}
                      className="btn-danger-small"
                    >
                      移除
                    </button>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {activeTab === 'import' && (
          <div className="import-tab">
            <ImportExport libraryId={id} onImportComplete={loadBooks} />
          </div>
        )}

        {activeTab === 'stats' && (
          <div className="stats-tab">
            <div className="stat-card">
              <h3>总书籍数</h3>
              <p className="stat-value">{library.totalBooks}</p>
            </div>
            <div className="stat-card">
              <h3>未放置</h3>
              <p className="stat-value">{library.unlocated}</p>
            </div>
            <div className="stat-card">
              <h3>书架数</h3>
              <p className="stat-value">{library.shelves?.length || 0}</p>
            </div>
            <div className="stat-card">
              <h3>箱子数</h3>
              <p className="stat-value">{library.boxes?.length || 0}</p>
            </div>
          </div>
        )}
      </div>

      {showAddMember && (
        <div className="modal" onClick={() => setShowAddMember(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <h2>添加成员</h2>
            <form onSubmit={handleAddMember}>
              <div className="form-group">
                <label>用户名</label>
                <input
                  type="text"
                  value={newMemberUsername}
                  onChange={(e) => setNewMemberUsername(e.target.value)}
                  required
                  autoFocus
                />
              </div>
              <div className="form-group">
                <label>角色</label>
                <select
                  value={newMemberRole}
                  onChange={(e) => setNewMemberRole(e.target.value)}
                >
                  <option value="member">成员</option>
                  <option value="admin">管理员</option>
                </select>
              </div>
              <div className="modal-actions">
                <button type="button" onClick={() => setShowAddMember(false)} className="btn-secondary">
                  取消
                </button>
                <button type="submit" className="btn-primary">添加</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
