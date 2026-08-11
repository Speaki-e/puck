import { createServer } from "node:http";

const host = "127.0.0.1";
const port = Number(process.env.MOCK_ANTHROPIC_PORT ?? 8787);

function event(response, name, data) {
  response.write(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`);
}

const server = createServer((request, response) => {
  if (request.method !== "POST" || request.url !== "/v1/messages") {
    response.writeHead(404, { "content-type": "application/json" });
    response.end(JSON.stringify({ error: { type: "not_found_error", message: "Use POST /v1/messages" } }));
    return;
  }

  let body = "";
  request.setEncoding("utf8");
  request.on("data", (chunk) => { body += chunk; });
  request.on("end", () => {
    let model = "local-anthropic-mock";
    try { model = JSON.parse(body).model ?? model; } catch {}

    response.writeHead(200, {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive",
    });
    event(response, "message_start", {
      type: "message_start",
      message: {
        id: "msg_local_mock",
        type: "message",
        role: "assistant",
        model,
        content: [],
        stop_reason: null,
        stop_sequence: null,
        usage: { input_tokens: 1, output_tokens: 0 },
      },
    });
    event(response, "content_block_start", {
      type: "content_block_start",
      index: 0,
      content_block: { type: "text", text: "" },
    });
    event(response, "content_block_delta", {
      type: "content_block_delta",
      index: 0,
      delta: { type: "text_delta", text: "Local Anthropic mock connected." },
    });
    event(response, "content_block_stop", { type: "content_block_stop", index: 0 });
    event(response, "message_delta", {
      type: "message_delta",
      delta: { stop_reason: "end_turn", stop_sequence: null },
      usage: { output_tokens: 6 },
    });
    event(response, "message_stop", { type: "message_stop" });
    response.end();
  });
});

server.listen(port, host, () => {
  process.stdout.write(`Anthropic-compatible mock listening at http://${host}:${port}/v1/messages\n`);
});
