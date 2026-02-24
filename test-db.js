const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
prisma.ad.findMany({ take: 3, orderBy: { createdAt: 'desc' } }).then(console.log);
