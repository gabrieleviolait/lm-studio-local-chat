# Local Chat for LM Studio

Una chat web minimale per usare [LM Studio](https://lmstudio.ai/) da un altro dispositivo della propria rete locale. Pensata per esercitazioni, demo e uso personale su Windows.

**Creato da [gabrieleviola.it](https://www.gabrieleviola.it/).**

## Funzionalità

- Interfaccia responsive per computer e smartphone.
- Modelli caricati in LM Studio selezionabili dal menu.
- Conversazione e cronologia conservate nel **browser utilizzato** (`localStorage`, ultimi 40 messaggi).
- Nuova conversazione, invio con `Invio` e nuova riga con `Maiusc + Invio`.
- Il modello viene eseguito in LM Studio sul PC host. La chat non utilizza direttamente servizi cloud.
- Nessun Docker, Python, Node.js o account aggiuntivo necessario. Server web in PowerShell incluso in Windows.

## Avvio su Windows

1. Installa e apri **LM Studio**, scarica e carica un modello adatto alla chat.
2. In **Developer > Local Server** avvia il server (`Running`) sulla porta **1234**. Il modello deve essere `Ready`.
3. In **Server Settings** disattiva **Require Authentication**. `Serve on Local Network` può essere disattivato, poiché il server web contatta LM Studio su `127.0.0.1`.
4. Scarica il progetto, estrai tutti i file nella stessa cartella e fai doppio clic su **`AVVIA_LOCAL_CHAT.cmd`**.
5. Sul computer apri `http://localhost:3000`. Su un telefono nella stessa rete Wi-Fi apri `http://IP_DEL_PC:3000` (indirizzo indicato dal programma).

Mantieni aperta la finestra di avvio. Per fermare il server chiudila oppure premi `Ctrl+C`.

## Se dal telefono non si apre

- Controlla che sul PC funzioni prima `http://localhost:3000`.
- Verifica che telefono e PC siano nella stessa LAN e non su una rete ospiti isolata.
- Windows Firewall potrebbe bloccare le connessioni in ingresso alla porta TCP `3000`. Puoi consentire solo rete privata e sottorete locale da PowerShell **come amministratore**, se autorizzato:

  ```powershell
  New-NetFirewallRule -DisplayName "Local Chat LM Studio - LAN" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3000 -Profile Private -RemoteAddress LocalSubnet
  ```

- La porta `3000` deve essere libera da altre applicazioni (per esempio Open WebUI).

## Sicurezza e limiti

Questo è un esempio didattico **senza autenticazione**: chi raggiunge `IP_DEL_PC:3000` può usare il modello e l'API chat, quindi eseguilo **solo su una LAN privata fidata**. Non aprire la porta `3000` sul router verso Internet. LM Studio può rimanere in ascolto esclusivamente su `127.0.0.1`, così l'API sulla porta `1234` non è esposta alla LAN.

- I messaggi tra telefono e server viaggiano su **HTTP non cifrato**.
- La cronologia rimane nel singolo browser e non è sincronizzata tra dispositivi.
- Non ci sono account utente, upload di file, RAG o streaming dei token.
- Le richieste sono gestite in sequenza dal server PowerShell: per molte persone contemporaneamente è preferibile una soluzione server dedicata.
- Le API LM Studio sono usate attraverso gli endpoint OpenAI-compatible `/v1/models` e `/v1/chat/completions`.

## Struttura

| File | Utilità |
|---|---|
| `AVVIA_LOCAL_CHAT.cmd` | Avvio con doppio clic su Windows |
| `Start-LocalChat.ps1` | Piccolo server HTTP e proxy verso LM Studio |
| `chat.html` | Pagina della chat (HTML, CSS, JavaScript) |
| `LICENSE` | Licenza MIT del codice di questo progetto |

## Licenza e crediti

**Local Chat for LM Studio**: copyright © 2026 Gabriele Viola. Codice distribuito con licenza **MIT** (vedi `LICENSE`).

Progetto realizzato da [gabrieleviola.it](https://www.gabrieleviola.it/).

LM Studio è un prodotto separato: non è incluso nel repository e resta soggetto alle condizioni dei suoi autori. Nessuna affiliazione ufficiale con LM Studio.
