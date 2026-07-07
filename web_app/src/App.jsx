import { useState } from 'react';
import { LoginPage } from './pages/LoginPage';
import { HomePage } from './pages/HomePage';
import './styles.css';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  if (isAuthenticated) {
    return <HomePage onLogout={() => setIsAuthenticated(false)} />;
  }

  return <LoginPage onLoginSuccess={() => setIsAuthenticated(true)} />;
}

export default App;