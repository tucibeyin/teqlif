"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { MessageSquare, CheckCircle, XCircle } from "lucide-react";

interface AdActionsProps {
    actionType: "MESSAGE" | "ACCEPT_BID" | "CANCEL_BID";
    adId?: string;
    sellerId?: string;
    bidId?: string;
    currentUser: any;
    isMessageBidder?: boolean;
    initialMessage?: string;
    customLabel?: string;
}

export function AdActions({
    actionType,
    adId,
    sellerId,
    bidId,
    currentUser,
    isMessageBidder,
    initialMessage,
    customLabel,
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

                    // If there's an initial message, try to send it before jumping to the conversation
                    if (initialMessage) {
                        try {
                            const currentUserId = currentUser.id;
                            const recipientId = conversation.user1Id === currentUserId ? conversation.user2Id : conversation.user1Id;

                            // Let's only send if conversation is newly created or we just want to push context
                            // The simplest approach is we just send it every time they click to start this context.
                            // To avoid spam, typically we'd only send if new, but let's just send the context message 
                            await fetch('/api/messages', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify({ conversationId: conversation.id, content: initialMessage, recipientId })
                            });
                        } catch (e) {
                            console.error("Failed to push initial context message", e);
                        }
                    }

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
            } else if (actionType === "CANCEL_BID" && bidId) {
                if (!confirm("Kabul edilen bu teklifi iptal etmek istediğinize emin misiniz?")) {
                    setIsLoading(false);
                    return;
                }

                const res = await fetch(`/api/bids/${bidId}/cancel`, {
                    method: "PATCH",
                });

                if (res.ok) {
                    alert("Teklif iptal edildi.");
                    router.refresh(); // Refresh page to show status
                } else {
                    const data = await res.json();
                    alert(data.message || "Teklif iptal edilemedi.");
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
        if (isMessageBidder) {
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
                        color: 'var(--primary)',
                        borderColor: 'var(--primary)',
                        background: 'rgba(0, 188, 212, 0.1)'
                    }}
                >
                    <MessageSquare size={14} />
                    {isLoading ? "..." : ""}
                </button>
            );
        }

        return (
            <button
                onClick={handleAction}
                disabled={isLoading}
                className="btn btn-primary btn-full"
                style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px' }}
            >
                <MessageSquare size={18} />
                {isLoading ? "İşleniyor..." : (customLabel || "Satıcıya Mesaj Gönder")}
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

    if (actionType === "CANCEL_BID") {
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
                    color: 'var(--danger)',
                    borderColor: 'var(--danger)',
                    background: 'rgba(239, 68, 68, 0.1)'
                }}
            >
                <XCircle size={14} />
                {isLoading ? "..." : "İptal Et"}
            </button>
        );
    }

    return null;
}
