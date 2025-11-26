#!/usr/bin/env node
const fs = require('fs');
const mustache = require('mustache');

// Get network from command line argument
const network = process.argv[2];

if (!network) {
  console.error('Usage: node scripts/prepare-subgraph.js <network>');
  process.exit(1);
}

// Load networks configuration
const networks = JSON.parse(fs.readFileSync('networks.json', 'utf8'));

if (!networks[network]) {
  console.error(`Error: Network "${network}" not found in networks.json`);
  console.error(`Available networks: ${Object.keys(networks).join(', ')}`);
  process.exit(1);
}

// Load templates
const subgraphTemplate = fs.readFileSync('subgraph.template.yaml', 'utf8');
const addressesTemplate = fs.readFileSync('src/addresses.template.ts', 'utf8');

// Generate subgraph.yaml
const subgraphOutput = mustache.render(subgraphTemplate, networks[network]);
fs.writeFileSync('subgraph.yaml', subgraphOutput);

// Generate addresses.ts
const addressesOutput = mustache.render(addressesTemplate, networks[network]);
fs.writeFileSync('src/addresses.ts', addressesOutput);

console.log(`Generated subgraph.yaml and src/addresses.ts for ${network}`);