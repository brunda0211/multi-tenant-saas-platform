const express = require('express');
const app = express();
const PORT = process.env.PORT || 80;
const TENANT = process.env.TENANT_NAME || 'unknown';

app.get('/', (req, res) => {
  res.json({
    message: 'Multi-Tenant SaaS Platform',
    tenant: TENANT,
    version: process.env.VERSION || '1.0.0',
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', tenant: TENANT });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT} for tenant: ${TENANT}`);
});
