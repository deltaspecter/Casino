import { render } from 'preact'
import { App } from './App'
import { registerServiceWorker } from './ui/install'
import './styles.css'
import './ui/table.css'
import './screens/screens.css'
import './games/games.css'

// Spielstand dauerhaft behalten (Safari löscht sonst Daten selten genutzter Websites).
navigator.storage?.persist?.().catch(() => {})
registerServiceWorker()

render(<App />, document.getElementById('app')!)
