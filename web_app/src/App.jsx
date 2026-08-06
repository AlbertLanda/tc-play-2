import { useEffect, useState } from 'react';
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
  const [playerReturnRoute, setPlayerReturnRoute] = useState(ROUTES.home);
  
  function navigateTo(nextRoute) {
    window.history.pushState({ route: nextRoute }, '');
    setRoute(nextRoute);
  }

  function handleLoginSuccess(sessionData) {
    setSession(sessionData);
    navigateTo(ROUTES.home);
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
    navigateTo(ROUTES.channels);
  }

  function handleSelectChannel(channel) {
    setSelectedChannel(channel);
    setPlayerReturnRoute(ROUTES.channels);
    navigateTo(ROUTES.player);
  }

  function handleSelectAstraChannel(channel, channelList = astraChannels) {
  const index = channelList.findIndex(
    (item) => item.id === channel.id,
  );

  setAstraChannels(channelList);
  setSelectedChannelIndex(index >= 0 ? index : 0);

  setSelectedChannel({
    ...channel,
    isAstra: true,
    stream_url: channel.url,
  });

  setPlayerReturnRoute(ROUTES.astraChannels);
  navigateTo(ROUTES.player);
}

  function handleSelectChannelFromHome(channel, channelList = []) {
    const list = channelList.length ? channelList : astraChannels;
    const nextIndex = list.findIndex((item) => item.id === channel.id);

    setAstraChannels(list);
    setSelectedChannelIndex(nextIndex >= 0 ? nextIndex : 0);
    setSelectedChannel({
      ...channel,
      isAstra: true,
      stream_url: channel.url,
    });

    setPlayerReturnRoute(ROUTES.home);
    navigateTo(ROUTES.player);
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

      setAstraChannels(channels);
      setSelectedChannelIndex(0);
      setSelectedChannel(null);
      navigateTo(ROUTES.astraChannels);
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
    console.log(
      "Canal actual:",
      selectedChannel?.name,
      "Índice:",
      selectedChannelIndex,
      "Total:",
      astraChannels.length,
    );

    handleSelectAstraChannelByIndex(selectedChannelIndex + 1);
  }

  function handlePreviousAstraChannel() {
    if (!selectedChannel || !astraChannels.length) return;

    const currentIndex = astraChannels.findIndex(
      (item) => item.id === selectedChannel.id,
    );

    handleSelectAstraChannelByIndex(currentIndex - 1);
  }

  useEffect(() => {
    window.history.replaceState({ route }, '');

    function handlePopState(event) {
      const previousRoute = event.state?.route;

      if (previousRoute) {
        setRoute(previousRoute);
      }
    }

    window.addEventListener('popstate', handlePopState);

    return () => {
      window.removeEventListener('popstate', handlePopState);
    };
  }, []);

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
        onBack={() => setRoute(playerReturnRoute)}
      />
    );
  }

  if (route === ROUTES.astraChannels && session) {
    return (
      <AstraChannelsPage
        channels={astraChannels}
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
        onSelectChannel={handleSelectChannelFromHome}
        isOpeningLiveTv={isOpeningLiveTv}
        homeErrorMessage={homeErrorMessage}
      />
    );
  }

  return <LoginPage onLoginSuccess={handleLoginSuccess} />;
}

export default App;