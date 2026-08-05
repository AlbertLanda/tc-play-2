import { useEffect, useRef, useState } from 'react';
import { IconChevronDown, IconUser, IconLogout } from './Icons';

export function AccountMenu({ username, onLogout }) {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef(null);
  const initial = (username || 'U').trim().charAt(0).toUpperCase();

  useEffect(() => {
    function handleClickOutside(event) {
      if (containerRef.current && !containerRef.current.contains(event.target)) {
        setIsOpen(false);
      }
    }

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  return (
    <div className="account-menu-container" ref={containerRef} style={{ position: 'relative' }}>
      <button
        type="button"
        className="account-menu-trigger"
        data-open={isOpen}
        onClick={() => setIsOpen((value) => !value)}
        aria-haspopup="true"
        aria-expanded={isOpen}
      >
        <span className="account-avatar">{initial}</span>
        <span>{username}</span>
        <IconChevronDown />
      </button>

      {isOpen && (
        <div className="account-menu" role="menu">
          <div className="account-menu-header">
            <span>Sesión activa</span>
            <strong>{username}</strong>
          </div>

          <button
            type="button"
            role="menuitem"
            onClick={() => setIsOpen(false)}
          >
            <IconUser /> Mi cuenta
          </button>

          <button
            type="button"
            role="menuitem"
            className="is-danger"
            onClick={() => {
              setIsOpen(false);
              onLogout();
            }}
          >
            <IconLogout /> Cerrar sesión
          </button>
        </div>
      )}
    </div>
  );
}
