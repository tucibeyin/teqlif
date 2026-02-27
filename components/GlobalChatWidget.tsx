"use client";

import { useState, useEffect, useRef, useCallback } from 'react';
import { useSession } from 'next-auth/react';
import { MessageCircle, X, Send, Minus } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { tr } from 'date-fns/locale';

interface User { id: string; name: string; avatar: string | null; }
interface Message { id: string; content: string; createdAt: string; senderId: string; }
interface Conversation { id: string; user1: User; user2: User; ad: { title: string } | null; messages: Message[]; _count?: { messages: number }; }

export function GlobalChatWidget() {
    const { data: session } = useSession();
    const [isOpen, setIsOpen] = useState(false);
    const [isMinimized, setIsMinimized] = useState(false);
    const [conversations, setConversations] = useState<Conversation[]>([]);
    const [activeConvId, setActiveConvId] = useState<string | null>(null);
    const [messages, setMessages] = useState<Message[]>([]);
    const [newMessage, setNewMessage] = useState("");
    const [unreadTotal, setUnreadTotal] = useState(0);

    const messagesEndRef = useRef<HTMLDivElement>(null);
    const widgetRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        const handleClickOutside = (event: MouseEvent) => {
            if (widgetRef.current && !widgetRef.current.contains(event.target as Node)) {
                setIsOpen(false);
            }
        };

        if (isOpen) {
            document.addEventListener('mousedown', handleClickOutside);
        }
        return () => {
            document.removeEventListener('mousedown', handleClickOutside);
        };
    }, [isOpen]);

    const fetchConversations = useCallback(async () => {
        try {
            const res = await fetch('/api/conversations');
            if (res.ok) {
                const data = await res.json();
                setConversations(data);

                const unread = data.reduce((acc: number, c: any) => acc + (c._count?.messages || 0), 0);
                setUnreadTotal(unread);
            }
        } catch (error) {
            console.error('Failed to fetch conversations:', error);
        }
    }, [session?.user?.id]);

    useEffect(() => {
        let mounted = true;
        if (!session?.user) return;

        const load = async () => {
            if (mounted) await fetchConversations();
        };
        load();

        const interval = setInterval(() => {
            if (mounted) fetchConversations();
        }, 10000);

        const handleMessagesRead = () => {
            if (mounted) fetchConversations();
        };
        typeof window !== 'undefined' && window.addEventListener('messagesRead', handleMessagesRead);

        return () => {
            mounted = false;
            clearInterval(interval);
            typeof window !== 'undefined' && window.removeEventListener('messagesRead', handleMessagesRead);
        };
    }, [session, fetchConversations]);

    const fetchMessages = useCallback(async (convId: string, refreshConversations = false) => {
        try {
            const isTabFocused = typeof document !== 'undefined' && document.hasFocus();
            const shouldMarkAsRead = isTabFocused && isOpen && !isMinimized;

            const res = await fetch(`/api/messages?conversationId=${convId}&read=${shouldMarkAsRead}`);
            if (res.ok) {
                const data = await res.json();
                setMessages(data);
                if (refreshConversations) {
                    fetchConversations();
                }
                setTimeout(() => {
                    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
                }, 100);

                if (shouldMarkAsRead) {
                    typeof window !== 'undefined' && window.dispatchEvent(new Event('messagesRead'));
                }
            }
        } catch (error) {
            console.error(error);
        }
    }, [isOpen, isMinimized, fetchConversations]);

    useEffect(() => {
        let mounted = true;
        let interval: NodeJS.Timeout;

        const loadMessages = async () => {
            if (mounted && activeConvId) await fetchMessages(activeConvId, true);
        };

        if (isOpen && !isMinimized && activeConvId) {
            loadMessages();

            const handleFocus = () => {
                if (mounted && activeConvId) fetchMessages(activeConvId);
            };
            window.addEventListener('focus', handleFocus);

            interval = setInterval(() => {
                if (mounted && activeConvId) fetchMessages(activeConvId);
            }, 5000); // Polling interval

            return () => {
                mounted = false;
                if (interval) clearInterval(interval);
                window.removeEventListener('focus', handleFocus);
            };
        }
    }, [isOpen, isMinimized, activeConvId, fetchMessages]);

    const handleSend = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!newMessage.trim() || !activeConvId || !session?.user) return;

        const conv = conversations.find(c => c.id === activeConvId);
        if (!conv) return;

        const currentUserId = (session.user as any).id;
        const recipientId = conv.user1.id === currentUserId ? conv.user2.id : conv.user1.id;

        try {
            const res = await fetch('/api/messages', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ conversationId: activeConvId, content: newMessage, recipientId })
            });

            if (res.ok) {
                setNewMessage("");
                fetchMessages(activeConvId);
                fetchConversations();
            }
        } catch (e) {
            console.error(e);
        }
    };

    if (!session?.user) return null;

    const currentUserId = (session.user as any).id;

    return (
        <div ref={widgetRef} style={{
            position: 'fixed',
            bottom: '20px',
            right: '20px',
            zIndex: 1000,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'flex-end'
        }}>
            {/* Main Toggle Button */}
            {!isOpen && (
                <button
                    onClick={() => { setIsOpen(true); setIsMinimized(false); }}
                    style={{
                        width: '60px',
                        height: '60px',
                        borderRadius: '50%',
                        background: 'var(--primary)',
                        color: 'white',
                        border: 'none',
                        boxShadow: '0 4px 15px rgba(0, 188, 212, 0.4)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        cursor: 'pointer',
                        transition: 'transform 0.2s',
                    }}
                    onMouseEnter={(e) => e.currentTarget.style.transform = 'scale(1.05)'}
                    onMouseLeave={(e) => e.currentTarget.style.transform = 'scale(1)'}
                >
                    <MessageCircle size={30} />
                    {unreadTotal > 0 && (
                        <span style={{
                            position: 'absolute',
                            top: '-5px',
                            right: '-5px',
                            background: '#ef4444', // explicitly red to avoid transparency issues
                            color: 'white',
                            fontSize: '11px',
                            fontWeight: 'bold',
                            width: '24px',
                            height: '24px',
                            borderRadius: '50%',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            boxShadow: '0 2px 4px rgba(0,0,0,0.2)'
                        }}>
                            {unreadTotal > 9 ? '9+' : unreadTotal}
                        </span>
                    )}
                </button>
            )}

            {/* Chat Panel */}
            {isOpen && (
                <div style={{
                    width: 'min(350px, calc(100vw - 40px))',
                    height: isMinimized ? '50px' : '500px',
                    maxHeight: 'calc(100vh - 40px)',
                    background: 'var(--bg-card)',
                    borderRadius: '1rem',
                    boxShadow: '0 10px 30px rgba(0,0,0,0.15)',
                    border: '1px solid var(--border)',
                    display: 'flex',
                    flexDirection: 'column',
                    overflow: 'hidden',
                    transition: 'height 0.3s ease'
                }}>
                    {/* Header */}
                    <div style={{
                        background: 'var(--primary)',
                        color: 'white',
                        padding: '12px 16px',
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        cursor: 'pointer'
                    }} onClick={() => setIsMinimized(!isMinimized)}>
                        <h4 style={{ margin: 0, fontWeight: 600, fontSize: '1rem' }}>
                            {activeConvId && !isMinimized ? (
                                <button
                                    onClick={(e) => { e.stopPropagation(); setActiveConvId(null); fetchConversations(); }}
                                    style={{ background: 'none', border: 'none', color: 'white', cursor: 'pointer', marginRight: '8px', padding: 0 }}
                                >
                                    &larr;
                                </button>
                            ) : null}
                            Mesajlar
                        </h4>
                        <div style={{ display: 'flex', gap: '8px' }}>
                            <button
                                onClick={(e) => { e.stopPropagation(); setIsMinimized(!isMinimized); }}
                                style={{ background: 'none', border: 'none', color: 'white', cursor: 'pointer', padding: 0 }}
                            >
                                <Minus size={18} />
                            </button>
                            <button
                                onClick={(e) => { e.stopPropagation(); setIsOpen(false); }}
                                style={{ background: 'none', border: 'none', color: 'white', cursor: 'pointer', padding: 0 }}
                            >
                                <X size={18} />
                            </button>
                        </div>
                    </div>

                    {/* Content */}
                    {!isMinimized && (
                        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
                            {!activeConvId ? (
                                // Conversation List
                                <div style={{ flex: 1, overflowY: 'auto' }}>
                                    {conversations.length === 0 ? (
                                        <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-secondary)' }}>
                                            Sohbet bulunamadı.
                                        </div>
                                    ) : (
                                        conversations.map(conv => {
                                            const otherUser = conv.user1.id === currentUserId ? conv.user2 : conv.user1;
                                            const lastMessage = conv.messages[0];
                                            return (
                                                <div
                                                    key={conv.id}
                                                    onClick={() => setActiveConvId(conv.id)}
                                                    style={{
                                                        padding: '12px 16px',
                                                        borderBottom: '1px solid var(--border)',
                                                        cursor: 'pointer',
                                                    }}
                                                    className="hover:bg-primary-50"
                                                >
                                                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                                                        <p className="text-secondary" style={{ fontSize: '0.9rem', marginBottom: '16px' }}>Bu ilan için satıcı ile görüşebilirsiniz.</p>
                                                        <span style={{ fontWeight: 600, fontSize: '0.9rem', display: 'flex', alignItems: 'center', gap: '8px' }}>
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
                                                        </span>
                                                        <span style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>
                                                            {lastMessage && formatDistanceToNow(new Date(lastMessage.createdAt), { addSuffix: true, locale: tr })}
                                                        </span>
                                                    </div>
                                                    <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                                        {lastMessage ? lastMessage.content : "Yeni mesaj gönder"}
                                                    </div>
                                                </div>
                                            );
                                        })
                                    )}
                                </div>
                            ) : (
                                // Active Conversation
                                <>
                                    <div style={{ flex: 1, overflowY: 'auto', padding: '16px', background: 'var(--bg-secondary)', display: 'flex', flexDirection: 'column', gap: '8px' }}>
                                        {messages.map((msg) => {
                                            const isMine = msg.senderId === currentUserId;
                                            return (
                                                <div key={msg.id} style={{
                                                    alignSelf: isMine ? 'flex-end' : 'flex-start',
                                                    maxWidth: '85%',
                                                    background: isMine ? 'var(--primary)' : 'var(--bg-card)',
                                                    color: isMine ? 'white' : 'var(--text-primary)',
                                                    padding: '8px 12px',
                                                    borderRadius: '12px',
                                                    borderBottomRightRadius: isMine ? '2px' : '12px',
                                                    borderBottomLeftRadius: !isMine ? '2px' : '12px',
                                                    fontSize: '0.9rem',
                                                    border: isMine ? 'none' : '1px solid var(--border)'
                                                }}>
                                                    {msg.content}
                                                </div>
                                            );
                                        })}
                                        <div ref={messagesEndRef} />
                                    </div>
                                    <form onSubmit={handleSend} style={{ display: 'flex', padding: '12px', borderTop: '1px solid var(--border)', background: 'var(--bg-card)' }}>
                                        <input
                                            type="text"
                                            value={newMessage}
                                            onChange={(e) => setNewMessage(e.target.value)}
                                            placeholder="Mesaj yaz..."
                                            style={{
                                                flex: 1,
                                                padding: '8px 12px',
                                                border: '1px solid var(--border)',
                                                borderRadius: '20px',
                                                outline: 'none',
                                                background: 'var(--bg-secondary)',
                                                color: 'var(--text-primary)'
                                            }}
                                        />
                                        <button
                                            type="submit"
                                            disabled={!newMessage.trim()}
                                            style={{
                                                background: 'none',
                                                border: 'none',
                                                color: newMessage.trim() ? 'var(--primary)' : 'var(--text-muted)',
                                                padding: '0 8px',
                                                cursor: newMessage.trim() ? 'pointer' : 'default',
                                                display: 'flex',
                                                alignItems: 'center'
                                            }}
                                        >
                                            <Send size={20} />
                                        </button>
                                    </form>
                                </>
                            )}
                        </div>
                    )}
                </div>
            )}
        </div>
    );
}
