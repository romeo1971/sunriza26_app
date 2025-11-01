import express from 'express';

const app = express();
app.use(express.json());

// CORS
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }
  next();
});

// MINIMAL TEST - nur Echo
app.post('/', async (req, res) => {
  console.log('Request received:', req.body);
  console.log('Memory usage:', process.memoryUsage());
  
  res.status(200).json({
    message: 'Memory API V3 - MINIMAL TEST',
    received: req.body,
    memory: process.memoryUsage(),
  });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Memory API listening on port ${PORT}`);
  console.log('Initial memory:', process.memoryUsage());
});
