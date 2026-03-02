"use client";

import dynamic from "next/dynamic";

const LiveArena = dynamic(() => import("./LiveArena"), { ssr: false });

export default function LiveArenaWrapper(props: any) {
    return <LiveArena {...props} />;
}
