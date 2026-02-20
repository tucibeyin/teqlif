"use client";

import { useState, useEffect } from "react";
import { Bell } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";

interface Notification {
    id: string;
    message: string;
    link: string | null;
    isRead: boolean;
    createdAt: string;
}

export function NotificationBell() {
    const [notifications, setNotifications] = useState<Notification[]>([]);
    const [unreadCount, setUnreadCount] = useState(0);
    const [isOpen, setIsOpen] = useState(false);
    const router = useRouter();

    const fetchNotifications = async () => {
        try {
            const res = await fetch("/api/notifications");
            if (res.ok) {
                const data = await res.json();
                setNotifications(data.notifications);
                setUnreadCount(data.unreadCount);
            }
        } catch (error) {
            console.error("Error fetching notifications:", error);
        }
    };

    useEffect(() => {
        fetchNotifications();
        // Poll every 30 seconds
        const intervalId = setInterval(fetchNotifications, 30000);
        return () => clearInterval(intervalId);
    }, []);

    const markAsRead = async (id?: string) => {
        try {
            await fetch("/api/notifications", {
                method: "PATCH",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ id }),
            });
            fetchNotifications(); // Refresh list immediately
        } catch (error) {
            console.error("Error marking as read", error);
        }
    };

    const handleNotificationClick = (notification: Notification) => {
        if (!notification.isRead) {
            markAsRead(notification.id);
        }
        setIsOpen(false);
        if (notification.link) {
            router.push(notification.link);
        }
    };

    return (
        <div style={{ position: "relative" }}>
            <button
                onClick={() => setIsOpen(!isOpen)}
                className="btn btn-ghost"
                style={{ padding: "8px", position: "relative" }}
            >
                <Bell size={20} />
                {unreadCount > 0 && (
                    <span
                        style={{
                            position: "absolute",
                            top: "2px",
                            right: "2px",
                            background: "var(--danger)",
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
            </button>

            {isOpen && (
                <div
                    style={{
                        position: "absolute",
                        top: "100%",
                        right: 0,
                        width: "300px",
                        background: "var(--bg-card)",
                        border: "1px solid var(--border)",
                        borderRadius: "var(--radius-md)",
                        boxShadow: "0 10px 25px rgba(0,0,0,0.1)",
                        zIndex: 50,
                        marginTop: "0.5rem",
                    }}
                >
                    <div
                        style={{
                            padding: "1rem",
                            borderBottom: "1px solid var(--border)",
                            display: "flex",
                            justifyContent: "space-between",
                            alignItems: "center",
                        }}
                    >
                        <h4 style={{ margin: 0, fontWeight: 600 }}>Bildirimler</h4>
                        {unreadCount > 0 && (
                            <button
                                onClick={() => markAsRead()}
                                style={{
                                    fontSize: "0.8rem",
                                    color: "var(--primary)",
                                    background: "none",
                                    border: "none",
                                    cursor: "pointer",
                                }}
                            >
                                Tümünü Okundu İşaretle
                            </button>
                        )}
                    </div>
                    <div style={{ maxHeight: "300px", overflowY: "auto" }}>
                        {notifications.length === 0 ? (
                            <div style={{ padding: "1rem", textAlign: "center", color: "var(--text-secondary)", fontSize: "0.9rem" }}>
                                Bildiriminiz yok.
                            </div>
                        ) : (
                            notifications.map((notif) => (
                                <div
                                    key={notif.id}
                                    onClick={() => handleNotificationClick(notif)}
                                    style={{
                                        padding: "1rem",
                                        borderBottom: "1px solid var(--border)",
                                        cursor: "pointer",
                                        background: notif.isRead ? "transparent" : "rgba(0, 188, 212, 0.05)",
                                        transition: "background 0.2s",
                                    }}
                                >
                                    <p
                                        style={{
                                            margin: 0,
                                            fontSize: "0.9rem",
                                            color: notif.isRead ? "var(--text-secondary)" : "var(--text-primary)",
                                            fontWeight: notif.isRead ? 400 : 500,
                                        }}
                                    >
                                        {notif.message}
                                    </p>
                                    <span style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginTop: "0.25rem", display: "block" }}>
                                        {new Date(notif.createdAt).toLocaleDateString("tr-TR", { hour: "2-digit", minute: "2-digit" })}
                                    </span>
                                </div>
                            ))
                        )}
                    </div>
                </div>
            )}
        </div>
    );
}
