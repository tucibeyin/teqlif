"use client";

import { useEffect, useRef, useState } from "react";
import type { ArenaMessage } from "../types";
import { censorProfanity } from "@/lib/profanity";

const T = {
  glass: "rgba(255,255,255,0.03)",
  glassBorder: "rgba(255,255,255,0.06)",
  teal: "#06C8E0",
  tealDark: "#059AAF",
  text: "#EDF2F7",
  muted: "#3D526A",
  display: "'Syne', system-ui, sans-serif",
};

const AVATAR_COLORS = [
  "#06C8E0", "#F03E3E", "#F0B429", "#10D88A",
  "#8B5CF6", "#F97316", "#06B6D4", "#EC4899",
];

interface ChatOverlayProps {
  messages: ArenaMessage[];
  inputValue: string;
  onInputChange: (val: string) => void;
  onSend: () => void;
  currentUserId?: string;
  isOwner?: boolean;
  adId?: string;
  onInviteToStage?: (userId: string) => void;
}

export function ChatOverlay({
  messages, inputValue, onInputChange, onSend, currentUserId, isOwner, adId, onInviteToStage,
}: ChatOverlayProps) {
  const listRef = useRef<HTMLDivElement>(null);
  const [selectedUser, setSelectedUser] = useState<{ id: string, name: string } | null>(null);
  const [isModerating, setIsModerating] = useState(false);

  const handleModerate = async (action: 'kick' | 'mute') => {
    if (!selectedUser || !adId) return;

    setIsModerating(true);
    try {
      const res = await fetch('/api/livekit/moderate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ roomId: adId, identity: selectedUser.id, action }),
      });

      const data = await res.json();
      if (res.ok) {
        alert(action === 'kick' ? `${selectedUser.name} odadan atıldı.` : `${selectedUser.name} susturuldu.`);
        setSelectedUser(null);
      } else {
        alert("Hata: " + (data.error || "İşlem başarısız."));
      }
    } catch (e) {
      console.error(e);
      alert("Sunucuya bağlanılamadı.");
    } finally {
      setIsModerating(false);
    }
  };

  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight;
  }, [messages]);

  return (
    <>
      <style>{`
        @keyframes tq-slideIn {
          from { opacity: 0; transform: translateX(-6px); }
          to   { opacity: 1; transform: translateX(0); }
        }
        .tq-chat-input::placeholder { color: #3D526A; font-family: 'Syne', system-ui, sans-serif; }
        .tq-chat-input:focus {
          border-color: rgba(6,200,224,0.35) !important;
          box-shadow: 0 0 0 3px rgba(6,200,224,0.07) !important;
          outline: none;
        }
        .tq-chat-row:hover { background: rgba(255,255,255,0.03) !important; }
        .tq-invite-btn { opacity: 0; transition: opacity 0.2s; }
        .tq-chat-row:hover .tq-invite-btn { opacity: 1; }
        .tq-send-btn:hover { filter: brightness(1.15); transform: scale(1.05); }
        .tq-send-btn:active { transform: scale(0.95); }
      `}</style>

      {/* Outer: flex: 1 ile parent flex container'ı doldurur */}
      <div
        id="arena-chat-overlay"
        style={{ display: "flex", flexDirection: "column", flex: 1, gap: 8 }}>

        {/* ── Message list ── */}
        {/*
          Twitch-style: flex spacer + column layout.
          Spacer (flex:1) mesajları alta ittiriyor.
          Mask gradient yalnızca üst boşluğu etkiler, mesajlar alt %80'de görünür.
        */}
        <div
          ref={listRef}
          style={{
            flex: 1,
            overflowY: "auto",
            display: "flex",
            flexDirection: "column",
            gap: 1,
            maskImage: "linear-gradient(to bottom, transparent, black 20%)",
            WebkitMaskImage: "linear-gradient(to bottom, transparent, black 20%)",
            paddingBottom: 4,
          }}
        >
          {/* Spacer — mesajları div'in altına iter */}
          <div style={{ flex: 1, minHeight: 0 }} />

          {messages.length === 0 ? (
            /* Boş durum */
            <div style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 8,
              padding: "20px 8px",
              opacity: 0.42,
              pointerEvents: "none",
            }}>
              <span style={{ fontSize: 24 }}>💬</span>
              <span style={{
                fontSize: 11,
                color: T.muted,
                fontFamily: T.display,
                textAlign: "center",
                lineHeight: 1.7,
              }}>
                Henüz mesaj yok.<br />Sohbeti başlatan sen ol!
              </span>
            </div>
          ) : (
            messages.map((msg, i) => {
              const avatarColor = AVATAR_COLORS[msg.sender.charCodeAt(0) % AVATAR_COLORS.length];
              const isMe = msg.senderId === currentUserId;
              const isSystem = msg.sender === "Sistem";
              const canModerate = isOwner && !isMe && !isSystem && msg.senderId;

              return (
                <div
                  key={msg.id}
                  className="tq-chat-row"
                  style={{
                    display: "flex",
                    flexWrap: "wrap",
                    alignItems: "baseline",
                    gap: 4,
                    padding: "3px 8px",
                    borderRadius: 4,
                    background: isSystem ? "rgba(6,200,224,0.05)" : "transparent",
                    transition: "background 0.15s",
                    animation: "tq-slideIn 0.2s ease-out both",
                    animationDelay: `${Math.min(i * 0.02, 0.1)}s`,
                    position: "relative",
                  }}
                >
                  {/* Kullanıcı adı */}
                  <span
                    onClick={() => canModerate ? setSelectedUser({ id: msg.senderId!, name: msg.sender }) : null}
                    style={{
                      fontFamily: T.display,
                      fontWeight: 700,
                      fontSize: 12,
                      color: isSystem ? T.teal : (isMe ? T.teal : avatarColor),
                      whiteSpace: "nowrap",
                      flexShrink: 0,
                      letterSpacing: 0.2,
                      cursor: canModerate ? "pointer" : "default",
                      textDecoration: canModerate ? "underline dotted rgba(255,255,255,0.2)" : "none",
                    }}
                    title={canModerate ? "Moderasyon Seçenekleri" : undefined}
                  >
                    {isSystem ? "⚡ Sistem" : (isMe ? "Sen" : msg.sender)}
                  </span>

                  {/* Ayraç */}
                  <span style={{
                    color: "rgba(255,255,255,0.28)",
                    fontWeight: 400,
                    fontSize: 12,
                    flexShrink: 0,
                  }}>:</span>

                  {/* Mesaj metni */}
                  <span style={{
                    fontFamily: T.display,
                    fontSize: 13,
                    color: isSystem ? T.teal : T.text,
                    lineHeight: 1.5,
                    wordBreak: "break-word",
                    flex: 1,
                  }}>
                    {censorProfanity(msg.text)}
                  </span>

                  {/* Sahneye davet (sadece host) */}
                  {onInviteToStage && msg.senderId && msg.senderId !== currentUserId && !isSystem && (
                    <button
                      className="tq-invite-btn"
                      onClick={() => onInviteToStage(msg.senderId!)}
                      title="Sahneye Davet Et"
                      style={{
                        width: 20,
                        height: 20,
                        borderRadius: "50%",
                        flexShrink: 0,
                        background: "rgba(99,102,241,0.15)",
                        border: "1px solid rgba(99,102,241,0.3)",
                        color: "#818CF8",
                        fontSize: 10,
                        cursor: "pointer",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                      }}
                    >
                      🎤
                    </button>
                  )}

                  {/* Moderation Menu (Floating for selected user) */}
                  {selectedUser && selectedUser.id === msg.senderId && (
                    <div style={{
                      position: "absolute",
                      left: 10,
                      top: 24,
                      zIndex: 1000,
                      background: "#1A202C",
                      border: "1px solid rgba(255,255,255,0.1)",
                      borderRadius: 8,
                      boxShadow: "0 10px 25px rgba(0,0,0,0.5)",
                      padding: 6,
                      display: "flex",
                      flexDirection: "column",
                      gap: 4,
                      minWidth: 120,
                    }}>
                      <div style={{ fontSize: 10, color: T.muted, padding: "2px 6px", borderBottom: "1px solid rgba(255,255,255,0.05)", marginBottom: 2 }}>
                        {selectedUser.name} Yönet
                      </div>
                      <button
                        disabled={isModerating}
                        onClick={() => handleModerate('mute')}
                        style={{ background: "transparent", border: "none", color: "#F6E05E", fontSize: 12, padding: "6px", textAlign: "left", cursor: "pointer", borderRadius: 4 }}
                      >
                        🔇 Sustur
                      </button>
                      <button
                        disabled={isModerating}
                        onClick={() => handleModerate('kick')}
                        style={{ background: "transparent", border: "none", color: "#F56565", fontSize: 12, padding: "6px", textAlign: "left", cursor: "pointer", borderRadius: 4 }}
                      >
                        ⛔ Odadan At
                      </button>
                      <button
                        onClick={() => setSelectedUser(null)}
                        style={{ background: "transparent", border: "none", color: T.muted, fontSize: 11, padding: "4px", textAlign: "center", cursor: "pointer", marginTop: 2 }}
                      >
                        İptal
                      </button>
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>

        {/* ── Input ── */}
        <div style={{ display: "flex", gap: 8, flexShrink: 0 }}>
          <input
            value={inputValue}
            onChange={e => onInputChange(e.target.value)}
            onKeyDown={e => e.key === "Enter" && onSend()}
            placeholder="Mesaj yaz..."
            className="tq-chat-input"
            style={{
              flex: 1,
              height: 42,
              background: T.glass,
              border: `1px solid ${T.glassBorder}`,
              borderRadius: 22,
              padding: "0 16px",
              color: T.text,
              fontSize: 13,
              outline: "none",
              fontFamily: T.display,
              transition: "border-color 0.2s, box-shadow 0.2s",
            }}
          />
          <button
            className="tq-send-btn"
            onClick={onSend}
            style={{
              width: 42,
              height: 42,
              borderRadius: "50%",
              flexShrink: 0,
              background: `linear-gradient(135deg, ${T.teal}, ${T.tealDark})`,
              border: "none",
              color: "white",
              cursor: "pointer",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              transition: "all 0.15s",
              boxShadow: "0 4px 14px rgba(6,200,224,0.3)",
              fontSize: 15,
            }}
          >
            ↑
          </button>
        </div>
      </div>
    </>
  );
}
