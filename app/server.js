const express = require('express');
const resolveTenant = require('./middleware/tenant-resolver');
const { Pool } = require('pg');

const app = express();
const port = process.env.PORT || 3000;

// Apply tenant resolver middleware
app.use(resolveTenant);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', tenant: req.tenant.id });
});

// Tenant-specific data endpoint
app.get('/api/data', async (req, res) => {
  try {
    // Access tenant-specific database
    const pool = new Pool({
      connectionString: req.tenant.dbConnection
    });
    
    // All queries automatically scoped to this tenant
    const result = await pool.query(
      'SELECT current_database(), current_user'
    );
    
    res.json({
      tenant: req.tenant.id,
      database: result.rows[0]
    });
    
    await pool.end();
  } catch (err) {
    console.error('Database error:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// Tenant info endpoint
app.get('/api/tenant', (req, res) => {
  res.json({
    tenant: req.tenant.id,
    namespace: req.tenant.namespace,
    timestamp: new Date().toISOString()
  });
});

app.listen(port, () => {
  console.log(`Multi-tenant app listening on port ${port}`);
  console.log(`Tenant ID: ${process.env.TENANT_ID || 'unknown'}`);
});
