import React, { useState, useEffect } from 'react';

export function LiveLogsTerminal() {
  const [logs, setLogs] = useState([
    { id: 1, time: '22:43:27', type: 'INFO', text: 'Sistema T-800 inicializado correctamente.' },
    { id: 2, time: '22:43:33', type: 'TUNNEL', text: 'Cloudflare Quick Tunnel activo.' }
  ]);

  useEffect(() => {
    const interval = setInterval(() => {
      const now = new Date().toLocaleTimeString();
      setLogs(prev => [
        ...prev.slice(-12),
        { id: Date.now(), time: now, type: 'WS', text: 'Sincronización de eventos activa.' }
      ]);
    }, 6000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="bg-black/90 border border-red-900/60 rounded-xl p-4 font-mono text-xs text-red-400 shadow-xl shadow-red-950/30 backdrop-blur-md mb-6">
      <div className="flex justify-between items-center border-b border-red-900/40 pb-2 mb-3">
        <span className="font-bold tracking-wider text-red-500 flex items-center gap-2">
          <span>//</span> CÁJA NEGRA FORENSE - LOGS EN DIRECTO
        </span>
        <span className="flex items-center gap-1.5 text-[10px] text-emerald-400 bg-emerald-950/40 px-2 py-0.5 rounded-full border border-emerald-800/50">
          <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span> LIVE
        </span>
      </div>
      <div className="h-40 overflow-y-auto space-y-1.5 scrollbar-thin scrollbar-thumb-red-900 pr-1">
        {logs.map(log => (
          <div key={log.id} className="flex gap-2 items-start bg-red-950/10 p-1 rounded border border-red-950/30">
            <span className="text-gray-500 shrink-0">[{log.time}]</span>
            <span className="font-semibold text-red-300 shrink-0">[{log.type}]</span>
            <span className="text-gray-300 break-all">{log.text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}