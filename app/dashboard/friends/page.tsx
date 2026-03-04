"use client";

import { useState, useEffect } from "react";
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";

export default function FriendsDashboard() {
    const router = useRouter();
    const [loading, setLoading] = useState(true);
    const [friends, setFriends] = useState<any[]>([]);
    const [lists, setLists] = useState<any[]>([]);
    const [selectedList, setSelectedList] = useState<string>("all");
    const [newListName, setNewListName] = useState("");
    const [isCreatingList, setIsCreatingList] = useState(false);
    const [actionLoading, setActionLoading] = useState(false);

    useEffect(() => {
        fetchFriendsData();
    }, []);

    const fetchFriendsData = async () => {
        try {
            const res = await fetch("/api/users/friends");
            const data = await res.json();
            if (res.ok) {
                setFriends(data.friends || []);
                setLists(data.customLists || []);
            }
        } catch (e) {
            console.error("Failed to fetch friends", e);
        } finally {
            setLoading(false);
        }
    };

    const handleCreateList = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!newListName.trim()) return;

        setActionLoading(true);
        try {
            const res = await fetch("/api/users/friend-lists", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ name: newListName })
            });
            if (res.ok) {
                setNewListName("");
                setIsCreatingList(false);
                fetchFriendsData(); // refresh lists
            } else {
                const data = await res.json();
                alert(data.error || "Liste oluşturulamadı");
            }
        } catch (e) {
            console.error("Create list error", e);
        } finally {
            setActionLoading(false);
        }
    };

    const handleDeleteList = async (listId: string) => {
        if (!confirm("Bu listeyi silmek istediğinize emin misiniz? (İçindeki kişiler takipten çıkmaz, sadece listesiz kalırlar)")) return;

        setActionLoading(true);
        try {
            const res = await fetch(`/api/users/friend-lists/${listId}`, { method: "DELETE" });
            if (res.ok) {
                if (selectedList === listId) setSelectedList("all");
                fetchFriendsData();
            }
        } catch (e) {
            console.error("Delete list error", e);
        } finally {
            setActionLoading(false);
        }
    };

    const handleAssignToList = async (friendId: string, listId: string) => {
        try {
            const res = await fetch(`/api/users/friend-lists/${listId}`, {
                method: "PATCH",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ friendId })
            });
            if (res.ok) {
                fetchFriendsData(); // refresh UI
            }
        } catch (e) {
            console.error("Assign list error", e);
        }
    };

    const handleUnfollow = async (friendId: string) => {
        if (!confirm("Takipten çıkarmak istediğinize emin misiniz?")) return;

        setActionLoading(true);
        try {
            const res = await fetch(`/api/users/friends/${friendId}`, { method: "DELETE" });
            if (res.ok) fetchFriendsData();
        } catch (e) {
            console.error("Unfollow error", e);
        } finally {
            setActionLoading(false);
        }
    };

    const handleMessage = async (userId: string) => {
        setActionLoading(true);
        try {
            const res = await fetch("/api/conversations", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ userId })
            });
            if (res.ok) {
                const conversation = await res.json();
                router.push(`/dashboard/messages?id=${conversation.id}`);
            }
        } catch (e) {
            console.error("Message initiation error", e);
        } finally {
            setActionLoading(false);
        }
    };

    const displayedFriends = selectedList === "all"
        ? friends
        : friends.filter(f => f.friendListId === selectedList);

    if (loading) {
        return <div className="p-8 flex justify-center"><div className="animate-spin w-8 h-8 border-4 border-t-transparent border-[var(--primary)] rounded-full"></div></div>;
    }

    return (
        <div className="dashboard">
            <div className="container">
                <div className="dashboard-header">
                    <h1 className="dashboard-name">Arkadaşlarım</h1>
                </div>

                <div style={{ display: 'flex', gap: '2rem', flexWrap: 'wrap', alignItems: 'flex-start' }}>

                    {/* Sidebar: Lists */}
                    <div className="card" style={{ width: '100%', maxWidth: '280px', flexShrink: 0 }}>
                        <div className="card-body">
                            <h2 style={{ fontSize: '0.875rem', fontWeight: 700, color: 'var(--text-secondary)', textTransform: 'uppercase', marginBottom: '1rem' }}>
                                Listeler
                            </h2>

                            <ul style={{ listStyle: 'none', padding: 0, margin: '0 0 1.5rem 0', display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                                <li>
                                    <button
                                        onClick={() => setSelectedList("all")}
                                        style={{
                                            width: '100%', textAlign: 'left', padding: '0.75rem 1rem', borderRadius: 'var(--radius-md)', border: 'none', cursor: 'pointer',
                                            fontWeight: 600, fontSize: '0.9375rem',
                                            background: selectedList === "all" ? 'var(--primary-100)' : 'transparent',
                                            color: selectedList === "all" ? 'var(--primary-dark)' : 'var(--text-primary)'
                                        }}
                                    >
                                        Tüm Arkadaşlar ({friends.length})
                                    </button>
                                </li>
                                {lists.map(list => (
                                    <li key={list.id} style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
                                        <button
                                            onClick={() => setSelectedList(list.id)}
                                            style={{
                                                flex: 1, textAlign: 'left', padding: '0.75rem 1rem', borderRadius: 'var(--radius-md)', border: 'none', cursor: 'pointer',
                                                fontWeight: 600, fontSize: '0.9375rem',
                                                background: selectedList === list.id ? 'var(--primary-100)' : 'transparent',
                                                color: selectedList === list.id ? 'var(--primary-dark)' : 'var(--text-primary)'
                                            }}
                                        >
                                            {list.name} ({friends.filter(f => f.friendListId === list.id).length})
                                        </button>
                                        <button
                                            onClick={() => handleDeleteList(list.id)}
                                            style={{
                                                padding: '0.5rem', background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--accent-red)', opacity: selectedList === list.id ? 1 : 0.6
                                            }}
                                            title="Listeyi Sil"
                                        >
                                            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 6h18"></path><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"></path><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"></path></svg>
                                        </button>
                                    </li>
                                ))}
                            </ul>

                            {isCreatingList ? (
                                <form onSubmit={handleCreateList} style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                                    <input
                                        type="text"
                                        value={newListName}
                                        onChange={(e) => setNewListName(e.target.value)}
                                        placeholder="Liste adı (Örn: Güvenilir)"
                                        className="input"
                                        autoFocus
                                    />
                                    <div style={{ display: 'flex', gap: '0.5rem' }}>
                                        <button type="submit" disabled={actionLoading} className="btn btn-primary btn-sm" style={{ flex: 1 }}>Oluştur</button>
                                        <button type="button" onClick={() => setIsCreatingList(false)} className="btn btn-secondary btn-sm" style={{ flex: 1 }}>İptal</button>
                                    </div>
                                </form>
                            ) : (
                                <button
                                    onClick={() => setIsCreatingList(true)}
                                    className="btn btn-outline btn-full"
                                    style={{ borderStyle: 'dashed' }}
                                >
                                    + Yeni Liste
                                </button>
                            )}
                        </div>
                    </div>

                    {/* Main Content: Friend Grid */}
                    <div style={{ flex: 1, minWidth: '300px' }}>
                        {displayedFriends.length === 0 ? (
                            <div className="card text-center" style={{ padding: '4rem 2rem' }}>
                                <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>👥</div>
                                <h3 style={{ fontSize: '1.25rem', fontWeight: 700, marginBottom: '0.5rem' }}>
                                    {selectedList === "all" ? "Henüz kimseyi takip etmiyorsunuz" : "Bu listede kimse yok"}
                                </h3>
                                <p style={{ color: 'var(--text-muted)' }}>İlan detaylarında veya satıcı profillerinde gördüğünüz kişileri takip ederek buraya ekleyebilirsiniz.</p>
                            </div>
                        ) : (
                            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: '1rem' }}>
                                {displayedFriends.map(friend => (
                                    <div key={friend.id} className="card">
                                        <div className="card-body" style={{ display: 'flex', gap: '1rem', alignItems: 'flex-start' }}>

                                            <Link href={`/user/${friend.id}`} style={{ flexShrink: 0, width: '64px', height: '64px', borderRadius: '50%', overflow: 'hidden', backgroundColor: 'var(--primary-50)', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '2px solid var(--border)' }}>
                                                {friend.avatar ? (
                                                    <Image src={friend.avatar} alt={friend.name} width={64} height={64} style={{ objectFit: 'cover' }} />
                                                ) : (
                                                    <span style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--primary)' }}>
                                                        {friend.name.charAt(0).toUpperCase()}
                                                    </span>
                                                )}
                                            </Link>

                                            <div style={{ flex: 1, minWidth: 0 }}>
                                                <Link href={`/user/${friend.id}`} style={{ display: 'block', fontSize: '1.125rem', fontWeight: 700, color: 'var(--text-primary)', marginBottom: '0.25rem', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                                    {friend.name}
                                                </Link>

                                                <div style={{ marginBottom: '1rem' }}>
                                                    <select
                                                        value={friend.friendListId || "null"}
                                                        onChange={(e) => handleAssignToList(friend.id, e.target.value)}
                                                        className="input"
                                                        style={{ padding: '0.375rem 2rem 0.375rem 0.75rem', fontSize: '0.8125rem', borderRadius: 'var(--radius-full)', backgroundPosition: 'right 0.5rem center' }}
                                                    >
                                                        <option value="null">⭐ Listesiz</option>
                                                        {lists.map(l => (
                                                            <option key={l.id} value={l.id}>{l.name}</option>
                                                        ))}
                                                    </select>
                                                </div>

                                                <div style={{ display: 'flex', gap: '0.5rem' }}>
                                                    <button
                                                        onClick={() => handleMessage(friend.id)}
                                                        disabled={actionLoading}
                                                        className="btn btn-secondary btn-sm"
                                                        style={{ flex: 1 }}
                                                    >
                                                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path></svg>
                                                        Mesaj
                                                    </button>
                                                    <button
                                                        onClick={() => handleUnfollow(friend.id)}
                                                        disabled={actionLoading}
                                                        className="btn btn-sm"
                                                        style={{ background: 'var(--bg)', color: 'var(--accent-red)', border: '1px solid var(--accent-red)', padding: '0 0.5rem' }}
                                                        title="Takipten Çıkar"
                                                    >
                                                        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H5c-1 0-2 1-2 2v2"></path><circle cx="8.5" cy="7" r="4"></circle><line x1="23" y1="11" x2="17" y2="11"></line></svg>
                                                    </button>
                                                </div>
                                            </div>

                                        </div>
                                    </div>
                                ))}
                            </div>
                        )}
                    </div>
                </div>
            </div>
        </div>
    );
}
