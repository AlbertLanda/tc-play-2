(function (root) {
  'use strict';
  root.TCPlayPlatform = {
    label: 'LG · webOS',
    init: function () {},
    keyAction: function (code) {
      return { 461: 'back', 427: 'next', 428: 'previous' }[code] || null;
    },
    exit: function () { root.close(); },
    createPlayer: function (video) {
      var handlers = null, listeners = [], generation = 0;
      function stop() {
        generation += 1;
        handlers = null;
        listeners.forEach(function (entry) { video.removeEventListener(entry[0], entry[1]); });
        listeners = [];
        video.pause(); video.removeAttribute('src'); video.load();
      }
      function listen(name, callback) { listeners.push([name, callback]); video.addEventListener(name, callback); }
      return {
        play: function (url, callbacks) {
          stop(); handlers = callbacks;
          var ticket = generation;
          function invoke(name) { if (ticket === generation && handlers === callbacks) callbacks[name](); }
          listen('playing', function () { invoke('ready'); });
          listen('waiting', function () { invoke('buffering'); });
          listen('stalled', function () { invoke('buffering'); });
          listen('error', function () { invoke('error'); });
          listen('ended', function () { invoke('ended'); });
          video.src = url; video.load();
          var result = video.play();
          if (result && result.catch) result.catch(function () { invoke('error'); });
        },
        stop: stop,
        setRect: function () {}
      };
    }
  };
}(window));
