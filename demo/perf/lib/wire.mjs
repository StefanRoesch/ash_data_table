// What really goes over the wire (PERF_WIRE=1): a TCP proxy between the
// browser and the server that counts the bytes the server sends on the
// LiveView's WebSocket, as they are on the socket: compressed when the two
// agreed on permessage-deflate, with the frames' own headers, without those
// of TCP and IP. The frames Playwright shows are already inflated, so only
// this sees what compression saves.
//
// PERF_WIRE_DEFLATE=0 takes the browser's offer of permessage-deflate
// (`Sec-WebSocket-Extensions`) out of the upgrade request, so that the
// server answers uncompressed as it does without `compress: true`, and the
// same server can be measured both ways.

import net from "node:net"

const END = "\r\n\r\n"

/**
 * Listens on `port` and forwards every connection to `target`. Returns
 * `{ received, deflate, close }`: the bytes the server has sent on LiveView
 * WebSockets so far, whether the last upgrade agreed on permessage-deflate,
 * and the function that stops it.
 */
export function startWire(port, target, { deflate = true } = {}) {
  const state = { received: 0, deflate: null }
  const sockets = new Set()

  const server = net.createServer((client) => {
    const upstream = net.connect(target, "127.0.0.1")
    sockets.add(client).add(upstream)
    let head = Buffer.alloc(0)
    let websocket = null
    let response = Buffer.alloc(0)

    // the first request of a connection says whether it is LiveView's socket
    client.on("data", (chunk) => {
      if (websocket !== null) return upstream.write(chunk)
      head = Buffer.concat([head, chunk])
      const end = head.indexOf(END)
      if (end < 0) return
      let request = head.subarray(0, end + END.length).toString("latin1")
      const rest = head.subarray(end + END.length)
      websocket = /^GET \/live\/websocket[?\s]/.test(request)
      if (websocket && !deflate) request = request.replace(/^sec-websocket-extensions:.*\r\n/gim, "")
      upstream.write(Buffer.from(request, "latin1"))
      if (rest.length > 0) upstream.write(rest)
    })

    upstream.on("data", (chunk) => {
      if (websocket) {
        state.received += chunk.length
        // the answer to the upgrade says what the two agreed on
        if (response !== null) {
          response = Buffer.concat([response, chunk])
          const end = response.indexOf(END)
          if (end >= 0) {
            state.deflate = /^sec-websocket-extensions:.*permessage-deflate/im.test(
              response.subarray(0, end).toString("latin1"),
            )
            response = null
          }
        }
      }
      client.write(chunk)
    })

    const close = () => {
      client.destroy()
      upstream.destroy()
      sockets.delete(client)
      sockets.delete(upstream)
    }
    client.on("close", close).on("error", close)
    upstream.on("close", close).on("error", close)
  })

  return new Promise((resolve, reject) => {
    server.once("error", reject)
    server.listen(port, "127.0.0.1", () =>
      resolve({
        received: () => state.received,
        deflate: () => state.deflate,
        close: () =>
          new Promise((done) => {
            for (const socket of sockets) socket.destroy()
            server.close(() => done())
          }),
      }),
    )
  })
}
