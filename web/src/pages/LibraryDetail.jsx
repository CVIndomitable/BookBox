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
  const [showEditBook, setShowEditBook] = useState(null); // book object or null
  const emptyBook = {
    title: '', author: '', adaptation: '', translator: '', authorNationality: '',
    isbn: '', publisher: '', edition: '', publisherPerson: '',
    responsibleEditor: '', responsiblePrinting: '', coverDesign: '',
    phone: '', address: '', postalCode: '', printingHouse: '',
    impression: '', format: '', printedSheets: '', wordCount: '', price: '',
  };
  const [newBook, setNewBook] = useState({ ...emptyBook });
  const [editBook, setEditBook] = useState({ ...emptyBook });

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
    if (!newBook.title.trim()) return;
    try {
      const payload = { libraryId: parseInt(id), verifyStatus: 'manual' };
      for (const [k, v] of Object.entries(newBook)) {
        if (v.trim()) payload[k] = v.trim();
      }
      await books.create(payload);
      setShowAddBook(false);
      setNewBook({ ...emptyBook });
      loadBooks();
    } catch (err) {
      alert(err.error || '添加失败');
    }
  };

  const handleEditBookClick = async (book) => {
    try {
      const detail = await books.get(book.id);
      setEditBook({
        title: detail.title || '',
        author: detail.author || '',
        adaptation: detail.adaptation || '',
        translator: detail.translator || '',
        authorNationality: detail.authorNationality || '',
        isbn: detail.isbn || '',
        publisher: detail.publisher || '',
        edition: detail.edition || '',
        publisherPerson: detail.publisherPerson || '',
        responsibleEditor: detail.responsibleEditor || '',
        responsiblePrinting: detail.responsiblePrinting || '',
        coverDesign: detail.coverDesign || '',
        phone: detail.phone || '',
        address: detail.address || '',
        postalCode: detail.postalCode || '',
        printingHouse: detail.printingHouse || '',
        impression: detail.impression || '',
        format: detail.format || '',
        printedSheets: detail.printedSheets || '',
        wordCount: detail.wordCount || '',
        price: detail.price || '',
      });
      setShowEditBook(book.id);
    } catch (err) {
      alert(err.error || '加载书籍详情失败');
    }
  };

  const handleSaveEdit = async (e) => {
    e.preventDefault();
    if (!editBook.title.trim()) return;
    try {
      const payload = {};
      for (const [k, v] of Object.entries(editBook)) {
        if (v.trim()) payload[k] = v.trim();
        else payload[k] = null;
      }
      await books.update(showEditBook, payload);
      setShowEditBook(null);
      loadBooks();
    } catch (err) {
      alert(err.error || '保存失败');
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
              <form className="book-form" onSubmit={handleAddBook}>
                <div className="book-form-sections">
                  <div className="form-section">
                    <h4>基本信息</h4>
                    <input type="text" placeholder="书名（必填）" value={newBook.title} onChange={(e) => setNewBook({...newBook, title: e.target.value})} required />
                    <input type="text" placeholder="作者" value={newBook.author} onChange={(e) => setNewBook({...newBook, author: e.target.value})} />
                    <input type="text" placeholder="改编" value={newBook.adaptation} onChange={(e) => setNewBook({...newBook, adaptation: e.target.value})} />
                    <input type="text" placeholder="译者" value={newBook.translator} onChange={(e) => setNewBook({...newBook, translator: e.target.value})} />
                    <input type="text" placeholder="作者国籍" value={newBook.authorNationality} onChange={(e) => setNewBook({...newBook, authorNationality: e.target.value})} />
                    <input type="text" placeholder="ISBN" value={newBook.isbn} onChange={(e) => setNewBook({...newBook, isbn: e.target.value})} />
                    <input type="text" placeholder="出版社" value={newBook.publisher} onChange={(e) => setNewBook({...newBook, publisher: e.target.value})} />
                    <input type="text" placeholder="版次（如 2023年5月第1版）" value={newBook.edition} onChange={(e) => setNewBook({...newBook, edition: e.target.value})} />
                    <input type="text" placeholder="出版人" value={newBook.publisherPerson} onChange={(e) => setNewBook({...newBook, publisherPerson: e.target.value})} />
                    <input type="text" placeholder="责任编辑" value={newBook.responsibleEditor} onChange={(e) => setNewBook({...newBook, responsibleEditor: e.target.value})} />
                    <input type="text" placeholder="责任印制" value={newBook.responsiblePrinting} onChange={(e) => setNewBook({...newBook, responsiblePrinting: e.target.value})} />
                    <input type="text" placeholder="封面设计" value={newBook.coverDesign} onChange={(e) => setNewBook({...newBook, coverDesign: e.target.value})} />
                    <input type="text" placeholder="定价（元）" value={newBook.price} onChange={(e) => setNewBook({...newBook, price: e.target.value})} />
                  </div>
                  <div className="form-section">
                    <h4>出版信息</h4>
                    <input type="text" placeholder="印刷厂" value={newBook.printingHouse} onChange={(e) => setNewBook({...newBook, printingHouse: e.target.value})} />
                    <input type="text" placeholder="印次（如 2023年5月第2次印刷）" value={newBook.impression} onChange={(e) => setNewBook({...newBook, impression: e.target.value})} />
                    <input type="text" placeholder="开本（如 32开）" value={newBook.format} onChange={(e) => setNewBook({...newBook, format: e.target.value})} />
                    <input type="text" placeholder="印张" value={newBook.printedSheets} onChange={(e) => setNewBook({...newBook, printedSheets: e.target.value})} />
                    <input type="text" placeholder="字数（如 200千字）" value={newBook.wordCount} onChange={(e) => setNewBook({...newBook, wordCount: e.target.value})} />
                  </div>
                  <div className="form-section">
                    <h4>联系方式</h4>
                    <input type="text" placeholder="电话" value={newBook.phone} onChange={(e) => setNewBook({...newBook, phone: e.target.value})} />
                    <input type="text" placeholder="地址" value={newBook.address} onChange={(e) => setNewBook({...newBook, address: e.target.value})} />
                    <input type="text" placeholder="邮编" value={newBook.postalCode} onChange={(e) => setNewBook({...newBook, postalCode: e.target.value})} />
                  </div>
                </div>
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
                    <div className="book-actions">
                      {canManage && (
                        <button onClick={() => handleEditBookClick(book)} className="btn-secondary-small">编辑</button>
                      )}
                      {canManage && (
                        <button onClick={() => handleDeleteBook(book.id)} className="btn-danger-small">删除</button>
                      )}
                    </div>
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

      {showEditBook && (
        <div className="modal" onClick={() => setShowEditBook(null)}>
          <div className="modal-content modal-wide" onClick={(e) => e.stopPropagation()}>
            <h2>编辑书籍</h2>
            <form className="book-form" onSubmit={handleSaveEdit}>
              <div className="book-form-sections">
                <div className="form-section">
                  <h4>基本信息</h4>
                  <input type="text" placeholder="书名（必填）" value={editBook.title} onChange={(e) => setEditBook({...editBook, title: e.target.value})} required />
                  <input type="text" placeholder="作者" value={editBook.author} onChange={(e) => setEditBook({...editBook, author: e.target.value})} />
                  <input type="text" placeholder="改编" value={editBook.adaptation} onChange={(e) => setEditBook({...editBook, adaptation: e.target.value})} />
                  <input type="text" placeholder="译者" value={editBook.translator} onChange={(e) => setEditBook({...editBook, translator: e.target.value})} />
                  <input type="text" placeholder="作者国籍" value={editBook.authorNationality} onChange={(e) => setEditBook({...editBook, authorNationality: e.target.value})} />
                  <input type="text" placeholder="ISBN" value={editBook.isbn} onChange={(e) => setEditBook({...editBook, isbn: e.target.value})} />
                  <input type="text" placeholder="出版社" value={editBook.publisher} onChange={(e) => setEditBook({...editBook, publisher: e.target.value})} />
                  <input type="text" placeholder="版次（如 2023年5月第1版）" value={editBook.edition} onChange={(e) => setEditBook({...editBook, edition: e.target.value})} />
                  <input type="text" placeholder="出版人" value={editBook.publisherPerson} onChange={(e) => setEditBook({...editBook, publisherPerson: e.target.value})} />
                  <input type="text" placeholder="责任编辑" value={editBook.responsibleEditor} onChange={(e) => setEditBook({...editBook, responsibleEditor: e.target.value})} />
                  <input type="text" placeholder="责任印制" value={editBook.responsiblePrinting} onChange={(e) => setEditBook({...editBook, responsiblePrinting: e.target.value})} />
                  <input type="text" placeholder="封面设计" value={editBook.coverDesign} onChange={(e) => setEditBook({...editBook, coverDesign: e.target.value})} />
                  <input type="text" placeholder="定价（元）" value={editBook.price} onChange={(e) => setEditBook({...editBook, price: e.target.value})} />
                </div>
                <div className="form-section">
                  <h4>出版信息</h4>
                  <input type="text" placeholder="印刷厂" value={editBook.printingHouse} onChange={(e) => setEditBook({...editBook, printingHouse: e.target.value})} />
                  <input type="text" placeholder="印次（如 2023年5月第2次印刷）" value={editBook.impression} onChange={(e) => setEditBook({...editBook, impression: e.target.value})} />
                  <input type="text" placeholder="开本（如 32开）" value={editBook.format} onChange={(e) => setEditBook({...editBook, format: e.target.value})} />
                  <input type="text" placeholder="印张" value={editBook.printedSheets} onChange={(e) => setEditBook({...editBook, printedSheets: e.target.value})} />
                  <input type="text" placeholder="字数（如 200千字）" value={editBook.wordCount} onChange={(e) => setEditBook({...editBook, wordCount: e.target.value})} />
                </div>
                <div className="form-section">
                  <h4>联系方式</h4>
                  <input type="text" placeholder="电话" value={editBook.phone} onChange={(e) => setEditBook({...editBook, phone: e.target.value})} />
                  <input type="text" placeholder="地址" value={editBook.address} onChange={(e) => setEditBook({...editBook, address: e.target.value})} />
                  <input type="text" placeholder="邮编" value={editBook.postalCode} onChange={(e) => setEditBook({...editBook, postalCode: e.target.value})} />
                </div>
              </div>
              <div className="modal-actions">
                <button type="button" onClick={() => setShowEditBook(null)} className="btn-secondary">取消</button>
                <button type="submit" className="btn-primary">保存</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
