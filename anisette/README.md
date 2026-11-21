# Anisette server

Anisette is the machine identity Apple wants next to a sign-in. The public
servers are used by everybody at once and get throttled, so this serves the same
endpoints from your own machine and keeps one identity warm for everyone on your
network.

## Run it

Python 3, no packages:

```
python anisette_server.py
```

or double-click `run.bat` on Windows, `./run.sh` on Linux and macOS.

At startup it prints three addresses:

```
  This PC:      http://127.0.0.1:6969
  Your network: http://192.168.1.20:6969
  Public:       http://203.0.113.7:6969
```

Paste one into SuperStore's **Anisette** box in step 2 (or pass
`--anisette-server http://…` on the command line). The public address only
answers from outside your network if TCP 6969 is forwarded to this machine.

## Endpoints

| Path | What it returns |
| --- | --- |
| `/` or `/v3/get_headers` | The Anisette headers, refreshed every ten minutes |
| `/v3/client_info` | The client info and user agent Apple expects |
| `/health` | Which upstream this machine identity came from |

`?refresh=1` forces a new identity. One is kept in memory only; restarting the
server asks upstream for a fresh one.

## Options

```
--port 6969            port to listen on
--host 0.0.0.0         interface to bind
--upstream URL         fetch the identity from this server (repeatable)
--no-public-ip         skip the public address lookup
```
