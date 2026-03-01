import React from "react";

export default function Loading() {
    return (
        <div className="container" style={{ paddingTop: "2rem", opacity: 0.6 }}>
            {/* Hero Skeleton (Static-ish) */}
            <div style={{ height: "300px", background: "var(--bg-secondary)", borderRadius: "var(--radius-lg)", marginBottom: "2rem", animation: "pulse 1.5s infinite ease-in-out" }} />

            <div style={{ display: "grid", gridTemplateColumns: "220px 1fr", gap: "2rem", alignItems: "start" }}>
                {/* Sidebar Skeleton */}
                <aside style={{
                    background: "var(--bg-card)",
                    border: "1px solid var(--border)",
                    borderRadius: "var(--radius-lg)",
                    padding: "1rem",
                }}>
                    {[...Array(12)].map((_, i) => (
                        <div key={i} style={{ height: "32px", background: "var(--bg-secondary)", borderRadius: "var(--radius-md)", marginBottom: "8px", width: i % 3 === 0 ? "80%" : "95%", animation: "pulse 1.5s infinite ease-in-out", animationDelay: `${i * 0.05}s` }} />
                    ))}
                </aside>

                {/* Main Content Skeleton */}
                <div>
                    <div style={{ height: "32px", width: "200px", background: "var(--bg-secondary)", borderRadius: "var(--radius-md)", marginBottom: "1.5rem", animation: "pulse 1.5s infinite ease-in-out" }} />

                    <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))", gap: "1rem" }}>
                        {[...Array(8)].map((_, i) => (
                            <div key={i} className="card" style={{ height: "320px", display: "flex", flexDirection: "column", overflow: "hidden", animation: "pulse 1.5s infinite ease-in-out", animationDelay: `${i * 0.1}s` }}>
                                <div style={{ flex: "0 0 180px", background: "var(--bg-secondary)" }} />
                                <div style={{ padding: "1rem", flex: 1 }}>
                                    <div style={{ height: "16px", background: "var(--bg-secondary)", borderRadius: "var(--radius-sm)", marginBottom: "8px", width: "80%" }} />
                                    <div style={{ height: "12px", background: "var(--bg-secondary)", borderRadius: "var(--radius-sm)", marginBottom: "4px", width: "100%" }} />
                                    <div style={{ height: "12px", background: "var(--bg-secondary)", borderRadius: "var(--radius-sm)", marginBottom: "16px", width: "90%" }} />
                                    <div style={{ marginTop: "auto", display: "flex", justifyContent: "space-between" }}>
                                        <div style={{ height: "20px", width: "100px", background: "var(--bg-secondary)", borderRadius: "var(--radius-sm)" }} />
                                        <div style={{ height: "18px", width: "60px", background: "var(--bg-secondary)", borderRadius: "var(--radius-sm)" }} />
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                </div>
            </div>

            <style dangerouslySetInnerHTML={{
                __html: `
        @keyframes pulse {
          0% { opacity: 0.5; }
          50% { opacity: 0.8; }
          100% { opacity: 0.5; }
        }
      `}} />
        </div>
    );
}
