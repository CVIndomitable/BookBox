import { Component } from 'react';

export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error('[ErrorBoundary]', error, info);
  }

  handleReload = () => {
    this.setState({ error: null });
    window.location.reload();
  };

  render() {
    if (this.state.error) {
      return (
        <div style={{
          minHeight: '100vh', display: 'flex', flexDirection: 'column',
          justifyContent: 'center', alignItems: 'center', padding: 24, gap: 16,
        }}>
          <h2>页面出错了</h2>
          <p style={{ color: '#666', maxWidth: 480, textAlign: 'center' }}>
            {String(this.state.error?.message || this.state.error)}
          </p>
          <button onClick={this.handleReload} style={{
            padding: '8px 16px', borderRadius: 4, border: 'none',
            background: '#3498db', color: '#fff', cursor: 'pointer',
          }}>
            重新加载
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
