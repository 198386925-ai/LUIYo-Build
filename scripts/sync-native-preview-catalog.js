// Keep the native preview's upload entries identical to the real homepage.
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const sourcePath = 'YouYouLUI_iOS/YouYouLUI/Web/index.html';
const outputPath = 'YouYouLUI_iOS/YouYouLUI/Web/native-preview-catalog.json';
const html = fs.readFileSync(sourcePath, 'utf8');
const sourceItems = JSON.parse(html.match(/^const items=(.*);$/m)[1]);
const start = html.indexOf('function syncTitleKey(');
const end = html.indexOf('function setChosenWithSync(');
assert(start >= 0 && end > start, 'Original homepage grouping logic must exist');
const preprocessing = html.slice(html.indexOf('const tabSets='), html.indexOf('const extraNamingRules='));
const items = JSON.parse(JSON.stringify(vm.runInNewContext('const items=' + JSON.stringify(sourceItems) + ';\n' + preprocessing + '\n' + html.slice(start, end) + '\nitems', {}, {timeout: 1000})));
const entries = items.flatMap((item, id) => {
  if (item.hiddenFromUI) return [];
  const peers = items.map((peer, index) => ({peer, index})).filter(({peer}) => peer.uploadRepresentative === id);
  const sourceIndices = peers.map(({index}) => index);
  const files = [...new Set(peers.flatMap(({peer}) => [peer.file, ...(peer.files || []), ...(peer.selectedFiles || [])]).filter(Boolean))];
  return [{id, title: item.title.replace(/^LiquidUI\s*/, ''), category: item.category,
    searchText: [item.title, ...item.aliases, ...item.sections, ...files].join(' '), files, sourceIndices}];
});
// Every original resource must still belong to an upload entry after merging.
const covered = entries.flatMap(entry => entry.sourceIndices).sort((a, b) => a - b);
assert.deepStrictEqual(covered, items.map((_, index) => index), 'No original upload resource may disappear');
for (const entry of entries) assert(['liquidui', 'wechat'].includes(entry.category));
const originalFiles = sourceItems.flatMap(item => [item.file, ...(item.files || []), ...(item.selectedFiles || [])]).filter(Boolean);
const generatedFiles = new Set(entries.flatMap(entry => entry.files));
for (const file of originalFiles) assert(generatedFiles.has(file), 'Original filename disappeared: ' + file);
const output = JSON.stringify({totalSourceItems: sourceItems.length, engineItems: items.length, entries}) + '\n';
if (process.argv.includes('--check')) {
  assert.strictEqual(fs.readFileSync(outputPath, 'utf8'), output, 'Regenerate the native catalog after homepage data changes');
} else {
  fs.writeFileSync(outputPath, output);
}
console.log(JSON.stringify({total: entries.length, liquidui: entries.filter(x => x.category === 'liquidui').length,
  wechat: entries.filter(x => x.category === 'wechat').length, coveredSourceItems: sourceItems.length, engineItems: items.length}));
