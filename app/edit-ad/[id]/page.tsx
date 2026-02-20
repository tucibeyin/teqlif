import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";
import { notFound, redirect } from "next/navigation";
import EditAdForm from "./EditAdForm";

export default async function EditAdPage({ params }: { params: Promise<{ id: string }> }) {
    const session = await auth();
    if (!session?.user) redirect("/login");

    const { id } = await params;

    const ad = await prisma.ad.findUnique({
        where: { id },
        include: { category: true }
    });

    if (!ad) notFound();

    if (ad.userId !== session.user.id) {
        return (
            <div className="container" style={{ padding: "4rem 0", textAlign: "center" }}>
                <h2>Yetkisiz Erişim</h2>
                <p>Bu ilanı düzenleme yetkiniz yok.</p>
            </div>
        );
    }

    return <EditAdForm ad={ad} />;
}
