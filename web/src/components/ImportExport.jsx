import { useState } from 'react';
import { books } from '../services/api';
import './ImportExport.css';

export default function ImportExport({ libraryId, onImportComplete }) {
  const [importing, setImporting] = useState(false);
  const [exporting, setExporting] = useState(false);

  const handleExport = async () => {
    setExporting(true);
    try {
      const blob = await books.export({ libraryId });
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `books-${libraryId}-${Date.now()}.csv`;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);
    } catch (err) {
      alert(err.error || '导出失败');
    } finally {
      setExporting(false);
    }
  };

  const handleImport = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    setImporting(true);
    try {
      const text = await file.text();
      const lines = text.split('\n').filter(line => line.trim());

      if (lines.length < 2) {
        alert('文件格式错误：至少需要标题行和一行数据');
        return;
      }

      const headers = lines[0].split(',').map(h => h.trim());
      const titleIndex = headers.findIndex(h => h === '书名' || h === 'title');
      const authorIndex = headers.findIndex(h => h === '作者' || h === 'author');
      const isbnIndex = headers.findIndex(h => h === 'ISBN' || h === 'isbn');
      const publisherIndex = headers.findIndex(h => h === '出版社' || h === 'publisher');

      if (titleIndex === -1) {
        alert('文件格式错误：缺少"书名"列');
        return;
      }

      const booksData = [];
      for (let i = 1; i < lines.length; i++) {
        const values = lines[i].split(',').map(v => v.trim());
        if (values.length < headers.length) continue;

        const bookData = {
          title: values[titleIndex],
          libraryId: parseInt(libraryId),
          verifyStatus: 'manual'
        };

        if (authorIndex !== -1 && values[authorIndex]) {
          bookData.author = values[authorIndex];
        }
        if (isbnIndex !== -1 && values[isbnIndex]) {
          bookData.isbn = values[isbnIndex];
        }
        if (publisherIndex !== -1 && values[publisherIndex]) {
          bookData.publisher = values[publisherIndex];
        }

        booksData.push(bookData);
      }

      if (booksData.length === 0) {
        alert('没有有效的书籍数据');
        return;
      }

      await books.batchImport({ books: booksData });
      alert(`成功导入 ${booksData.length} 本书`);
      if (onImportComplete) onImportComplete();
    } catch (err) {
      alert(err.error || '导入失败');
    } finally {
      setImporting(false);
      e.target.value = '';
    }
  };

  const downloadTemplate = () => {
    const template = '书名,作者,ISBN,出版社\n示例书籍,示例作者,9787111111111,示例出版社';
    const blob = new Blob([template], { type: 'text/csv;charset=utf-8;' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'books-template.csv';
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(url);
    document.body.removeChild(a);
  };

  return (
    <div className="import-export">
      <div className="action-group">
        <h3>导出书籍</h3>
        <p>将当前书库的所有书籍导出为 CSV 文件</p>
        <button onClick={handleExport} disabled={exporting} className="btn-primary">
          {exporting ? '导出中...' : '导出 CSV'}
        </button>
      </div>

      <div className="action-group">
        <h3>导入书籍</h3>
        <p>从 CSV 文件批量导入书籍（支持：书名、作者、ISBN、出版社）</p>
        <div className="import-actions">
          <button onClick={downloadTemplate} className="btn-secondary">
            下载模板
          </button>
          <label className="btn-primary">
            {importing ? '导入中...' : '选择文件'}
            <input
              type="file"
              accept=".csv"
              onChange={handleImport}
              disabled={importing}
              style={{ display: 'none' }}
            />
          </label>
        </div>
      </div>
    </div>
  );
}
