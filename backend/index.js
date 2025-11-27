const express = require('express');
const cors = require('cors');
const engine = require('./engine');

const app = express();
const port = 3001;

app.use(cors());
app.use(express.json());

app.post('/api/execute', (req, res) => {
  const { nodes, edges } = req.body;
  console.log('Received flow data:');
  
  // Pass the flow data to the engine
  engine.execute(nodes, edges);

  res.status(200).json({ message: 'Flow received successfully' });
});

app.listen(port, () => {
  console.log(`Backend server listening at http://localhost:${port}`);
});
