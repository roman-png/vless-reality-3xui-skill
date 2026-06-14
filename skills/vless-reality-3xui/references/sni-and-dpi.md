# SNI selection and DPI

## The SNI must match — exactly

Reality authorises a client only if the SNI in its ClientHello is byte-for-byte one of the
server's `serverNames`. There is no wildcard and no partial match. A client configured with
`sni=vk.com` against a server whose `serverNames=["www.microsoft.com"]` is rejected and relayed
to `dest`, which presents as "connected, no traffic" (see [diagnostics.md](diagnostics.md)).

Keep one canonical `vless://` link per inbound and do not hand-edit the `sni=` field on clients.
If you genuinely need to accept several SNIs, list them all in `serverNames` (the array supports
multiple values).

## Choosing dest / serverNames

`dest` is the site whose TLS handshake Reality borrows. Requirements:

- TLS 1.3 + HTTP/2 + X25519, reachable **from the server**. Verify:
  `echo | openssl s_client -connect <dest>:443 -servername <dest> -alpn h2` → expect
  `Protocol: TLSv1.3`, `ALPN protocol: h2`, `Verify return code: 0 (ok)`.
- Not blocked where your clients are.
- Ideally a large, popular site so the SNI is unremarkable.

## Foreign vs domestic SNI (the trap)

It is tempting to use a *domestic, whitelisted* site (e.g. `vk.com`, `yandex.ru`) as the SNI so
the connection survives "allow-list only" censorship modes. There is a catch:

- A **foreign** SNI (e.g. `www.microsoft.com`) pointed at a **foreign** server IP is consistent
  and unremarkable — it just works.
- A **domestic** SNI pointed at a **foreign** server IP is an anomaly. Censors that correlate
  SNI with destination IP (observed on Russian ISP/TSPU systems) can reset such flows: the
  TLS/Reality handshake completes, then the data connection is cut. Symptom: "connected, no
  traffic" *even though the SNI matches the server*.

Practical guidance:

- **Default to a foreign `dest`/SNI.** `www.microsoft.com` is a solid, verified choice.
- Use a domestic SNI only if you specifically need to pass a pure SNI-allowlist mode AND you have
  confirmed the provider does not enforce SNI↔IP correlation. If it does, a domestic SNI is worse
  than a foreign one.
- A single foreign server IP cannot beat an **IP-allowlist** mode (only domestic IPs allowed)
  with any SNI trick; that needs a domestic relay/IP.

## Fingerprint

`fp=chrome` (uTLS) is a fine default. The server accepts any uTLS fingerprint; the fingerprint
only shapes how the ClientHello looks on the wire. A fingerprint mismatch does **not** cause
`server name mismatch` or `failed to read client hello`.
