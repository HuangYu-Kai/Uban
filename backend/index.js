const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/api/message', (req, res) => {
  res.send('Hello from the backend!');
});

app.listen(port, () => {
  console.log(`Backend server listening at http://localhost:${port}`);
});