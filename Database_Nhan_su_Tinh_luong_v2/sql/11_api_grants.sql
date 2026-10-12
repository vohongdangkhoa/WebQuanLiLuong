-- Run as PAYROLL_APP after all objects compile VALID.
GRANT EXECUTE ON PKG_HR_CORE TO PAYROLL_API;
GRANT EXECUTE ON PKG_PAYROLL_CORE TO PAYROLL_API;
GRANT EXECUTE ON PKG_PAYMENT TO PAYROLL_API;
GRANT EXECUTE ON PKG_PAYROLL_READ TO PAYROLL_API;
GRANT EXECUTE ON PKG_REQUESTS TO PAYROLL_API;
-- Never grant EXECUTE on PKG_PAYROLL_INTERNAL.
-- Never grant direct DML/SELECT on tables to PAYROLL_API.
-- p_actor is supplied by a trusted API from its verified identity, never from request JSON.
-- These grants secure a server credential; they do not authenticate a human DB user.
