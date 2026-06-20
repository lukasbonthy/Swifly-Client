# Swifly Server List

This is the master server endpoint used by the Swifly in-game server browser.

The client does **not** fetch the server list through normal HTTP. It sends a UDP `getservers` packet to the configured master host. This Node app answers with a `getServersResponse` packet in the raw format the client parser expects.

## Default listed server

```txt
mp1.swifly.net:1154
```

## Run locally

```bash
cd server-list
npm start
```

By default it starts:

- UDP master server on `0.0.0.0:20810`
- HTTP status page on `0.0.0.0:3000`

## Production DNS

Point `client.swifly.net` to the VPS/public machine running this app.

Open firewall ports:

- `UDP 20810` for the game client server browser
- Your HTTP reverse-proxy port, usually `TCP 80/443`, for the status page

## Environment variables

```bash
MASTER_PORT=20810
PORT=3000
PUBLIC_HOST=client.swifly.net
SERVERS=mp1.swifly.net:1154
npm start
```

You can add more later with commas:

```bash
SERVERS=mp1.swifly.net:1154,mp2.swifly.net:1154
```

## Important

Hosts like Render/Vercel/Netlify usually do not expose arbitrary UDP ports. Use a VPS, dedicated server, or another host that allows UDP traffic.
