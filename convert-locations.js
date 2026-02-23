const fs = require('fs');
const ts = require('typescript');

const tsContent = fs.readFileSync('lib/locations.ts', 'utf8');

// Compile to JS to strip TS types
const jsContent = ts.transpileModule(tsContent, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;

// Evaluate the exported module
const mod = {};
eval(`(function(exports) { ${jsContent} })(mod);`);

let dartContent = `// Auto-generated locations file based on lib/locations.ts

class AppLocations {
  static const List<Map<String, String>> provinces = [\n`;

mod.provinces.forEach(p => {
  dartContent += `    {'id': '${p.id}', 'name': '${p.name}'},\n`;
});

dartContent += `  ];\n\n  static const Map<String, List<Map<String, String>>> districts = {\n`;

for (const [provId, dists] of Object.entries(mod.allDistricts)) {
  dartContent += `    '${provId}': [\n`;
  dists.forEach(d => {
    dartContent += `      {'id': '${d.id}', 'name': '${d.name}'},\n`;
  });
  dartContent += `    ],\n`;
}

dartContent += `  };\n}\n`;

if (!fs.existsSync('mobile/lib/core/constants')) {
  fs.mkdirSync('mobile/lib/core/constants', { recursive: true });
}

fs.writeFileSync('mobile/lib/core/constants/locations.dart', dartContent);
console.log('Successfully created mobile/lib/core/constants/locations.dart');
