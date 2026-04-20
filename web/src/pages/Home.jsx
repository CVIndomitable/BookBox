import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { libraries } from '../services/api';
import { useAuth } from '../hooks/useAuth';
import './Home.css';

export default function Home() {
  const [libraryList, setLibraryList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [newLibrary, setNewLibrary] = useState({ name: '', location: '', description: '' });
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    loadLibraries();
  }, []);

  const loadLibraries = async () => {
    try {
      const data = await libraries.list();
      setLibraryList(data);
    } catch (err) {
      console.error('加载书库失败:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleCreate = async (e) => {
    e.preventDefault();
    try {
      await libraries.create(newLibrary);
      setShowCreate(false);
      setNewLibrary({ name: '', location: '', description: '' });
      loadLibraries();
    } catch (err) {
      alert(err.error || '创建失败');
    }
  };

  if (loading) {
    return <div className="loading">加载中...</div>;
  }

  return (
    <div className="home">
      <header className="header">
        <h1>BookBox</h1>
        <div className="user-info">
          <span>{user.displayName || user.username}</span>
          <button onClick={logout} className="btn-secondary">退出</button>
        </div>
      </header>

      <main className="main">
        <div className="toolbar">
          <h2>我的书库</h2>
          <button onClick={() => setShowCreate(true)} className="btn-primary">
            + 新建书库
          </button>
        </div>

        {libraryList.length === 0 ? (
          <div className="empty">
            <p>还没有书库，创建一个开始管理你的藏书吧</p>
          </div>
        ) : (
          <div className="library-grid">
            {libraryList.map((lib) => (
              <div
                key={lib.id}
                className="library-card"
                onClick={() => navigate(`/library/${lib.id}`)}
              >
                <h3>{lib.name}</h3>
                {lib.location && <p className="location">{lib.location}</p>}
                <div className="stats">
                  <span>{lib.bookCount} 本书</span>
                  <span className="role">{lib.role === 'owner' ? '所有者' : lib.role === 'admin' ? '管理员' : '成员'}</span>
                </div>
              </div>
            ))}
          </div>
        )}
      </main>

      {showCreate && (
        <div className="modal" onClick={() => setShowCreate(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <h2>新建书库</h2>
            <form onSubmit={handleCreate}>
              <div className="form-group">
                <label>书库名称</label>
                <input
                  type="text"
                  value={newLibrary.name}
                  onChange={(e) => setNewLibrary({ ...newLibrary, name: e.target.value })}
                  required
                  autoFocus
                />
              </div>
              <div className="form-group">
                <label>位置（可选）</label>
                <input
                  type="text"
                  value={newLibrary.location}
                  onChange={(e) => setNewLibrary({ ...newLibrary, location: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label>描述（可选）</label>
                <textarea
                  value={newLibrary.description}
                  onChange={(e) => setNewLibrary({ ...newLibrary, description: e.target.value })}
                  rows="3"
                />
              </div>
              <div className="modal-actions">
                <button type="button" onClick={() => setShowCreate(false)} className="btn-secondary">
                  取消
                </button>
                <button type="submit" className="btn-primary">创建</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
