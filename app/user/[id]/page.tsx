"use client";

import { useState, useEffect } from "react";
import { useParams, useRouter } from "next/navigation";
import Image from "next/image";
import Link from "next/link";
import { useSession } from "next-auth/react";
import { Navbar } from "@/components/Navbar";

export default function UserProfilePage() {
    const { id } = useParams();
    const router = useRouter();
    const { data: session } = useSession();

    const [loading, setLoading] = useState(true);
    const [actionLoading, setActionLoading] = useState(false);
    const [user, setUser] = useState<any>(null);
    const [ads, setAds] = useState<any[]>([]);
    const [connectionStatus, setConnectionStatus] = useState<"NONE" | "FRIEND" | "SELF">("NONE");

    useEffect(() => {
        const fetchProfile = async () => {
            try {
                const res = await fetch(`/api/users/${id}`);
                const data = await res.json();

                if (res.ok) {
                    setUser(data.user);
                    setAds(data.ads);
                    setConnectionStatus(data.connectionStatus);
                } else {
                    alert(data.error || "Kullanıcı bulunamadı.");
                    router.push("/");
                }
            } catch (e) {
                console.error("Profile fetch error:", e);
                alert("Bir hata oluştu.");
            } finally {
                setLoading(false);
            }
        };

        if (id) fetchProfile();
    }, [id, router]);

    const handleFollowToggle = async () => {
        if (!session) {
            router.push("/login");
            return;
        }

        setActionLoading(true);
        try {
            if (connectionStatus === "FRIEND") {
                const res = await fetch(`/api/users/friends/${id}`, { method: "DELETE" });
                if (res.ok) setConnectionStatus("NONE");
            } else {
                const res = await fetch(`/api/users/friends`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ targetUserId: id })
                });
                if (res.ok) setConnectionStatus("FRIEND");
            }
        } catch (e) {
            console.error("Follow error:", e);
        } finally {
            setActionLoading(false);
        }
    };

    const handleMessage = async () => {
        if (!session) {
            router.push("/login");
            return;
        }

        setActionLoading(true);
        try {
            const res = await fetch("/api/conversations", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ userId: id })
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

    if (loading) {
        return (
            <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
                <Navbar />
                <div className="flex items-center justify-center h-[60vh]">
                    <div className="w-12 h-12 border-4 border-[var(--primary)] border-t-transparent rounded-full animate-spin"></div>
                </div>
            </div>
        );
    }

    if (!user) return null;

    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
            <Navbar />

            <main className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8">

                {/* Profile Header */}
                <div className="bg-white dark:bg-gray-800 rounded-2xl shadow-sm border border-gray-100 dark:border-gray-700 p-8 mb-8">
                    <div className="flex flex-col md:flex-row items-center md:items-start gap-8">

                        {/* Avatar */}
                        <div className="flex-shrink-0 relative w-32 h-32 rounded-full overflow-hidden border-4 border-gray-50 dark:border-gray-700 shadow-md bg-gray-100 dark:bg-gray-800 flex justify-center items-center">
                            {user.avatar ? (
                                <Image src={user.avatar} alt={user.name} fill className="object-cover" />
                            ) : (
                                <span className="text-4xl font-bold text-gray-500">{user.name.charAt(0).toUpperCase()}</span>
                            )}
                        </div>

                        {/* Info */}
                        <div className="flex-1 text-center md:text-left">
                            <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">{user.name}</h1>
                            <p className="text-gray-500 dark:text-gray-400 mb-4">
                                Teqlif Üyesi • {new Date(user.createdAt).toLocaleDateString("tr-TR", { year: 'numeric', month: 'long' })} tarihinden beri
                            </p>

                            {user.phone && (
                                <div className="inline-flex items-center px-4 py-2 bg-gray-100 dark:bg-gray-700 rounded-full text-gray-700 dark:text-gray-300 font-medium text-sm mb-6">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="mr-2"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"></path></svg>
                                    {user.phone}
                                </div>
                            )}

                            {/* Actions */}
                            {connectionStatus !== "SELF" && (
                                <div className="flex flex-wrap justify-center md:justify-start gap-4">
                                    <button
                                        onClick={handleFollowToggle}
                                        disabled={actionLoading}
                                        className={`px-6 py-2.5 rounded-xl font-bold transition-all ${connectionStatus === "FRIEND"
                                            ? "bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200 hover:bg-gray-200"
                                            : "bg-[var(--primary)] text-white hover:opacity-90 shadow-md shadow-[var(--primary)]/30"
                                            }`}
                                    >
                                        {actionLoading ? "İşleniyor..." : connectionStatus === "FRIEND" ? "Takipten Çık" : "Takip Et / Ekle"}
                                    </button>

                                    <button
                                        onClick={handleMessage}
                                        disabled={actionLoading}
                                        className="px-6 py-2.5 rounded-xl font-bold bg-white dark:bg-gray-800 border-2 border-[var(--primary)] text-[var(--primary)] hover:bg-[var(--primary)] hover:text-white transition-all shadow-sm"
                                    >
                                        Mesaj Gönder
                                    </button>
                                </div>
                            )}
                        </div>

                        {/* Stats box */}
                        <div className="flex gap-6 p-6 bg-gray-50 dark:bg-gray-900 rounded-2xl border border-gray-100 dark:border-gray-700">
                            <div className="text-center">
                                <div className="text-2xl font-black text-gray-900 dark:text-white tabular-nums">{user.stats.activeAds}</div>
                                <div className="text-xs font-semibold text-gray-500 uppercase tracking-wider mt-1">Aktif İlan</div>
                            </div>
                            <div className="w-px bg-gray-200 dark:bg-gray-700"></div>
                            <div className="text-center">
                                <div className="text-2xl font-black text-gray-900 dark:text-white tabular-nums">{user.stats.followers}</div>
                                <div className="text-xs font-semibold text-gray-500 uppercase tracking-wider mt-1">Takipçi</div>
                            </div>
                        </div>

                    </div>
                </div>

                {/* Ads Section */}
                <div>
                    <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">Kullanıcının İlanları</h2>

                    {ads.length === 0 ? (
                        <div className="bg-white dark:bg-gray-800 rounded-2xl p-12 text-center border border-gray-100 dark:border-gray-700">
                            <svg className="w-16 h-16 mx-auto text-gray-300 dark:text-gray-600 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.5" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                            </svg>
                            <p className="text-gray-500 text-lg">Bu kullanıcının henüz aktif bir ilanı bulunmuyor.</p>
                        </div>
                    ) : (
                        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
                            {ads.map((ad: any) => (
                                <Link
                                    href={`/ad/${ad.id}`}
                                    key={ad.id}
                                    className="group bg-white dark:bg-gray-800 rounded-2xl overflow-hidden border border-gray-100 dark:border-gray-700 shadow-sm hover:shadow-lg transition-all duration-300 flex flex-col"
                                >
                                    <div className="relative aspect-[4/3] bg-gray-100 dark:bg-gray-900 overflow-hidden">
                                        {ad.images && ad.images.length > 0 ? (
                                            <Image
                                                src={ad.images[0]}
                                                alt={ad.title}
                                                fill
                                                className="object-cover group-hover:scale-105 transition-transform duration-500"
                                            />
                                        ) : (
                                            <div className="absolute inset-0 flex items-center justify-center text-gray-400">Görsel Yok</div>
                                        )}
                                        {/* Status Badge */}
                                        <div className="absolute top-3 right-3 bg-white/90 dark:bg-gray-800/90 backdrop-blur-sm px-3 py-1 rounded-full text-xs font-bold shadow-sm">
                                            {ad.isAuction ? (
                                                <span className="text-orange-500 flex items-center gap-1">
                                                    <span className="w-2 h-2 rounded-full bg-orange-500 animate-pulse"></span>
                                                    Açık Arttırma
                                                </span>
                                            ) : (
                                                <span className="text-blue-500">Sabit Fiyat</span>
                                            )}
                                        </div>
                                    </div>

                                    <div className="p-4 flex flex-col flex-grow">
                                        <h3 className="font-semibold text-gray-900 dark:text-white line-clamp-2 mb-2 group-hover:text-[var(--primary)] transition-colors">
                                            {ad.title}
                                        </h3>
                                        <div className="mt-auto pt-4 border-t border-gray-100 dark:border-gray-700 flex justify-between items-end">
                                            <div className="text-sm text-gray-500 dark:text-gray-400">
                                                {ad.province?.name} / {ad.district?.name}
                                            </div>
                                            <div className="text-lg font-black text-gray-900 dark:text-white">
                                                {new Intl.NumberFormat("tr-TR").format(ad.price)} ₺
                                            </div>
                                        </div>
                                    </div>
                                </Link>
                            ))}
                        </div>
                    )}
                </div>

            </main>
        </div>
    );
}
