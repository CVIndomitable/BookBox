// PM2 配置：生产(main)/开发(dev) 两个进程
// 用法：
//   pm2 start ecosystem.config.cjs --only bookbox-main   # 生产
//   pm2 start ecosystem.config.cjs --only bookbox-dev    # 开发
//   pm2 save && pm2 startup                               # 开机自启
//
// 日志轮转：需要一次性装 pm2-logrotate 模块（全局）：
//   pm2 install pm2-logrotate
//   pm2 set pm2-logrotate:max_size 20M
//   pm2 set pm2-logrotate:retain 14
//   pm2 set pm2-logrotate:compress true
//   pm2 set pm2-logrotate:rotateInterval '0 0 * * *'

const sharedEnv = {
  DOUBAN_REQUEST_INTERVAL: 3000,
  SEARCH_CACHE_TTL: 604800,
};

module.exports = {
  apps: [
    {
      name: 'bookbox-main',
      cwd: '/home/bookbox-main',
      script: 'src/index.js',
      instances: 1,
      exec_mode: 'fork',
      // 进程挂掉自动拉起；内存超过 500M 重启（防泄漏兜底）
      autorestart: true,
      max_memory_restart: '500M',
      // 启动后 30s 内挂掉不重试，避免无限 crash-loop
      min_uptime: '30s',
      max_restarts: 10,
      // 优雅停止：给 SIGINT 处理 10s
      kill_timeout: 10000,
      wait_ready: false,
      out_file: '/var/log/pm2/bookbox-main.out.log',
      error_file: '/var/log/pm2/bookbox-main.err.log',
      merge_logs: true,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      env: {
        ...sharedEnv,
        NODE_ENV: 'production',
        PORT: 3001,
      },
    },
    {
      name: 'bookbox-dev',
      cwd: '/home/bookbox-dev',
      script: 'src/index.js',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_memory_restart: '500M',
      min_uptime: '30s',
      max_restarts: 10,
      kill_timeout: 10000,
      out_file: '/var/log/pm2/bookbox-dev.out.log',
      error_file: '/var/log/pm2/bookbox-dev.err.log',
      merge_logs: true,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      env: {
        ...sharedEnv,
        NODE_ENV: 'development',
        PORT: 3002,
      },
    },
  ],
};
