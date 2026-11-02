import React, { useState } from 'react';

export function AutomationPanel() {
  const [cpuRule, setCpuRule] = useState(false);
  const [threshold, setThreshold] = useState(90);

  const handleSave = () => {
    alert(`Regla configurada: Apagado automático si CPU > ${threshold}%`);
  };

  return (
    <div className="bg-black/90 border border-red-900/60 rounded-xl p-4 font-mono text-xs text-gray-300 shadow-xl shadow-red-950/30 backdrop-blur-md mb-6">
      <h3 className="font-bold tracking-wider text-red-500 border-b border-red-900/40 pb-2 mb-3 flex items-center justify-between">
        <span>// PANEL DE RUTINAS Y AUTOMATIZACIONES</span>
        <span className="text-[10px] text-gray-500">MODO ACTIVO</span>
      </h3>
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <span className="text-red-300">Apagado automático por estrés de CPU:</span>
          <input 
            type="checkbox" 
            checked={cpuRule} 
            onChange={() => setCpuRule(!cpuRule)}
            className="accent-red-600 w-4 h-4 cursor-pointer"
          />
        </div>
        {cpuRule && (
          <div className="pl-4 border-l-2 border-red-900/50 space-y-3 pt-2">
            <label className="block text-gray-400">Umbral de activación ({threshold}%):</label>
            <input 
              type="range" 
              min="70" 
              max="99" 
              value={threshold} 
              onChange={(e) => setThreshold(e.target.value)}
              className="w-full accent-red-600 cursor-pointer"
            />
            <button 
              onClick={handleSave}
              className="px-3 py-1.5 bg-red-950/60 hover:bg-red-900/80 border border-red-700/50 text-red-200 rounded transition font-bold"
            >
              Guardar Regla de Automatización
            </button>
          </div>
        )}
      </div>
    </div>
  );
}