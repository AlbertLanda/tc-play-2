export function HomeMenuCard({ icon, title, description, onClick }) {
  return (
    <button type="button" className="home-menu-card" onClick={onClick}>
      <span className="home-menu-icon">{icon}</span>
      <div>
        <h3>{title}</h3>
        <p>{description}</p>
      </div>
    </button>
  );
}