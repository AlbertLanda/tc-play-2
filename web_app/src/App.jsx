import { useState } from 'react';
import { LoginPage } from './pages/LoginPage';
import { HomePage } from './pages/HomePage';
import { CategoriesPage } from './pages/CategoriesPage';
import './styles.css';

const ROUTES = {
  login: 'login',
  home: 'home',
  categories: 'categories',
};

function App() {
  const [route, setRoute] = useState(ROUTES.login);
  const [session, setSession] = useState(null);

  function handleLoginSuccess(sessionData) {
    setSession(sessionData);
    setRoute(ROUTES.home);
  }

  function handleLogout() {
    setSession(null);
    setRoute(ROUTES.login);
  }

  if (route === ROUTES.categories && session) {
    return (
      <CategoriesPage
        session={session}
        onBack={() => setRoute(ROUTES.home)}
      />
    );
  }

  if (route === ROUTES.home && session) {
    return (
      <HomePage
        session={session}
        onLogout={handleLogout}
        onGoToCategories={() => setRoute(ROUTES.categories)}
      />
    );
  }

  return <LoginPage onLoginSuccess={handleLoginSuccess} />;
}

export default App;