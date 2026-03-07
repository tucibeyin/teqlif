import { prisma } from "@/lib/prisma";
import { auth } from "@/auth";
import { notFound } from "next/navigation";
import ChannelArenaWrapper from "./ChannelArenaWrapper";

export const revalidate = 0;

export default async function LiveChannelPage({
    params,
}: {
    params: Promise<{ hostId: string }>;
}) {
    const { hostId } = await params;

    const [host, session] = await Promise.all([
        prisma.user.findUnique({
            where: { id: hostId },
            select: { id: true, name: true, avatar: true },
        }),
        auth(),
    ]);

    if (!host) notFound();

    const isOwner = session?.user?.id === hostId;

    return (
        <ChannelArenaWrapper
            hostId={hostId}
            hostName={host.name ?? "Yayıncı"}
            isOwner={isOwner}
        />
    );
}
