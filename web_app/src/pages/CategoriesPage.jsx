import { useEffect, useState } from 'react';
import { getLiveCategories } from '../api/liveTvApi';

export function CategoriesPage({ session, onBack, onSelectCategory }) {
  const [categories, setCategories] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState('');

  useEffect(() => {
    async function loadCategories() {
      try {
        setIsLoading(true);
        setErrorMessage('');

        const data = await getLiveCategories(session.username, session.password);
        setCategories(data);
      } catch (error) {
        setErrorMessage(error.message || 'No se pudieron cargar las categorías.');
      } finally {
        setIsLoading(false);
      }
    }

    loadCategories();
  }, [session.username, session.password]);

  return (
    <main className="home-layout">
      <header className="home-header">
        <div>
          <h1>Categorías</h1>
          <p>TV en vivo - TC Play 2.0</p>
        </div>

        <button type="button" onClick={onBack}>
          Volver
        </button>
      </header>

      <section className="categories-content">
        {isLoading && <p className="state-message">Cargando categorías...</p>}

        {!isLoading && errorMessage && (
          <div className="state-card error-state">
            <h2>No se pudieron cargar las categorías</h2>
            <p>{errorMessage}</p>
          </div>
        )}

        {!isLoading && !errorMessage && categories.length === 0 && (
          <div className="state-card">
            <h2>Sin categorías disponibles</h2>
            <p>La línea de cliente no tiene bouquets asignados o no hay contenido disponible.</p>
          </div>
        )}

        {!isLoading && !errorMessage && categories.length > 0 && (
          <div className="categories-grid">
            {categories.map((category) => (
              <button
                type="button"
                className="category-card"
                key={category.id}
                onClick={() => onSelectCategory(category)}
              >
                <span>📡</span>
                <h3>{category.name}</h3>
                <p>ID: {category.id}</p>
              </button>
            ))}
          </div>
        )}
      </section>
    </main>
  );
}