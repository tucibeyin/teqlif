"use client";

import { useState, useEffect } from "react";
import { usePathname } from "next/navigation";
import { useSession } from "next-auth/react";

export default function TitleBadgeManager() {
    const { data: session } = useSession();
    const [unreadCount, setUnreadCount] = useState(0);
    const pathname = usePathname();

    const fetchCounts = async () => {
        if (!session?.user) return;

        try {
            const [msgRes, notifRes] = await Promise.all([
                fetch("/api/messages/unread"),
                fetch("/api/notifications")
            ]);

            let total = 0;
            if (msgRes.ok) {
                const msgData = await msgRes.json();
                total += msgData.unreadCount || 0;
            }
            if (notifRes.ok) {
                const notifData = await notifRes.json();
                total += notifData.unreadCount || 0;
            }

            setUnreadCount(total);
        } catch (error) {
            console.error("Error fetching unread counts for title badge:", error);
        }
    };

    useEffect(() => {
        if (session?.user) {
            fetchCounts();
        } else {
            setUnreadCount(0);
        }
    }, [pathname, session]);

    useEffect(() => {
        if (!session?.user) return;

        const intervalId = setInterval(fetchCounts, 20000); // Poll every 20 seconds
        return () => clearInterval(intervalId);
    }, [session]);

    useEffect(() => {
        const originalTitle = "teqlif - İstediğin fiyattan al ve sat";
        if (unreadCount > 0) {
            document.title = `(${unreadCount}) teqlif`;
        } else {
            document.title = originalTitle;
        }
    }, [unreadCount]);

    return null; // This component doesn't render anything
}
