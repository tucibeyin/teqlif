"use client";

import { useState, useEffect } from "react";
import { MessageCircle } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";

export function MessageBell() {
    const [unreadCount, setUnreadCount] = useState(0);

    const fetchUnreadCount = async () => {
        try {
            const res = await fetch("/api/messages/unread");
            if (res.ok) {
                const data = await res.json();
                setUnreadCount(data.unreadCount || 0);
            }
        } catch (error) {
            console.error("Error fetching unread messages:", error);
        }
    };

    useEffect(() => {
        fetchUnreadCount();
        const intervalId = setInterval(fetchUnreadCount, 10000); // 10 seconds polling for better responsiveness
        return () => clearInterval(intervalId);
    }, []);

    return (
        <Link
            href="/dashboard/messages"
            className="btn btn-ghost"
            style={{ padding: "8px", position: "relative", display: 'flex', alignItems: 'center' }}
            title="Mesajlarım"
        >
            <MessageCircle size={20} />
            {unreadCount > 0 && (
                <span
                    style={{
                        position: "absolute",
                        top: "2px",
                        right: "2px",
                        background: "var(--primary)", // Different color than red notifications to distinguish easily
                        color: "white",
                        fontSize: "10px",
                        fontWeight: 700,
                        borderRadius: "50%",
                        width: "16px",
                        height: "16px",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                    }}
                >
                    {unreadCount > 9 ? "9+" : unreadCount}
                </span>
            )}
        </Link>
    );
}
