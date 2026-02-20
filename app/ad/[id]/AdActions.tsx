"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { MessageSquare, CheckCircle } from "lucide-react";

interface AdActionsProps {
    actionType: "MESSAGE" | "ACCEPT_BID";
    adId?: string;
    sellerId?: string;
    bidId?: string;
    currentUser: any;
}

export function AdActions({
    actionType,
    adId,
    sellerId,
    bidId,
    currentUser,
}: AdActionsProps) {
    const [isLoading, setIsLoading] = useState(false);
    const router = useRouter();

    const handleAction = async () => {
        if (!currentUser) {
            router.push("/login");
            return;
        }

        setIsLoading(true);

        try {
            if (actionType === "MESSAGE") {
                // Navigate to messages or open widget
                // For now, we'll navigate to the messages panel and create a conversation if it doesn't exist
                const res = await fetch("/api/conversations", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ userId: sellerId, adId }),
                });

                if (res.ok) {
                    const conversation = await res.json();
                    router.push(`/dashboard/messages?id=${conversation.id}`);
                } else {
                    const data = await res.json();
                    alert(data.message || "Mesajlaşma başlatılamadı.");
                }
            } else if (actionType === "ACCEPT_BID" && bidId) {
                if (!confirm("Bu teklifi kabul etmek istediğinize emin misiniz?")) {
                    setIsLoading(false);
                    return;
                }

                const res = await fetch(`/api/bids/${bidId}/accept`, {
                    method: "PATCH",
                });

                if (res.ok) {
                    alert("Teklif kabul edildi!");
                    router.refresh(); // Refresh page to show status
                } else {
                    const data = await res.json();
                    alert(data.message || "Teklif kabul edilemedi.");
                }
            }
        } catch (error) {
            console.error("Action error:", error);
            alert("Bir hata oluştu. Lütfen tekrar deneyin.");
        } finally {
            setIsLoading(false);
        }
    };

    if (actionType === "MESSAGE") {
        return (
            <button
                onClick={handleAction}
                disabled={isLoading}
                className="btn btn-primary btn-full"
                style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px' }}
            >
                <MessageSquare size={18} />
                {isLoading ? "İşleniyor..." : "Satıcıya Mesaj Gönder"}
            </button>
        );
    }

    if (actionType === "ACCEPT_BID") {
        return (
            <button
                onClick={handleAction}
                disabled={isLoading}
                className="btn btn-outline"
                style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px',
                    padding: '4px 8px',
                    fontSize: '0.8rem',
                    color: 'var(--success)',
                    borderColor: 'var(--success)',
                    background: 'rgba(76, 175, 80, 0.1)'
                }}
            >
                <CheckCircle size={14} />
                {isLoading ? "..." : "Kabul Et"}
            </button>
        );
    }

    return null;
}
