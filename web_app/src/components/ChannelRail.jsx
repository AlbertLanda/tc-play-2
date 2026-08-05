import { IconArrowRight, IconTv } from './Icons';
import { getChannelLogo } from '../constants/channelLogos';

export function ChannelRail({ title, eyebrow, channels, onSelectChannel, onSeeAll }) {
  return (
    <section>
      <div className="rail-section-head">
        <div>
          <span className="eyebrow-pill">{eyebrow}</span>
          <h2>{title}</h2>
        </div>

        {onSeeAll && (
          <button type="button" className="rail-see-all" onClick={onSeeAll}>
            Ver todos <IconArrowRight />
          </button>
        )}
      </div>

      {channels.length === 0 ? (
        <div className="rail-empty">
          <IconTv /> Aún no hay canales para mostrar aquí.
        </div>
      ) : (
        <div className="channel-rail no-scrollbar">
          {channels.map((channel) => {
            const logo = getChannelLogo(channel);

            return (
              <button
                type="button"
                className="rail-card"
                key={channel.id}
                onClick={() => onSelectChannel(channel)}
              >
                <div className="rail-card-thumb">
                  {logo ? (
                    <img src={logo} alt="" />
                  ) : (
                    <IconTv />
                  )}
                  <span className="rail-card-live">En vivo</span>
                </div>

                <p className="rail-card-name">{channel.name}</p>
              </button>
            );
          })}
        </div>
      )}
    </section>
  );
}
