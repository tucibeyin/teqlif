import Link from "next/link";
import { auth } from "@/auth";
import { handleSignOut } from "@/app/actions/auth";
import { NotificationBell } from "./NotificationBell";
import { MessageBell } from "./MessageBell";
import { LiveSearch } from "./LiveSearch";
import { LogoutButton } from "./LogoutButton";
import { QuickLiveButton } from "./QuickLiveButton";

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
                                <QuickLiveButton />
                                <Link href="/post-ad" className="btn btn-primary btn-sm hidden md:flex">
                                    + İlan Ver
                                </Link>
                                <NotificationBell />
                                <Link href="/dashboard" className="btn btn-ghost btn-sm">
                                    Hesabım
                                </Link>
                                <MessageBell />
                                <LogoutButton onLogout={handleSignOut} />
                                <Link href="/support" className="btn btn-ghost btn-sm hidden md:flex text-[var(--primary)]">
                                    Destek
                                </Link>
                            </>
                        ) : (
                            <>
                                <Link href="/login" className="btn btn-ghost btn-sm">
                                    Giriş Yap
                                </Link>
                                <Link href="/register" className="btn btn-primary btn-sm">
                                    Üye Ol
                                </Link>
                                <Link href="/support" className="btn btn-ghost btn-sm hidden md:flex">
                                    Destek
                                </Link>
                            </>
                        )}
                    </div>
                </div>
            </div>
        </nav>
    );
}
