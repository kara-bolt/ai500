import * as fs from 'fs';

async function inject() {
  const indexHtmlPath = 'index.tmp.html';
  let html = fs.readFileSync(indexHtmlPath, 'utf-8');

  // 1. Update stats - clean version
  const statsHtml = `
                <div class="stat-card">
                    <span class="label">Token Price</span>
                    <span class="value" id="price">...</span>
                </div>
                <div class="stat-card">
                    <span class="label">Market Cap</span>
                    <span class="value" id="mcap">...</span>
                </div>
                <div class="stat-card">
                    <span class="label">AI500 Index MCap</span>
                    <span class="value">$852.2M</span>
                </div>
                <div class="stat-card">
                    <span class="label">AGIX Total Minted</span>
                    <span class="value">1.2M AGIX</span>
                </div>
                <div class="stat-card">
                    <span class="label">Fees Claimed</span>
                    <span class="value">2.3M KARA</span>
                    <span class="sub-value">0.0027 ETH</span>
                </div>
                <div class="stat-card">
                    <span class="label">Agent Uptime</span>
                    <span class="value">99.9%</span>
                </div>
  `;
  
  html = html.replace(/<div class="stats-grid">[\s\S]*?<\/div>/, `<div class="stats-grid">${statsHtml}</div>`);

  // 2. Add constituents table
  const tableHtml = fs.readFileSync('table.tmp.html', 'utf-8');
  if (!html.includes('ai500-table-container')) {
    html = html.replace('</section>\n\n        <section class="comics-section">', `</section>\n\n        ${tableHtml}\n\n        <section class="comics-section">`);
  } else {
    // Update existing table
    html = html.replace(/<div class="ai500-table-container">[\s\S]*?<\/div>/, tableHtml);
  }

  fs.writeFileSync('index.final.html', html);
}

inject();
