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
        <div className="max-w-6xl mx-auto p-4 sm:p-6">
            <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">Arkadaşlarım</h1>

            <div className="flex flex-col md:flex-row gap-8">

                {/* Sidebar: Lists */}
                <div className="w-full md:w-64 flex-shrink-0">
                    <div className="bg-white dark:bg-gray-800 rounded-2xl p-4 shadow-sm border border-gray-100 dark:border-gray-700">
                        <h2 className="font-semibold text-gray-600 dark:text-gray-300 text-sm uppercase tracking-wider mb-4">Listeler</h2>

                        <ul className="space-y-2 mb-6">
                            <li>
                                <button
                                    onClick={() => setSelectedList("all")}
                                    className={`w-full text-left px-4 py-2.5 rounded-xl text-sm font-medium transition-colors ${selectedList === "all" ? "bg-[var(--primary)] text-white shadow-md shadow-[var(--primary)]/20" : "text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"}`}
                                >
                                    Tüm Arkadaşlar ({friends.length})
                                </button>
                            </li>
                            {lists.map(list => (
                                <li key={list.id} className="group flex items-center">
                                    <button
                                        onClick={() => setSelectedList(list.id)}
                                        className={`flex-1 text-left px-4 py-2.5 rounded-l-xl text-sm font-medium transition-colors ${selectedList === list.id ? "bg-[var(--primary)] text-white shadow-md shadow-[var(--primary)]/20" : "text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"}`}
                                    >
                                        {list.name} ({friends.filter(f => f.friendListId === list.id).length})
                                    </button>
                                    <button
                                        onClick={() => handleDeleteList(list.id)}
                                        className={`px-3 py-2.5 rounded-r-xl transition-colors ${selectedList === list.id ? "bg-[var(--primary)] text-white opacity-80 hover:opacity-100" : "bg-gray-50 dark:bg-gray-800 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 opacity-0 group-hover:opacity-100"}`}
                                        title="Listeyi Sil"
                                    >
                                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 6h18"></path><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"></path><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"></path></svg>
                                    </button>
                                </li>
                            ))}
                        </ul>

                        {isCreatingList ? (
                            <form onSubmit={handleCreateList} className="space-y-3">
                                <input
                                    type="text"
                                    value={newListName}
                                    onChange={(e) => setNewListName(e.target.value)}
                                    placeholder="Liste adı (Örn: Güvenilir)"
                                    className="w-full bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-[var(--primary)]"
                                    autoFocus
                                />
                                <div className="flex gap-2">
                                    <button type="submit" disabled={actionLoading} className="flex-1 bg-[var(--primary)] text-white text-xs font-bold py-2 rounded-lg hover:opacity-90">Oluştur</button>
                                    <button type="button" onClick={() => setIsCreatingList(false)} className="flex-1 bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 text-xs font-bold py-2 rounded-lg hover:bg-gray-300 dark:hover:bg-gray-600">İptal</button>
                                </div>
                            </form>
                        ) : (
                            <button
                                onClick={() => setIsCreatingList(true)}
                                className="w-full flex items-center justify-center gap-2 py-2.5 border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-xl text-gray-500 hover:text-[var(--primary)] hover:border-[var(--primary)] hover:bg-[var(--primary)] hover:bg-opacity-5 transition-colors text-sm font-semibold"
                            >
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
                                Yeni Liste
                            </button>
                        )}
                    </div>
                </div>

                {/* Main Content: Friend Grid */}
                <div className="flex-1">
                    {displayedFriends.length === 0 ? (
                        <div className="bg-white dark:bg-gray-800 rounded-2xl p-12 text-center border border-gray-100 dark:border-gray-700">
                            <svg className="w-16 h-16 mx-auto text-gray-300 dark:text-gray-600 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.5" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
                            </svg>
                            <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-2">
                                {selectedList === "all" ? "Henüz kimseyi takip etmiyorsunuz" : "Bu listede kimse yok"}
                            </h3>
                            <p className="text-gray-500">İlan detaylarında veya satıcı profillerinde gördüğünüz kişileri takip ederek buraya ekleyebilirsiniz.</p>
                        </div>
                    ) : (
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                            {displayedFriends.map(friend => (
                                <div key={friend.id} className="bg-white dark:bg-gray-800 rounded-2xl p-5 shadow-sm border border-gray-100 dark:border-gray-700 flex flex-col sm:flex-row items-center sm:items-start gap-4 hover:shadow-md transition-shadow">

                                    <Link href={`/user/${friend.id}`} className="flex-shrink-0 relative w-16 h-16 rounded-full overflow-hidden bg-gray-100 dark:bg-gray-700 border-2 border-gray-200 dark:border-gray-600">
                                        {friend.avatar ? (
                                            <Image src={friend.avatar} alt={friend.name} fill className="object-cover" />
                                        ) : (
                                            <div className="w-full h-full flex items-center justify-center text-xl font-bold text-gray-400">
                                                {friend.name.charAt(0).toUpperCase()}
                                            </div>
                                        )}
                                    </Link>

                                    <div className="flex-1 text-center sm:text-left min-w-0 w-full">
                                        <Link href={`/user/${friend.id}`} className="block truncate text-lg font-bold text-gray-900 dark:text-white hover:text-[var(--primary)] transition-colors">
                                            {friend.name}
                                        </Link>

                                        <div className="mt-2 mb-4 flex flex-col sm:flex-row items-center gap-2">
                                            <select
                                                value={friend.friendListId || "null"}
                                                onChange={(e) => handleAssignToList(friend.id, e.target.value)}
                                                className="text-xs bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded-full px-3 py-1.5 focus:outline-none focus:border-[var(--primary)] text-gray-700 dark:text-gray-300 w-full sm:w-auto"
                                            >
                                                <option value="null">⭐ Listesiz</option>
                                                {lists.map(l => (
                                                    <option key={l.id} value={l.id}>{l.name}</option>
                                                ))}
                                            </select>
                                        </div>

                                        <div className="flex flex-col sm:flex-row w-full gap-2">
                                            <button
                                                onClick={() => handleMessage(friend.id)}
                                                disabled={actionLoading}
                                                className="flex-1 bg-gray-100 dark:bg-gray-700 hover:bg-[var(--primary)] hover:text-white text-gray-800 dark:text-gray-200 text-xs font-bold py-2 px-4 rounded-lg transition-colors flex items-center justify-center gap-2"
                                            >
                                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path></svg>
                                                Mesaj
                                            </button>
                                            <button
                                                onClick={() => handleUnfollow(friend.id)}
                                                disabled={actionLoading}
                                                className="sm:w-10 flex-shrink-0 bg-red-50 hover:bg-red-500 text-red-500 hover:text-white dark:bg-red-900/20 dark:hover:bg-red-500 flex items-center justify-center rounded-lg transition-colors py-2"
                                                title="Takipten Çıkar"
                                            >
                                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H5c-1 0-2 1-2 2v2"></path><circle cx="8.5" cy="7" r="4"></circle><line x1="23" y1="11" x2="17" y2="11"></line></svg>
                                            </button>
                                        </div>
                                    </div>

                                </div>
                            ))}
                        </div>
                    )}
                </div>

            </div>
        </div>
    );
}
