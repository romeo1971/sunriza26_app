module.exports = {
  apps: [
    {
      name: 'lipsync-orchestrator',
      script: 'dist/lipsync_handler.js',
      cwd: __dirname,
      env: {
        NODE_ENV: 'production',
      },
      env_production: {
        NODE_ENV: 'production',
      },
      watch: false,
      autorestart: true,
      max_memory_restart: '300M',
    },
  ],
};



