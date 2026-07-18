import { useState } from 'react';
import { LoginPage } from './pages/LoginPage';
import { HomePage } from './pages/HomePage';
import { CategoriesPage } from './pages/CategoriesPage';
import { ChannelsPage } from './pages/ChannelsPage';
import { PlayerPage } from './pages/PlayerPage';
import { AstraChannelsPage } from './pages/AstraChannelsPage';
import { getAstraChannels } from './api/astraApi';
import './styles.css';

const ROUTES = {
  login: 'login',
  home: 'home',
  categories: 'categories',
  channels: 'channels',
  player: 'player',
  astraChannels: 'astraChannels',
};

function App() {
  const [route, setRoute] = useState(ROUTES.login);
  const [session, setSession] = useState(null);
  const [selectedCategory, setSelectedCategory] = useState(null);
  const [selectedChannel, setSelectedChannel] = useState(null);

  const [astraChannels, setAstraChannels] = useState([]);
  const [selectedChannelIndex, setSelectedChannelIndex] = useState(0);
  const [homeErrorMessage, setHomeErrorMessage] = useState('');
  const [isOpeningLiveTv, setIsOpeningLiveTv] = useState(false);

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

  function handleSelectAstraChannel(channel) {
    setSelectedChannel({
      ...channel,
      isAstra: true,
      stream_url: channel.url,
    });

    setRoute(ROUTES.player);
  }

  async function handleOpenLiveTv() {
    try {
      setIsOpeningLiveTv(true);
      setHomeErrorMessage('');

      const channels = await getAstraChannels();

      if (!channels.length) {
        setHomeErrorMessage('No se encontraron canales disponibles.');
        return;
      }

      const randomIndex = Math.floor(Math.random() * channels.length);
      const randomChannel = channels[randomIndex];

      setAstraChannels(channels);
      setSelectedChannelIndex(randomIndex);
      setSelectedChannel({
        ...randomChannel,
        isAstra: true,
        stream_url: randomChannel.url,
      });

      setRoute(ROUTES.player);
    } catch (error) {
      setHomeErrorMessage(
        error.message || 'No se pudo abrir TV en vivo. Intenta nuevamente.',
      );
    } finally {
      setIsOpeningLiveTv(false);
    }
  }

  function handleSelectAstraChannelByIndex(nextIndex) {
    if (!astraChannels.length) {
      return;
    }

    const normalizedIndex =
      (nextIndex + astraChannels.length) % astraChannels.length;

    const nextChannel = astraChannels[normalizedIndex];

    setSelectedChannelIndex(normalizedIndex);
    setSelectedChannel({
      ...nextChannel,
      isAstra: true,
      stream_url: nextChannel.url,
    });
  }

  function handleNextAstraChannel() {
    handleSelectAstraChannelByIndex(selectedChannelIndex + 1);
  }

  function handlePreviousAstraChannel() {
    handleSelectAstraChannelByIndex(selectedChannelIndex - 1);
  }

  if (route === ROUTES.player && session && selectedChannel) {
    return (
      <PlayerPage
        session={session}
        channel={selectedChannel}
        channels={astraChannels}
        currentChannelIndex={selectedChannelIndex}
        onPreviousChannel={
          selectedChannel?.isAstra ? handlePreviousAstraChannel : undefined
        }
        onNextChannel={
          selectedChannel?.isAstra ? handleNextAstraChannel : undefined
        }
        onBack={() => setRoute(ROUTES.home)}
      />
    );
  }

  if (route === ROUTES.astraChannels && session) {
    return (
      <AstraChannelsPage
        onBack={() => setRoute(ROUTES.home)}
        onSelectChannel={handleSelectAstraChannel}
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
        onGoToAstra={handleOpenLiveTv}
        isOpeningLiveTv={isOpeningLiveTv}
        homeErrorMessage={homeErrorMessage}
      />
    );
  }

  return <LoginPage onLoginSuccess={handleLoginSuccess} />;
}

export default App;