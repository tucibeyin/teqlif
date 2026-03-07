"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import Image from "next/image";

interface LiveStream {
  type: "channel" | "ad";
  roomId: string;
  hostId?: string;
  adId?: string;
  hostName: string;
  title: string;
  imageUrl: string | null;
  viewerCount: number;
}

export default function LiveStories() {
  const [streams, setStreams] = useState<LiveStream[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/live-streams")
      .then((r) => r.json())
      .then((data) => setStreams(data?.streams ?? []))
      .catch(() => setStreams([]))
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <LiveStoriesSkeleton />;
  if (streams.length === 0) return null;

  return (
    <>
      <style>{`
        @keyframes liveStoriesPulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }
        .live-stories-scroll {
          display: flex;
          gap: 0.75rem;
          overflow-x: auto;
          padding: 0.5rem 1rem 1rem;
          scrollbar-width: none;
          -ms-overflow-style: none;
          -webkit-overflow-scrolling: touch;
        }
        .live-stories-scroll::-webkit-scrollbar { display: none; }
      `}</style>

      <div className="container" style={{ paddingTop: "1.75rem", paddingBottom: "0.5rem" }}>
        <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", marginBottom: "0.75rem" }}>
          <span style={{
            display: "inline-block", width: "9px", height: "9px", borderRadius: "50%",
            background: "#ef4444", animation: "liveStoriesPulse 1.5s infinite",
          }} />
          <span style={{ fontSize: "1rem", fontWeight: 700, color: "var(--text-primary)" }}>
            🔥 Şu An Canlı
          </span>
          <span style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginLeft: "0.25rem" }}>
            {streams.length} yayın
          </span>
        </div>

        <div className="live-stories-scroll">
          {streams.map((stream) => {
            const href =
              stream.type === "channel"
                ? `/live/${stream.hostId}`
                : `/ad/${stream.adId}`;
            const badgeLabel =
              stream.viewerCount > 0 ? `👁 ${stream.viewerCount}` : "CANLI";

            return (
              <Link
                key={stream.roomId}
                href={href}
                style={{ textDecoration: "none", flexShrink: 0, width: "76px" }}
              >
                <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: "6px" }}>
                  {/* Gradient ring */}
                  <div style={{
                    width: "72px", height: "72px", borderRadius: "50%",
                    background: "linear-gradient(135deg, #ef4444 0%, #ec4899 40%, #8b5cf6 70%, #00b4cc 100%)",
                    padding: "2.5px", flexShrink: 0,
                  }}>
                    <div style={{
                      width: "100%", height: "100%", borderRadius: "50%",
                      background: "var(--bg-card)", padding: "2px",
                    }}>
                      <div style={{ position: "relative", width: "100%", height: "100%", borderRadius: "50%", overflow: "hidden", background: "var(--bg-secondary)" }}>
                        {stream.imageUrl ? (
                          <Image
                            src={stream.imageUrl}
                            alt={stream.hostName}
                            fill
                            sizes="60px"
                            style={{ objectFit: "cover" }}
                          />
                        ) : (
                          <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", fontSize: "1.5rem" }}>
                            📹
                          </div>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Badge */}
                  <span style={{
                    fontSize: "0.65rem", fontWeight: 800, lineHeight: 1,
                    background: "#ef4444", color: "#fff",
                    padding: "2px 6px", borderRadius: "100px",
                    letterSpacing: "0.03em", whiteSpace: "nowrap",
                    boxShadow: "0 1px 4px rgba(239,68,68,0.4)",
                  }}>
                    {badgeLabel}
                  </span>

                  {/* Name */}
                  <span style={{
                    fontSize: "0.72rem", fontWeight: 500, color: "var(--text-secondary)",
                    maxWidth: "72px", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
                    textAlign: "center", display: "block",
                  }}>
                    {stream.hostName.split(" ")[0]}
                  </span>
                </div>
              </Link>
            );
          })}
        </div>
      </div>
    </>
  );
}

function LiveStoriesSkeleton() {
  return (
    <>
      <style>{`
        @keyframes liveStoriesShimmer {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.35; }
        }
      `}</style>
      <div className="container" style={{ paddingTop: "1.75rem", paddingBottom: "0.5rem" }}>
        <div style={{ width: "120px", height: "18px", borderRadius: "6px", background: "var(--bg-secondary)", marginBottom: "1rem", animation: "liveStoriesShimmer 1.4s ease-in-out infinite" }} />
        <div style={{ display: "flex", gap: "0.75rem", padding: "0.5rem 0 1rem" }}>
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} style={{ flexShrink: 0, display: "flex", flexDirection: "column", alignItems: "center", gap: "6px" }}>
              <div style={{
                width: "72px", height: "72px", borderRadius: "50%",
                background: "var(--bg-secondary)", animation: `liveStoriesShimmer 1.4s ease-in-out ${i * 0.1}s infinite`,
              }} />
              <div style={{ width: "36px", height: "14px", borderRadius: "100px", background: "var(--bg-secondary)", animation: `liveStoriesShimmer 1.4s ease-in-out ${i * 0.1}s infinite` }} />
              <div style={{ width: "48px", height: "10px", borderRadius: "4px", background: "var(--bg-secondary)", animation: `liveStoriesShimmer 1.4s ease-in-out ${i * 0.1}s infinite` }} />
            </div>
          ))}
        </div>
      </div>
    </>
  );
}
