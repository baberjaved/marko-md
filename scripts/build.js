#!/usr/bin/env node
// Builds the viewer from src/viewer.template.html.
//   viewer/marko.html  — shipped viewer (no sample documents; the CLI or Claude embeds a document)
//   dist/marko-demo.html — demo with the sample documents embedded (what the Claude artifact shows)
// Usage: node scripts/build.js [--local-libs vendorDir]   (local libs only for offline testing)
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const tpl = fs.readFileSync(path.join(root, 'src', 'viewer.template.html'), 'utf8');
const sampleFiles = [
  path.join(root, 'docs', 'guide.md'),
  path.join(root, 'src', 'samples', 'marko-requirements.md'),
  path.join(root, 'src', 'samples', 'plan-marko-cli-plugin.md'),
];
const samples = sampleFiles.filter(fs.existsSync).map(f => {
  const text = fs.readFileSync(f, 'utf8');
  const title = (text.match(/^title:\s*(.+)$/m) || [])[1] || path.basename(f);
  return { label: title.trim(), name: path.basename(f), text };
});

const libs = {
  cdn: {
    __LIB_MARKED__: 'https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js',
    __LIB_HLJS__: 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js',
    __LIB_MERMAID__: 'https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js',
  },
};
const argLocal = process.argv.indexOf('--local-libs');
if (argLocal !== -1) {
  const dir = process.argv[argLocal + 1];
  libs.local = { __LIB_MARKED__: dir + '/marked.min.js', __LIB_HLJS__: dir + '/hljs.umd.js', __LIB_MERMAID__: dir + '/mermaid.min.js' };
}

function assemble(libset, withSamples, standalone) {
  let out = tpl.replace('__DOCS_JSON__', JSON.stringify(withSamples ? samples : []).replace(/<\//g, '<\\/'));
  for (const [k, v] of Object.entries(libset)) out = out.split(k).join(v);
  if (standalone) {
    out = '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n<style>[hidden]{display:none!important}</style>\n</head>\n<body>\n' + out + '\n</body>\n</html>\n';
  }
  return out;
}

fs.mkdirSync(path.join(root, 'viewer'), { recursive: true });
fs.mkdirSync(path.join(root, 'dist'), { recursive: true });
const write = (rel, content) => { fs.writeFileSync(path.join(root, rel), content); console.log(`${rel}  ${(Buffer.byteLength(content) / 1024).toFixed(0)} KB`); };
write('viewer/marko.html', assemble(libs.cdn, false, true));
fs.mkdirSync(path.join(root, 'claude-app', 'marko', 'viewer'), { recursive: true });
write('claude-app/marko/viewer/marko.html', assemble(libs.cdn, false, true)); // the Claude app skill carries its own copy
write('dist/marko-demo.html', assemble(libs.cdn, true, true));
write('dist/marko-artifact.html', assemble(libs.cdn, true, false)); // no skeleton: the Claude artifact host wraps it
if (libs.local) {
  write('dist/marko-local.html', assemble(libs.local, false, true));
  write('dist/marko-demo-local.html', assemble(libs.local, true, true));
}
