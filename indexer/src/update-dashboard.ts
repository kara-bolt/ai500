import * as fs from 'fs';
import { IndexSnapshot } from './types.js';

async function updateDashboard() {
  const snapshotPath = 'data/snapshot.json';
  const tokensPath = 'data/tokens.json';
  
  if (!fs.existsSync(snapshotPath) || !fs.existsSync(tokensPath)) {
    console.error('Data files missing');
    return;
  }

  const snapshot: IndexSnapshot = JSON.parse(fs.readFileSync(snapshotPath, 'utf-8'));
  const tokens = JSON.parse(fs.readFileSync(tokensPath, 'utf-8'));
  
  // Create a map for quick lookup
  const tokenMap = new Map(tokens.map((t: any) => [t.address.toLowerCase(), t]));

  const totalMcap = Number(snapshot.totalMarketCap);
  const formattedMcap = (totalMcap / 1_000_000).toFixed(1) + 'M';
  
  // Generate HTML for constituents table
  let constituentsHtml = `
    <div class="ai500-table-container">
      <style>
        .ai500-table-container { margin-top: 3rem; text-align: left; }
        .ai500-table { width: 100%; border-collapse: collapse; margin-top: 1rem; font-family: 'JetBrains Mono', monospace; font-size: 0.85rem; }
        .ai500-table th { text-align: left; padding: 0.75rem; border-bottom: 1px solid rgba(0, 242, 255, 0.2); color: var(--gray); font-size: 0.7rem; text-transform: uppercase; }
        .ai500-table td { padding: 0.75rem; border-bottom: 1px solid rgba(255, 255, 255, 0.03); }
        .ai500-table tr:hover { background: rgba(0, 242, 255, 0.05); }
        .ai500-table a { text-decoration: none; margin-right: 0.5rem; filter: grayscale(1); transition: filter 0.3s; }
        .ai500-table a:hover { filter: grayscale(0); }
      </style>
      <h3>AI500 Index Constituents</h3>
      <table class="ai500-table">
        <thead>
          <tr>
            <th>Rank</th>
            <th>Symbol</th>
            <th>Weight</th>
            <th>Market Cap</th>
            <th>Links</th>
          </tr>
        </thead>
        <tbody>
  `;

  snapshot.constituents.slice(0, 10).forEach(c => {
    const token = tokenMap.get(c.address.toLowerCase());
    const gtUrl = token?.geckoTerminalUrl || '#';
    const weight = (c.weight / 100).toFixed(2) + '%';
    const mcap = '$' + (Number(c.marketCap) / 1_000_000).toFixed(1) + 'M';
    
    constituentsHtml += `
          <tr>
            <td>${c.rank}</td>
            <td><strong>${c.symbol}</strong></td>
            <td>${weight}</td>
            <td>${mcap}</td>
            <td>
              <a href="${gtUrl}" target="_blank" title="GeckoTerminal">🦎</a>
              <a href="https://basescan.org/token/${c.address}" target="_blank" title="BaseScan">🔗</a>
            </td>
          </tr>
    `;
  });

  constituentsHtml += `
        </tbody>
      </table>
      <p style="font-size: 0.7rem; color: #444; margin-top: 1rem;">* Tracking top 500 AI agents on Base. Market data via DexScreener. Updated daily.</p>
    </div>
  `;

  console.log('--- STATS ---');
  console.log(`TOTAL_MCAP: ${formattedMcap}`);
  console.log('--- HTML ---');
  console.log(constituentsHtml);
}

updateDashboard();
