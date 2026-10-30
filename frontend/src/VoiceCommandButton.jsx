import { useEffect, useRef, useState } from 'react'

const SUPPORTED = typeof window !== 'undefined' && !!(window.SpeechRecognition || window.webkitSpeechRecognition)
const RECOGNITION_LANG = 'es-ES'

const VOICE_COMMANDS = {
  apagar: 'shutdown',
  estado: 'state',
  suspender: 'suspend',
  reiniciar: 'restart',
  despertar: 'wake',
  cancelar: 'cancel',
}

function getHudClass(status) {
  switch (status) {
    case 'ready': return 'bg-emerald-500/20 text-emerald-300'
    case 'listening': return 'bg-neon/30 text-neon-soft'
    case 'recognized': return 'bg-emerald-500/20 text-emerald-300'
    case 'error': return 'bg-neon/30 text-neon-soft'
    case 'unsupported': return 'bg-zinc-700 text-zinc-300'
    case 'permission-denied': return 'border-red-500/40 bg-red-500/10 text-red-300'
    case 'unknown-command': return 'bg-emerald-500/20 text-emerald-300'
    default: return 'bg-emerald-500/20 text-emerald-300'
  }
}

export default function VoiceCommandButton({ onCommand }) {
  const [recording, setRecording] = useState(false)
  const [lastCommand, setLastCommand] = useState('')
  const [listeningStatus, setListeningStatus] = useState('ready')
  const animationRef = useRef(null)
  const recRef = useRef(null)

  useEffect(() => {
    if (!SUPPORTED) {
      setListeningStatus('unsupported')
      return
    }
    const rec = new (window.SpeechRecognition || window.webkitSpeechRecognition)()
    recRef.current = rec
    rec.lang = RECOGNITION_LANG
    rec.interimResults = false
    rec.maxAlternatives = 1
    const animate = () => {
      if (animationRef.current) {
        animationRef.current.classList.add('voice-active')
        setTimeout(() => animationRef.current.classList.remove('voice-active'), 300)
      }
    }
    rec.onstart = () => {
      setRecording(true)
      setListeningStatus('listening')
      animate()
    }
    rec.onresult = event => {
      const transcript = event.results[0][0].transcript.trim().toLowerCase()
      setLastCommand(transcript)
      setRecording(false)
      setListeningStatus('recognized')
      onCommand(transcript)
    }
    rec.onerror = event => {
      setRecording(false)
      setListeningStatus('error')
      if (event.error === 'network' || event.error === 'not-allowed') {
        setListeningStatus('permission-denied')
      }
    }
    rec.onend = () => {
      setRecording(false)
      setListeningStatus(recording ? 'listening' : 'ready')
    }
    rec.continuous = false
    rec.interimResults = false
    return () => { rec.stop() }
  }, [onCommand])

  const handleCommand = (text) => {
    setLastCommand(text)
    setListeningStatus('processing')
    const normalized = text.trim().toLowerCase()
    const action = VOICE_COMMANDS[normalized]
    if (action) {
      onCommand(action)
    } else {
      setListeningStatus('unknown-command')
    }
  }

  const hudClass = getHudClass(listeningStatus)

  // Build className using simple concatenation (no template literals)
  const buttonMods = []
  buttonMods.push('relative rounded-full border bg-emerald-500/40 p-3 cursor-pointer')
  if (recording) buttonMods.push('bg-emerald-500/20')
  if (recording) buttonMods.push('text-emerald-300')
  buttonMods.push('cursor-pointer flex items-center justify-center')
  const buttonClass = buttonMods.join(' ')

  return (
    <div className='fixed bottom-4 left-1/2 transform -translate-x-1/2 z-50'>
      <div ref={animationRef} className={hudClass}>
        {listeningStatus === 'listening' && 'Escuchando...'}
        {lastCommand && lastCommand !== '' && '<div>{lastCommand}</div>'}
      </div>
      <button
        onClick={() => {
          if (!recording && !SUPPORTED) { setListeningStatus('unsupported'); return }
          setRecording(!recording)
          if (recording && recRef.current) { recRef.current.start() }
        }}
        className={buttonClass}
        aria-label='voz'
        disabled={!SUPPORTED}
      >
        MIC
      </button>
      {listeningStatus !== 'ready' && (
        <div className='mt-2 text-center text-sm'>
          {listeningStatus === 'unsupported'
            ? 'API no soportada'
            : listeningStatus === 'permission-denied'
              ? 'Permiso denegado'
              : listeningStatus === 'unknown-command'
                ? 'Comando no reconocido'
                : 'Reconocido: ' + lastCommand}
        </div>
      )}
    </div>
  )
}