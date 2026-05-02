import { createContext, useContext, useState, useEffect } from 'react';
import { auth } from '../services/api';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const token = localStorage.getItem('token');
    const savedUser = localStorage.getItem('user');

    // localStorage 可能被破坏（跨站脚本污染、调试工具改错等）：保险 try-catch
    let parsed = null;
    if (savedUser) {
      try {
        parsed = JSON.parse(savedUser);
      } catch {
        parsed = null;
      }
    }

    if (token && parsed) {
      setUser(parsed);
      auth.getMe()
        .then(({ user }) => {
          setUser(user);
          localStorage.setItem('user', JSON.stringify(user));
        })
        .catch(() => {
          localStorage.removeItem('token');
          localStorage.removeItem('user');
          setUser(null);
        })
        .finally(() => setLoading(false));
    } else {
      // 清理可能的半损坏状态
      if (!parsed && savedUser) localStorage.removeItem('user');
      setLoading(false);
    }
  }, []);

  const login = async (credentials) => {
    const { user, token } = await auth.login(credentials);
    localStorage.setItem('token', token);
    localStorage.setItem('user', JSON.stringify(user));
    setUser(user);
  };

  const register = async (data) => {
    const { user, token } = await auth.register(data);
    localStorage.setItem('token', token);
    localStorage.setItem('user', JSON.stringify(user));
    setUser(user);
  };

  const logout = () => {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    setUser(null);
  };

  return (
    <AuthContext.Provider value={{ user, loading, login, register, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}
