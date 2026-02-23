import { PrismaClient } from '@prisma/client'
const prisma = new PrismaClient()

async function main() {
  const p = await prisma.province.findFirst()
  console.log("Province:", p)
  const d = await prisma.district.findFirst()
  console.log("District:", d)
}
main()
