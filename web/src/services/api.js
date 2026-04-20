import axios from 'axios';

const api = axios.create({
  baseURL: '/api',
  timeout: 30000
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response.data,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('token');
      localStorage.removeItem('user');
      window.location.href = '/login';
    }
    return Promise.reject(error.response?.data || error);
  }
);

export const auth = {
  register: (data) => api.post('/auth/register', data),
  login: (data) => api.post('/auth/login', data),
  getMe: () => api.get('/auth/me'),
  updateMe: (data) => api.patch('/auth/me', data),
  changePassword: (data) => api.post('/auth/change-password', data)
};

export const libraries = {
  list: () => api.get('/libraries'),
  get: (id) => api.get(`/libraries/${id}`),
  create: (data) => api.post('/libraries', data),
  update: (id, data) => api.put(`/libraries/${id}`, data),
  delete: (id) => api.delete(`/libraries/${id}`)
};

export const members = {
  list: (libraryId) => api.get(`/library-members/${libraryId}/members`),
  add: (libraryId, data) => api.post(`/library-members/${libraryId}/members`, data),
  updateRole: (libraryId, userId, data) => api.patch(`/library-members/${libraryId}/members/${userId}`, data),
  remove: (libraryId, userId) => api.delete(`/library-members/${libraryId}/members/${userId}`),
  transfer: (libraryId, data) => api.post(`/library-members/${libraryId}/transfer`, data),
  leave: (libraryId) => api.post(`/library-members/${libraryId}/leave`)
};

export const books = {
  list: (params) => api.get('/books', { params }),
  get: (id) => api.get(`/books/${id}`),
  create: (data) => api.post('/books', data),
  update: (id, data) => api.put(`/books/${id}`, data),
  delete: (id) => api.delete(`/books/${id}`),
  move: (id, data) => api.post(`/books/${id}/move`, data),
  batchImport: (data) => api.post('/books/batch-import', data),
  export: (params) => api.get('/books/export', { params, responseType: 'blob' })
};

export const sunReminders = {
  list: () => api.get('/sun-reminders'),
  createForLibrary: (libraryId, data) => api.post(`/sun-reminders/library/${libraryId}`, data),
  createForBox: (boxId, data) => api.post(`/sun-reminders/box/${boxId}`, data),
  update: (id, data) => api.patch(`/sun-reminders/${id}`, data),
  markSunned: (id) => api.post(`/sun-reminders/${id}/mark-sunned`),
  delete: (id) => api.delete(`/sun-reminders/${id}`)
};

export default api;
