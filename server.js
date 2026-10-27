// Santo Santo Santo · servidor do app (Node.js, sem dependências externas)
// Uso: npm start   (porta definida pela variável PORT; padrão 3000)
'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const PORT = Number(process.env.PORT) || 3000;
const PUBLIC = path.join(__dirname, 'docs');
const SUPABASE = 'uazetizbzpzdplaynwcl.supabase.co';

const TIPOS = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.svg': 'image/svg+xml',
  '.css': 'text/css; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8'
};

const CSP = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline' https://hcaptcha.com https://*.hcaptcha.com",
  "frame-src https://hcaptcha.com https://*.hcaptcha.com",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://hcaptcha.com https://*.hcaptcha.com",
  "font-src https://fonts.gstatic.com",
  "img-src 'self' data: blob: https:",
  `connect-src 'self' https://${SUPABASE} wss://${SUPABASE} https://hcaptcha.com https://*.hcaptcha.com`,
  "worker-src 'self' blob:",
  "manifest-src 'self'",
  "object-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'"
].join('; ');

const SEGURANCA = {
  'Content-Security-Policy': CSP,
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
  'Cross-Origin-Opener-Policy': 'same-origin-allow-popups'
};

// página e service worker: sempre conferem versão nova; ícones: guardados por 7 dias
function cache(arquivo) {
  const nome = path.basename(arquivo);
  if (nome === 'index.html' || nome === 'sw.js' || nome.endsWith('.webmanifest')) return 'no-cache';
  if (arquivo.includes(`${path.sep}icons${path.sep}`)) return 'public, max-age=604800';
  return 'public, max-age=3600';
}

function responder(res, status, corpo, extras = {}) {
  res.writeHead(status, { ...SEGURANCA, 'Content-Type': 'text/plain; charset=utf-8', ...extras });
  res.end(corpo);
}

const servidor = http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return responder(res, 405, 'Método não permitido', { Allow: 'GET, HEAD' });
  }

  let caminho;
  try {
    caminho = decodeURIComponent(new URL(req.url, 'http://local').pathname);
  } catch {
    return responder(res, 400, 'Endereço inválido');
  }
  if (caminho.endsWith('/')) caminho += 'index.html';

  // impede sair da pasta docs (ex.: /../server.js)
  const arquivo = path.normalize(path.join(PUBLIC, caminho));
  if (!arquivo.startsWith(PUBLIC + path.sep)) return responder(res, 403, 'Acesso negado');

  fs.stat(arquivo, (erro, info) => {
    // qualquer endereço desconhecido sem extensão abre o app
    const destino = (!erro && info.isFile()) ? arquivo
      : (path.extname(caminho) === '' ? path.join(PUBLIC, 'index.html') : null);
    if (!destino) return responder(res, 404, 'Não encontrado');

    fs.stat(destino, (erro2, info2) => {
      if (erro2) return responder(res, 404, 'Não encontrado');
      res.writeHead(200, {
        ...SEGURANCA,
        'Content-Type': TIPOS[path.extname(destino).toLowerCase()] || 'application/octet-stream',
        'Content-Length': info2.size,
        'Cache-Control': cache(destino),
        ...(path.basename(destino) === 'sw.js' ? { 'Service-Worker-Allowed': '/' } : {})
      });
      if (req.method === 'HEAD') return res.end();
      fs.createReadStream(destino).pipe(res);
    });
  });
});

servidor.listen(PORT, () => {
  console.log(`Santo Santo Santo · app rodando na porta ${PORT}`);
});
