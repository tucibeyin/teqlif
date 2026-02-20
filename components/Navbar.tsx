import Link from "next/link";
import { auth, signOut } from "@/auth";
import { NotificationBell } from "./NotificationBell";
import { MessageBell } from "./MessageBell";
import { LiveSearch } from "./LiveSearch";

export async function Navbar() {
    const session = await auth();

    return (
        <nav className="navbar">
            <div className="container">
                <div className="navbar-inner">
                    <Link href="/" className="navbar-logo">
                        teqlif
                    </Link>

                    <LiveSearch />

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
