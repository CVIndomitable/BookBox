import { useState, useEffect } from 'react';
import { sunReminders } from '../services/api';
import { useAuth } from '../hooks/useAuth';
import './SunReminders.css';

export default function SunReminders() {
  const [reminders, setReminders] = useState([]);
  const [loading, setLoading] = useState(true);
  const { user } = useAuth();

  useEffect(() => {
    loadReminders();
  }, []);

  const loadReminders = async () => {
    try {
      const data = await sunReminders.list();
      setReminders(data.reminders || []);
    } catch (err) {
      console.error('加载提醒失败:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleMarkSunned = async (id) => {
    try {
      await sunReminders.markSunned(id);
      loadReminders();
    } catch (err) {
      alert(err.error || '操作失败');
    }
  };

  const handleDelete = async (id) => {
    if (!confirm('确定删除此提醒？')) return;
    try {
      await sunReminders.delete(id);
      loadReminders();
    } catch (err) {
      alert(err.error || '删除失败');
    }
  };

  const formatDate = (dateStr) => {
    const date = new Date(dateStr);
    return date.toLocaleDateString('zh-CN', { year: 'numeric', month: 'long', day: 'numeric' });
  };

  const getDaysUntil = (dateStr) => {
    const now = new Date();
    const target = new Date(dateStr);
    const days = Math.ceil((target - now) / (1000 * 60 * 60 * 24));
    return days;
  };

  if (loading) {
    return <div className="loading">加载中...</div>;
  }

  return (
    <div className="sun-reminders">
      <header className="reminders-header">
        <h1>晒书提醒</h1>
        <p className="subtitle">定期晒书，防止书籍受潮发霉</p>
      </header>

      <div className="reminders-content">
        <div className="settings-card">
          <h2>全局设置</h2>
          <p>默认晒书间隔：{user.defaultSunDays} 天</p>
          <button className="btn-secondary">修改</button>
        </div>

        <div className="reminders-list">
          <h2>我的提醒</h2>
          {reminders.length === 0 ? (
            <div className="empty">暂无提醒，可在书库或箱子页面创建</div>
          ) : (
            <div className="reminder-items">
              {reminders.map((reminder) => {
                const daysUntil = getDaysUntil(reminder.nextSunAt);
                const isOverdue = daysUntil < 0;
                const isUrgent = daysUntil >= 0 && daysUntil <= 7;

                return (
                  <div
                    key={reminder.id}
                    className={`reminder-item ${isOverdue ? 'overdue' : isUrgent ? 'urgent' : ''}`}
                  >
                    <div className="reminder-info">
                      <h3>{reminder.targetName}</h3>
                      <p className="target-type">
                        {reminder.targetType === 'library' ? '书库' : '箱子'}
                      </p>
                      <p className="next-sun">
                        {isOverdue ? (
                          <span className="overdue-text">已逾期 {Math.abs(daysUntil)} 天</span>
                        ) : daysUntil === 0 ? (
                          <span className="urgent-text">今天需要晒书</span>
                        ) : (
                          <span>还有 {daysUntil} 天 · {formatDate(reminder.nextSunAt)}</span>
                        )}
                      </p>
                      {reminder.lastSunAt && (
                        <p className="last-sun">上次晒书：{formatDate(reminder.lastSunAt)}</p>
                      )}
                    </div>
                    <div className="reminder-actions">
                      <button
                        onClick={() => handleMarkSunned(reminder.id)}
                        className="btn-primary-small"
                      >
                        已晒书
                      </button>
                      <button
                        onClick={() => handleDelete(reminder.id)}
                        className="btn-danger-small"
                      >
                        删除
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
