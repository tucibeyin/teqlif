import Link from "next/link";
import { auth, signOut } from "@/auth";
import { NotificationBell } from "./NotificationBell";
import { MessageBell } from "./MessageBell";

export async function Navbar() {
    const session = await auth();

    return (
        <nav className="navbar">
            <div className="container">
                <div className="navbar-inner">
                    <Link href="/" className="navbar-logo">
                        teqlif
                    </Link>

                    <div className="navbar-search search-input-wrap">
                        <span className="search-icon">
                            <svg width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24">
                                <circle cx="11" cy="11" r="8" /><path d="m21 21-4.35-4.35" />
                            </svg>
                        </span>
                        <input
                            type="search"
                            className="input"
                            placeholder="İlan ara..."
                            id="search-input"
                        />
                    </div>

                    <div className="navbar-actions">
                        {session?.user ? (
                            <>
                                <Link href="/post-ad" className="btn btn-primary btn-sm">
                                    + İlan Ver
                                </Link>
                                <NotificationBell />
                                <Link href="/dashboard" className="btn btn-ghost btn-sm">
                                    Panelim
                                </Link>
                                <MessageBell />
                                <form action={async () => {
                                    "use server";
                                    await signOut({ redirectTo: "/" });
                                }}>
                                    <button type="submit" className="btn btn-ghost btn-sm">
                                        Çıkış
                                    </button>
                                </form>
                            </>
                        ) : (
                            <>
                                <Link href="/login" className="btn btn-ghost btn-sm">
                                    Giriş Yap
                                </Link>
                                <Link href="/register" className="btn btn-primary btn-sm">
                                    Üye Ol
                                </Link>
                            </>
                        )}
                    </div>
                </div>
            </div>
        </nav>
    );
}
