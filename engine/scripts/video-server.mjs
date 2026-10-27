#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import fsp from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { pipeline } from "node:stream";
import { fileURLToPath } from "node:url";

function normalizeHash(value) {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(normalized)) {
    throw new Error("Expected SHA-256 must be 64 hexadecimal characters.");
  }
  return normalized;
}

async function hashFile(filePath) {
  const hash = crypto.createHash("sha256");
  for await (const chunk of fs.createReadStream(filePath)) hash.update(chunk);
  return hash.digest("hex");
}

export async function validateVideoSource({ filePath, expectedSize, expectedSha256 }) {
  const resolved = path.resolve(String(filePath ?? ""));
  const expectedHash = normalizeHash(expectedSha256);
  const size = Number(expectedSize);
  if (!Number.isSafeInteger(size) || size <= 0) {
    throw new Error("Expected video size must be a positive safe integer.");
  }
  const entry = await fsp.lstat(resolved);
  if (!entry.isFile() || entry.isSymbolicLink()) {
    throw new Error("Video source must be a regular file.");
  }
  if (entry.size !== size) {
    throw new Error("Video size mismatch: expected " + size + ", received " + entry.size + ".");
  }
  const actualHash = await hashFile(resolved);
  if (actualHash !== expectedHash) {
    throw new Error("Video SHA-256 mismatch: expected " + expectedHash + ", received " + actualHash + ".");
  }
  return { filePath: resolved, size, sha256: actualHash };
}

export function parseSingleRange(header, size) {
  if (typeof header !== "string" || !header.startsWith("bytes=") || header.includes(",")) {
    return null;
  }
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || (!match[1] && !match[2])) return null;
  let start;
  let end;
  if (!match[1]) {
    const suffix = Number(match[2]);
    if (!Number.isSafeInteger(suffix) || suffix <= 0) return null;
    start = Math.max(0, size - suffix);
    end = size - 1;
  } else {
    start = Number(match[1]);
    end = match[2] ? Number(match[2]) : size - 1;
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end)) return null;
    end = Math.min(end, size - 1);
  }
  if (start < 0 || start >= size || end < start) return null;
  return { start, end };
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
    server.closeAllConnections?.();
  });
}

function playerDocument() {
  return [
    "<!doctype html><meta charset=\"utf-8\">",
    "<meta name=\"color-scheme\" content=\"dark\">",
    "<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}",
    "video{display:block;width:100%;height:100%;object-fit:cover;object-position:center}</style>",
    "<video id=\"video\" src=\"./video.mp4\" autoplay muted loop playsinline></video>",
    "<script>",
    "const video=document.getElementById('video');",
    "const send=(state)=>parent.postMessage({type:\"dream-skin-video-state\",state},\"*\");",
    "video.addEventListener('playing',()=>send('playing'));",
    "video.addEventListener('pause',()=>send('paused'));",
    "video.addEventListener('error',()=>send('error'));",
    "addEventListener('message',(event)=>{",
    "if(event.source!==parent||event.data?.type!==\"dream-skin-video-command\")return;",
    "if(event.data.command===\"pause\")video.pause();",
    "else if(event.data.command===\"play\")video.play().catch(()=>send('error'));",
    "});",
    "video.play().catch(()=>send('error'));",
    "</script>",
  ].join("");
}

