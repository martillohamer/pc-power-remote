import React from 'react';

export function QuickActionsWidget() {
  const handleAction = (name) => {
    alert(`Comando ejecutado con éxito: ${name}`);
  };

  return (
    <div className="bg-black/90 border border-red-900/60 rounded-xl p-4 font-mono text-xs shadow-xl shadow-red-950/30 backdrop-blur-md mb-6">
      <h3 className="font-bold tracking-wider text-red-500 border-b border-red-900/40 pb-2 mb-3">
        // ATAJOS Y COMANDOS RÁPIDOS
      </h3>
      <div className="grid grid-cols-2 gap-3">
        <button 
          onClick={() => handleAction('Limpiar Caché Temporal')}
          className="p-3 bg-red-950/30 hover:bg-red-900/50 border border-red-900/50 rounded-lg text-red-300 transition text-center font-semibold shadow-sm cursor-pointer"
        >
          🧹 Limpiar Caché
        </button>
        <button 
          onClick={() => handleAction('Reiniciar Servicios del Sistema')}
          className="p-3 bg-red-950/30 hover:bg-red-900/50 border border-red-900/50 rounded-lg text-red-300 transition text-center font-semibold shadow-sm cursor-pointer"
        >
          🔄 Reiniciar Backend
        </button>
      </div>
    </div>
  );
}