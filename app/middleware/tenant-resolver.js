// tenant-resolver.js
const jwt = require('jsonwebtoken');

function resolveTenant(req, res, next) {
  // Option 1: From hostname
  const hostname = req.hostname;  // acme-corp.yourplatform.local
  const tenantId = hostname.split('.')[0];  // acme-corp
  
  // Option 2: From JWT token
  const token = req.headers.authorization?.split(' ')[1];
  if (token) {
    try {
      const decoded = jwt.decode(token);
      req.tenantId = decoded.tenant_id;
    } catch (err) {
      console.error('Invalid token:', err);
    }
  }
  
  // Option 3: From custom header
  if (req.headers['x-tenant-id']) {
    req.tenantId = req.headers['x-tenant-id'];
  }
  
  // Fallback to hostname
  if (!req.tenantId) {
    req.tenantId = tenantId;
  }
  
  // Store tenant context in request
  req.tenant = {
    id: req.tenantId,
    namespace: `tenant-${req.tenantId}`,
    dbConnection: process.env.DB_HOST 
      ? `postgres://${req.tenantId.replace(/-/g, '_')}_user:${process.env.DB_PASSWORD}@${process.env.DB_HOST}:5432/${req.tenantId.replace(/-/g, '_')}_db`
      : null
  };
  
  console.log(`Request for tenant: ${req.tenant.id}`);
  next();
}

module.exports = resolveTenant;
