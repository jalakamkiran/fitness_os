const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

const screens = [
  { id: 'splash', name: 'splash' },
  { id: 'onboarding-permissions', name: 'onboarding-permissions' },
  { id: 'onboarding-scan', name: 'onboarding-scan' },
  { id: 'onboarding-pairing', name: 'onboarding-pairing' },
  { id: 'onboarding-sync', name: 'onboarding-sync' },
  { id: 'today', name: 'today-light', theme: 'light' },
  { id: 'today', name: 'today-dark', theme: 'dark' },
  { id: 'sleep-detail', name: 'sleep-detail-light', theme: 'light' },
  { id: 'sleep-detail', name: 'sleep-detail-dark', theme: 'dark' },
  { id: 'recovery', name: 'recovery' },
  { id: 'heart-rate', name: 'heart-rate' },
  { id: 'activity', name: 'activity' },
  { id: 'workouts', name: 'workouts' },
  { id: 'workout-detail-swim', name: 'workout-detail-swim' },
  { id: 'workout-detail-run', name: 'workout-detail-run' },
  { id: 'workout-detail-badminton', name: 'workout-detail-badminton' },
  { id: 'programs', name: 'programs' },
  { id: 'food', name: 'food' },
  { id: 'weight', name: 'weight' },
  { id: 'device-sync', name: 'device-sync' },
  { id: 'settings', name: 'settings' },
  { id: 'profile', name: 'profile' },
  { id: 'state-loading', name: 'state-loading' },
  { id: 'state-empty', name: 'state-empty' },
  { id: 'state-error', name: 'state-error' },
  { id: 'state-offline', name: 'state-offline' },
  { id: 'state-syncing', name: 'state-syncing' },
];

(async () => {
  console.log('Launching browser...');
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
  });
  
  const page = await browser.newPage();
  
  // Set viewport to match device frame content area
  await page.setViewport({
    width: 390,
    height: 844,
    deviceScaleFactor: 2,
  });
  
  const indexPath = `file://${path.join(__dirname, 'index.html')}`;
  console.log(`Loading ${indexPath}...`);
  await page.goto(indexPath, { waitUntil: 'networkidle0' });
  
  // Wait for fonts to load
  await new Promise(resolve => setTimeout(resolve, 1000));
  
  for (const screen of screens) {
    console.log(`Capturing ${screen.name}...`);
    
    // Set theme if specified
    if (screen.theme) {
      await page.evaluate((theme) => {
        document.documentElement.setAttribute('data-theme', theme);
      }, screen.theme);
      await new Promise(resolve => setTimeout(resolve, 200));
    }
    
    // Navigate to screen
    await page.evaluate((screenId) => {
      window.showScreen(screenId);
    }, screen.id);
    
    await new Promise(resolve => setTimeout(resolve, 500));
    
    // Capture screenshot of the screen container only
    const element = await page.$('.screen-container');
    const screenshotPath = path.join(__dirname, 'screenshots', `${screen.name}.png`);
    await element.screenshot({ path: screenshotPath });
    
    console.log(`  ✓ Saved ${screen.name}.png`);
  }
  
  console.log('All screenshots captured!');
  await browser.close();
})();
