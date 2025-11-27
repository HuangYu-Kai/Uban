import React, { useState } from 'react';
import './App.css';

function App() {
  const [message, setMessage] = useState('');

  const handleClick = async () => {
    try {
      const response = await fetch('/api/message');
      const text = await response.text();
      setMessage(text);
    } catch (error) {
      console.error('Error fetching data:', error);
      setMessage('Error fetching data from the backend.');
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <p>{message || 'Click the button to fetch data from the backend'}</p>
        <button onClick={handleClick}>Fetch Backend Data</button>
      </header>
    </div>
  );
}

export default App;