export async function startVideoServer({
  filePath,
  expectedSize,
  expectedSha256,
  token = crypto.randomBytes(32).toString("hex"),
}) {
  if (!/^[a-f0-9]{64}$/.test(token)) {
    throw new Error("Video access token must be 64 lowercase hexadecimal characters.");
  }
  const source = await validateVideoSource({ filePath, expectedSize, expectedSha256 });
  const route = "/" + token + "/video.mp4";
  const playerRoute = "/" + token + "/player.html";
  const playerHtml = Buffer.from(playerDocument(), "utf8");
  const server = http.createServer((request, response) => {
    let requestUrl;
    try {
      requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");
    } catch {
      response.writeHead(400, { "Content-Length": "0" });
      response.end();
      return;
    }
    if (requestUrl.search || (requestUrl.pathname !== route && requestUrl.pathname !== playerRoute)) {
      response.writeHead(404, { "Content-Length": "0" });
      response.end();
      return;
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      response.writeHead(405, { Allow: "GET, HEAD", "Content-Length": "0" });
      response.end();
      return;
    }

    if (requestUrl.pathname === playerRoute) {
      response.writeHead(200, {
        "Cache-Control": "no-store",
        "Content-Length": String(playerHtml.length),
        "Content-Security-Policy": "default-src 'none'; media-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'",
        "Content-Type": "text/html; charset=utf-8",
        "X-Content-Type-Options": "nosniff",
      });
      if (request.method === "HEAD") response.end();
      else response.end(playerHtml);
      return;
    }

    const baseHeaders = {
      "Accept-Ranges": "bytes",
      "Cache-Control": "no-store",
      "Content-Type": "video/mp4",
    };
    const rangeHeader = request.headers.range;
    if (rangeHeader) {
      const range = parseSingleRange(rangeHeader, source.size);
      if (!range) {
        response.writeHead(416, {
          ...baseHeaders,
          "Content-Length": "0",
          "Content-Range": "bytes */" + source.size,
        });
        response.end();
        return;
      }
      const length = range.end - range.start + 1;
      response.writeHead(206, {
        ...baseHeaders,
        "Content-Length": String(length),
        "Content-Range": "bytes " + range.start + "-" + range.end + "/" + source.size,
      });
      if (request.method === "HEAD") {
        response.end();
      } else {
        pipeline(fs.createReadStream(source.filePath, range), response, () => {});
      }
      return;
    }

    response.writeHead(200, {
      ...baseHeaders,
      "Content-Length": String(source.size),
    });
    if (request.method === "HEAD") {
      response.end();
    } else {
      pipeline(fs.createReadStream(source.filePath), response, () => {});
    }
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  server.removeAllListeners("error");
  const address = server.address();
  if (!address || typeof address === "string") {
    await closeServer(server);
    throw new Error("Video server did not expose an IPv4 loopback address.");
  }
  return {
    address,
    source,
    token,
    url: "http://127.0.0.1:" + address.port + route,
    playerUrl: "http://127.0.0.1:" + address.port + playerRoute,
    close: () => closeServer(server),
  };
}

function parseCliArguments(argumentsList) {
  const options = {};
  for (let index = 0; index < argumentsList.length; index += 2) {
    const name = argumentsList[index];
    const value = argumentsList[index + 1];
    if (!value || (name !== "--config" && name !== "--ready")) {
      throw new Error("Usage: video-server.mjs --config <path> --ready <path>");
    }
    options[name.slice(2)] = value;
  }
  if (!options.config || !options.ready || Object.keys(options).length !== 2) {
    throw new Error("Usage: video-server.mjs --config <path> --ready <path>");
  }
  return options;
}

async function writeJsonAtomically(filePath, value) {
  const resolved = path.resolve(filePath);
  const temporary = resolved + ".tmp-" + process.pid + "-" + crypto.randomBytes(4).toString("hex");
  try {
    await fsp.writeFile(temporary, JSON.stringify(value), { encoding: "utf8", flag: "wx" });
    await fsp.rename(temporary, resolved);
  } finally {
    await fsp.rm(temporary, { force: true }).catch(() => {});
  }
}

async function runCli() {
  const options = parseCliArguments(process.argv.slice(2));
  const config = JSON.parse(await fsp.readFile(path.resolve(options.config), "utf8"));
  const startedAt = new Date().toISOString();
  const instance = await startVideoServer(config);
  const tokenSha256 = crypto.createHash("sha256").update(instance.token).digest("hex");
  try {
    await writeJsonAtomically(options.ready, {
      schema: "codex-dream-skin-video-ready/1",
      pid: process.pid,
      startedAt,
      host: instance.address.address,
      port: instance.address.port,
      token: instance.token,
      tokenSha256,
      url: instance.url,
      fileSize: instance.source.size,
      fileSha256: instance.source.sha256,
    });
  } catch (error) {
    await instance.close();
    throw error;
  }
  process.stdout.write("READY\n");
  const stop = async () => {
    await instance.close();
    process.exit(0);
  };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli().catch((error) => {
    process.stderr.write("Video server failed: " + (error?.message ?? String(error)) + "\n");
    process.exitCode = 1;
  });
}
