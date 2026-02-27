"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { MessageSquare, CheckCircle, XCircle } from "lucide-react";

interface AdActionsProps {
    actionType: "MESSAGE" | "ACCEPT_BID" | "CANCEL_BID" | "FINALIZE_SALE";
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
                // ... (existing message logic)
                const res = await fetch("/api/conversations", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ userId: sellerId, adId }),
                });

                if (res.ok) {
                    const conversation = await res.json();
                    if (initialMessage) {
                        try {
                            const currentUserId = currentUser.id;
                            const recipientId = conversation.user1Id === currentUserId ? conversation.user2Id : conversation.user1Id;
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
                if (!confirm("Bu teklifi kabul etmek istediğinize emin misiniz? (Sadece sohbet başlatılacaktır, ilan hala aktif kalacaktır)")) {
                    setIsLoading(false);
                    return;
                }

                const res = await fetch(`/api/bids/${bidId}/accept`, {
                    method: "PATCH",
                });

                if (res.ok) {
                    alert("Teklif kabul edildi! Şimdi alıcı ile iletişime geçebilirsiniz.");
                    router.refresh();
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
                    router.refresh();
                } else {
                    const data = await res.json();
                    alert(data.message || "Teklif iptal edilemedi.");
                }
            } else if (actionType === "FINALIZE_SALE" && bidId) {
                if (!confirm("Dikkat! Satışın gerçekleştiğini onaylıyorsunuz. Bu işlemden sonra ilan PASİF (Satıldı) durumuna düşecektir. Emin misiniz?")) {
                    setIsLoading(false);
                    return;
                }

                const res = await fetch(`/api/bids/${bidId}/finalize`, {
                    method: "POST",
                });

                if (res.ok) {
                    alert("Satış başarıyla tamamlandı! İlan yayından kaldırıldı.");
                    router.refresh();
                } else {
                    const data = await res.json();
                    alert(data.message || "Satış tamamlanamadı.");
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
                    title="Mesaj Gönder"
                    style={{
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        width: '32px',
                        height: '32px',
                        padding: '0',
                        fontSize: '0.8rem',
                        color: 'var(--primary)',
                        borderColor: 'transparent',
                        background: 'rgba(0, 180, 204, 0.08)',
                        borderRadius: '50%',
                        cursor: 'pointer',
                        transition: 'all 0.2s ease',
                        border: '1px solid transparent'
                    }}
                    onMouseEnter={(e) => {
                        e.currentTarget.style.background = 'rgba(0, 180, 204, 0.15)';
                        e.currentTarget.style.borderColor = 'rgba(0, 180, 204, 0.2)';
                    }}
                    onMouseLeave={(e) => {
                        e.currentTarget.style.background = 'rgba(0, 180, 204, 0.08)';
                        e.currentTarget.style.borderColor = 'transparent';
                    }}
                >
                    <MessageSquare size={16} style={{ minWidth: '16px' }} />
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
                {isLoading ? "..." : "Kabul Et ve Konuş"}
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

    if (actionType === "FINALIZE_SALE") {
        return (
            <button
                onClick={handleAction}
                disabled={isLoading}
                className="btn btn-primary"
                style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px',
                    padding: '4px 12px',
                    fontSize: '0.8rem',
                    fontWeight: 700,
                    backgroundColor: 'var(--accent-green)',
                    color: 'white',
                    borderColor: 'var(--accent-green)',
                    boxShadow: '0 2px 4px rgba(34, 197, 94, 0.2)'
                }}
            >
                <CheckCircle size={14} />
                {isLoading ? "..." : "Satışı Tamamla"}
            </button>
        );
    }

    return null;
}
