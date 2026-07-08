import { useState } from 'react';
import { LoginPage } from './pages/LoginPage';
import { HomePage } from './pages/HomePage';
import { CategoriesPage } from './pages/CategoriesPage';
import { ChannelsPage } from './pages/ChannelsPage';
import { PlayerPage } from './pages/PlayerPage';
import './styles.css';

const ROUTES = {
  login: 'login',
  home: 'home',
  categories: 'categories',
  channels: 'channels',
  player: 'player',
};

function App() {
  const [route, setRoute] = useState(ROUTES.login);
  const [session, setSession] = useState(null);
  const [selectedCategory, setSelectedCategory] = useState(null);
  const [selectedChannel, setSelectedChannel] = useState(null);

  function handleLoginSuccess(sessionData) {
    setSession(sessionData);
    setRoute(ROUTES.home);
  }

  function handleLogout() {
    setSession(null);
    setSelectedCategory(null);
    setSelectedChannel(null);
    setRoute(ROUTES.login);
  }

  function handleSelectCategory(category) {
    setSelectedCategory(category);
    setSelectedChannel(null);
    setRoute(ROUTES.channels);
  }

  function handleSelectChannel(channel) {
    setSelectedChannel(channel);
    setRoute(ROUTES.player);
  }

  if (route === ROUTES.player && session && selectedChannel) {
    return (
      <PlayerPage
        session={session}
        channel={selectedChannel}
        onBack={() => setRoute(ROUTES.channels)}
      />
    );
  }

  if (route === ROUTES.channels && session && selectedCategory) {
    return (
      <ChannelsPage
        session={session}
        category={selectedCategory}
        onBack={() => setRoute(ROUTES.categories)}
        onSelectChannel={handleSelectChannel}
      />
    );
  }

  if (route === ROUTES.categories && session) {
    return (
      <CategoriesPage
        session={session}
        onBack={() => setRoute(ROUTES.home)}
        onSelectCategory={handleSelectCategory}
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