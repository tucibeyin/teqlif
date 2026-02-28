"use client";

import React from "react";

interface LogoutButtonProps {
    onLogout: () => Promise<void>;
}

export function LogoutButton({ onLogout }: LogoutButtonProps) {
    const handleLogout = async (e: React.FormEvent) => {
        e.preventDefault();
        if (window.confirm("Çıkış yapmak istediğinize emin misiniz?")) {
            await onLogout();
        }
    };

    return (
        <form onSubmit={handleLogout}>
            <button type="submit" className="btn btn-ghost btn-sm">
                Çıkış
            </button>
        </form>
    );
}
