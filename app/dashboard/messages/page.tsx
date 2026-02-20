"use client";

import { useState, useEffect, useRef, Suspense } from "react";
import { useSession } from "next-auth/react";
import { formatDistanceToNow } from "date-fns";
import { tr } from "date-fns/locale";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Send, ArrowLeft } from "lucide-react";

interface User {
    id: string;
    name: string;
    avatar: string | null;
}

interface Message {
    id: string;
    content: string;
    createdAt: string;
    senderId: string;
    sender: User;
}

interface Conversation {
    id: string;
    user1: User;
    user2: User;
    ad: { id: string; title: string, images: string[] } | null;
    messages: Message[];
    updatedAt: string;
    _count?: { messages: number };
}

function MessagesContent() {
    const { data: session } = useSession();
    const searchParams = useSearchParams();
    const initialConversationId = searchParams.get("id");

    const [conversations, setConversations] = useState<Conversation[]>([]);
    const [activeConversationId, setActiveConversationId] = useState<string | null>(initialConversationId);
    const [messages, setMessages] = useState<Message[]>([]);
    const [newMessage, setNewMessage] = useState("");
    const [isLoading, setIsLoading] = useState(true);
    const [isSending, setIsSending] = useState(false);

    const messagesEndRef = useRef<HTMLDivElement>(null);

    const scrollToBottom = () => {
        messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
    };

    useEffect(() => {
        const fetchConversations = async () => {
            try {
                const res = await fetch("/api/conversations");
                if (res.ok) {
                    const data = await res.json();
                    setConversations(data);
                    // If no initial id and there are conversations, select the first one on desktop
                    if (!initialConversationId && data.length > 0 && window.innerWidth > 768) {
                        setActiveConversationId(data[0].id);
                    }
                }
            } catch (error) {
                console.error("Failed to fetch conversations", error);
            } finally {
                setIsLoading(false);
            }
        };

        if (session?.user) {
            fetchConversations();
        }
    }, [session, initialConversationId]);

    const fetchMessages = async (convId: string) => {
        try {
            const res = await fetch(`/api/messages?conversationId=${convId}`);
            if (res.ok) {
                const data = await res.json();
                setMessages(data);
                setTimeout(scrollToBottom, 100);
            }
        } catch (error) {
            console.error("Failed to fetch messages", error);
        }
    };

    useEffect(() => {
        if (activeConversationId) {
            fetchMessages(activeConversationId);
            // Optimistically clear unread count for the active conversation
            setConversations(prev => prev.map(c =>
                c.id === activeConversationId ? { ...c, _count: { messages: 0 } } : c
            ));

            // Polling for new messages
            const interval = setInterval(() => {
                fetchMessages(activeConversationId);
            }, 5000);
            return () => clearInterval(interval);
        }
    }, [activeConversationId]);

    const handleSendMessage = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!newMessage.trim() || !activeConversationId || !session?.user) return;

        setIsSending(true);
        const activeConversation = conversations.find(c => c.id === activeConversationId);
        if (!activeConversation) {
            setIsSending(false); return;
        }

        // Determine recipient
        const currentUserId = (session.user as any).id;
        const recipientId = activeConversation.user1.id === currentUserId
            ? activeConversation.user2.id
            : activeConversation.user1.id;

        try {
            const res = await fetch("/api/messages", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    conversationId: activeConversationId,
                    content: newMessage,
                    recipientId
                }),
            });

            if (res.ok) {
                setNewMessage("");
                fetchMessages(activeConversationId);

                // Refresh conversations list to update 'last message' and sorting internally if we wanted to
            } else {
                alert("Mesaj gönderilemedi");
            }
        } catch (error) {
            console.error(error);
        } finally {
            setIsSending(false);
        }
    };

    if (isLoading) {
        return (
            <div className="container" style={{ padding: '2rem 0', textAlign: 'center' }}>
                Yükleniyor...
            </div>
        );
    }

    const activeConversation = conversations.find(c => c.id === activeConversationId);
    const currentUserId = (session?.user as any)?.id;

    // View logic for mobile (show list OR messages) vs desktop (show both)
    const isMobileView = typeof window !== 'undefined' && window.innerWidth <= 768;
    const showList = !isMobileView || !activeConversationId;
    const showChat = !isMobileView || activeConversationId;

    return (
        <div className="container" style={{ padding: '2rem 0' }}>
            <h1 style={{ marginBottom: '1.5rem', fontSize: '1.75rem', fontWeight: 700 }}>Mesajlarım</h1>

            <div style={{
                display: 'flex',
                height: '70vh',
                minHeight: '500px',
                background: 'var(--bg-card)',
                borderRadius: 'var(--radius-lg)',
                border: '1px solid var(--border)',
                overflow: 'hidden'
            }}>
                {/* Sol Panel: Konuşma Listesi */}
                {showList && (
                    <div style={{
                        width: isMobileView ? '100%' : '320px',
                        borderRight: isMobileView ? 'none' : '1px solid var(--border)',
                        display: 'flex',
                        flexDirection: 'column'
                    }}>
                        <div style={{ padding: '1rem', borderBottom: '1px solid var(--border)' }}>
                            <h2 style={{ fontSize: '1.1rem', fontWeight: 600, margin: 0 }}>Sohbetler</h2>
                        </div>
                        <div style={{ flex: 1, overflowY: 'auto' }}>
                            {conversations.length === 0 ? (
                                <div style={{ padding: '2rem 1rem', textAlign: 'center', color: 'var(--text-secondary)' }}>
                                    Henüz mesajınız bulunmuyor.
                                </div>
                            ) : (
                                conversations.map(conv => {
                                    const otherUser = conv.user1.id === currentUserId ? conv.user2 : conv.user1;
                                    const lastMessage = conv.messages[0];
                                    const isActive = conv.id === activeConversationId;

                                    return (
                                        <div
                                            key={conv.id}
                                            onClick={() => setActiveConversationId(conv.id)}
                                            style={{
                                                padding: '1rem',
                                                borderBottom: '1px solid var(--border)',
                                                cursor: 'pointer',
                                                background: isActive ? 'rgba(0, 188, 212, 0.08)' : 'transparent',
                                                transition: 'background 0.2s'
                                            }}
                                            className="hover:bg-primary-50"
                                        >
                                            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.25rem' }}>
                                                <div style={{ fontWeight: 600, fontSize: '0.95rem', display: 'flex', alignItems: 'center', gap: '8px' }}>
                                                    {otherUser.name}
                                                    {conv._count?.messages ? (
                                                        <span style={{
                                                            background: 'var(--primary)',
                                                            color: 'white',
                                                            fontSize: '0.7rem',
                                                            padding: '2px 6px',
                                                            borderRadius: '10px',
                                                            fontWeight: 'bold'
                                                        }}>
                                                            {conv._count.messages}
                                                        </span>
                                                    ) : null}
                                                </div>
                                                <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                                                    {lastMessage ? formatDistanceToNow(new Date(lastMessage.createdAt), { addSuffix: true, locale: tr }) : ''}
                                                </div>
                                            </div>

                                            {conv.ad && (
                                                <div style={{ fontSize: '0.75rem', color: 'var(--primary)', marginBottom: '0.25rem', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                                    İlan: {conv.ad.title}
                                                </div>
                                            )}

                                            <div style={{
                                                fontSize: '0.85rem',
                                                color: 'var(--text-secondary)',
                                                whiteSpace: 'nowrap',
                                                overflow: 'hidden',
                                                textOverflow: 'ellipsis'
                                            }}>
                                                {lastMessage ? (
                                                    <span>
                                                        {lastMessage.senderId === currentUserId ? 'Sen: ' : ''}
                                                        {lastMessage.content}
                                                    </span>
                                                ) : "Yeni sohbet"}
                                            </div>
                                        </div>
                                    );
                                })
                            )}
                        </div>
                    </div>
                )}

                {/* Sağ Panel: Mesaj İçeriği */}
                {showChat && (
                    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', width: isMobileView ? '100%' : 'auto' }}>
                        {activeConversationId && activeConversation ? (
                            <>
                                {/* Sohbet Başlığı */}
                                <div style={{
                                    padding: '1rem',
                                    borderBottom: '1px solid var(--border)',
                                    display: 'flex',
                                    alignItems: 'center',
                                    gap: '1rem',
                                    background: 'var(--bg-card)'
                                }}>
                                    {isMobileView && (
                                        <button
                                            onClick={() => setActiveConversationId(null)}
                                            className="btn btn-ghost"
                                            style={{ padding: '8px' }}
                                        >
                                            <ArrowLeft size={20} />
                                        </button>
                                    )}
                                    <div style={{ flex: 1 }}>
                                        <h3 style={{ fontSize: '1.1rem', fontWeight: 600, margin: 0 }}>
                                            {activeConversation.user1.id === currentUserId ? activeConversation.user2.name : activeConversation.user1.name}
                                        </h3>
                                    </div>
                                </div>

                                {/* İlan Banner Alanı */}
                                {activeConversation.ad && (
                                    <Link
                                        href={`/ad/${activeConversation.ad.id}`}
                                        style={{
                                            display: 'flex',
                                            alignItems: 'center',
                                            justifyContent: 'space-between',
                                            padding: '0.75rem 1rem',
                                            background: '#F4F7FA',
                                            borderBottom: '1px solid var(--border)',
                                            color: 'var(--primary)',
                                            textDecoration: 'none',
                                            transition: 'background 0.2s',
                                        }}
                                        className="hover:bg-primary-50"
                                    >
                                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', overflow: 'hidden' }}>
                                            <span style={{ fontSize: '1.2rem' }}>🏷️</span>
                                            <span style={{ fontWeight: 600, fontSize: '0.9rem', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                                İlan: {activeConversation.ad.title}
                                            </span>
                                        </div>
                                        <span style={{ fontSize: '1.2rem', color: 'var(--text-muted)' }}>↗</span>
                                    </Link>
                                )}

                                {/* Mesaj Listesi */}
                                <div style={{ flex: 1, overflowY: 'auto', padding: '1rem', display: 'flex', flexDirection: 'column', gap: '1rem', background: 'var(--bg-secondary)' }}>
                                    {messages.map((msg) => {
                                        const isMine = msg.senderId === currentUserId;
                                        return (
                                            <div key={msg.id} style={{
                                                alignSelf: isMine ? 'flex-end' : 'flex-start',
                                                maxWidth: '75%',
                                            }}>
                                                <div style={{
                                                    background: isMine ? 'var(--primary)' : 'var(--bg-card)',
                                                    color: isMine ? 'white' : 'var(--text-primary)',
                                                    padding: '0.75rem 1rem',
                                                    borderRadius: '1rem',
                                                    borderBottomRightRadius: isMine ? '0' : '1rem',
                                                    borderBottomLeftRadius: !isMine ? '0' : '1rem',
                                                    boxShadow: '0 2px 5px rgba(0,0,0,0.05)',
                                                    border: isMine ? 'none' : '1px solid var(--border)'
                                                }}>
                                                    {msg.content}
                                                </div>
                                                <div style={{
                                                    fontSize: '0.7rem',
                                                    color: 'var(--text-muted)',
                                                    marginTop: '0.25rem',
                                                    textAlign: isMine ? 'right' : 'left'
                                                }}>
                                                    {new Date(msg.createdAt).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })}
                                                </div>
                                            </div>
                                        );
                                    })}
                                    <div ref={messagesEndRef} />
                                </div>

                                {/* Mesaj Gönderme Formu */}
                                <div style={{ padding: '1rem', borderTop: '1px solid var(--border)', background: 'var(--bg-card)' }}>
                                    <form onSubmit={handleSendMessage} style={{ display: 'flex', gap: '0.5rem' }}>
                                        <input
                                            type="text"
                                            value={newMessage}
                                            onChange={(e) => setNewMessage(e.target.value)}
                                            placeholder="Bir mesaj yazın..."
                                            className="input"
                                            style={{ flex: 1 }}
                                        />
                                        <button
                                            type="submit"
                                            className="btn btn-primary"
                                            disabled={isSending || !newMessage.trim()}
                                            style={{ padding: '0 1.5rem' }}
                                        >
                                            {isSending ? "..." : <Send size={18} />}
                                        </button>
                                    </form>
                                </div>
                            </>
                        ) : (
                            <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-secondary)', flexDirection: 'column', gap: '1rem' }}>
                                <div style={{ fontSize: '3rem', opacity: 0.2 }}>💬</div>
                                <p>Sohbete başlamak için soldan bir kişi seçin.</p>
                            </div>
                        )}
                    </div>
                )
                }
            </div >
        </div >
    );
}

export default function MessagesPage() {
    return (
        <Suspense fallback={<div className="container" style={{ padding: '2rem 0', textAlign: 'center' }}>Yükleniyor...</div>}>
            <MessagesContent />
        </Suspense>
    );
}
