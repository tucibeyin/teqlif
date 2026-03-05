"use client";

import { useEffect, useRef } from "react";
import type { ArenaMessage } from "../types";

const T = {
  glass:       "rgba(255,255,255,0.03)",
  glassBorder: "rgba(255,255,255,0.06)",
  teal:        "#06C8E0",
  tealDark:    "#059AAF",
  text:        "#EDF2F7",
  muted:       "#3D526A",
  display:     "'Syne', system-ui, sans-serif",
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
  onInviteToStage?: (userId: string) => void;
}

export function ChatOverlay({
  messages, inputValue, onInputChange, onSend, currentUserId, onInviteToStage,
}: ChatOverlayProps) {
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight;
  }, [messages]);

  return (
    <>
      <style>{`
        @keyframes tq-slideIn {
          from { opacity: 0; transform: translateX(-8px); }
          to   { opacity: 1; transform: translateX(0); }
        }
        .tq-chat-input::placeholder { color: #3D526A; font-family: 'Syne', system-ui, sans-serif; }
        .tq-chat-input:focus {
          border-color: rgba(6,200,224,0.35) !important;
          box-shadow: 0 0 0 3px rgba(6,200,224,0.07) !important;
          outline: none;
        }
        .tq-invite-btn { opacity: 0; transition: opacity 0.2s; }
        .tq-chat-bubble:hover .tq-invite-btn { opacity: 1; }
        .tq-send-btn:hover { filter: brightness(1.15); transform: scale(1.05); }
        .tq-send-btn:active { transform: scale(0.95); }
      `}</style>

      <div style={{ display: "flex", flexDirection: "column", height: "100%", gap: 8 }}>

        {/* Message list */}
        <div
          ref={listRef}
          style={{
            flex: 1, overflowY: "auto", display: "flex",
            flexDirection: "column", gap: 6,
            maskImage: "linear-gradient(to bottom, transparent, black 25%)",
            WebkitMaskImage: "linear-gradient(to bottom, transparent, black 25%)",
            paddingBottom: 4,
          }}
        >
          {messages.map((msg, i) => {
            const avatarColor = AVATAR_COLORS[msg.sender.charCodeAt(0) % AVATAR_COLORS.length];
            const isMe = msg.senderId === currentUserId;
            const isSystem = msg.sender === "Sistem";
            return (
              <div
                key={msg.id}
                className="tq-chat-bubble"
                style={{
                  display: "flex", alignItems: "flex-start", gap: 8,
                  padding: "6px 8px", borderRadius: 10,
                  background: isSystem
                    ? "rgba(6,200,224,0.07)"
                    : "rgba(255,255,255,0.02)",
                  border: isSystem
                    ? "1px solid rgba(6,200,224,0.15)"
                    : "1px solid transparent",
                  animation: "tq-slideIn 0.22s ease-out both",
                  animationDelay: `${Math.min(i * 0.025, 0.12)}s`,
                }}
              >
                {/* Avatar */}
                {!isSystem && (
                  <div style={{
                    width: 24, height: 24, borderRadius: "50%", flexShrink: 0,
                    background: isMe
                      ? `linear-gradient(135deg, ${T.teal}, ${T.tealDark})`
                      : avatarColor,
                    display: "flex", alignItems: "center", justifyContent: "center",
                    fontSize: 10, fontWeight: 900, color: "white", fontFamily: T.display,
                  }}>
                    {msg.sender.charAt(0).toUpperCase()}
                  </div>
                )}

                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: "flex", alignItems: "baseline", gap: 5, marginBottom: 1 }}>
                    <span style={{
                      fontSize: 10, fontWeight: 800, fontFamily: T.display,
                      color: isSystem ? T.teal : (isMe ? T.teal : avatarColor),
                      whiteSpace: "nowrap", letterSpacing: 0.3,
                    }}>
                      {isSystem ? "⚡ Sistem" : (isMe ? "Sen" : msg.sender)}
                    </span>
                  </div>
                  <span style={{
                    fontSize: 12.5, color: isSystem ? T.teal : T.text,
                    lineHeight: 1.45, wordBreak: "break-word",
                    fontFamily: T.display,
                  }}>
                    {msg.text}
                  </span>
                </div>

                {/* Invite to stage (host only) */}
                {onInviteToStage && msg.senderId && msg.senderId !== currentUserId && !isSystem && (
                  <button
                    className="tq-invite-btn"
                    onClick={() => onInviteToStage(msg.senderId!)}
                    title="Sahneye Davet Et"
                    style={{
                      width: 22, height: 22, borderRadius: "50%", flexShrink: 0,
                      background: "rgba(99,102,241,0.15)",
                      border: "1px solid rgba(99,102,241,0.3)",
                      color: "#818CF8", fontSize: 10, cursor: "pointer",
                      display: "flex", alignItems: "center", justifyContent: "center",
                    }}
                  >
                    🎤
                  </button>
                )}
              </div>
            );
          })}
        </div>

        {/* Input */}
        <div style={{ display: "flex", gap: 8, flexShrink: 0 }}>
          <input
            value={inputValue}
            onChange={e => onInputChange(e.target.value)}
            onKeyDown={e => e.key === "Enter" && onSend()}
            placeholder="Mesaj yaz..."
            className="tq-chat-input"
            style={{
              flex: 1, height: 42,
              background: T.glass,
              border: `1px solid ${T.glassBorder}`,
              borderRadius: 22, padding: "0 16px",
              color: T.text, fontSize: 13, outline: "none",
              fontFamily: T.display, transition: "border-color 0.2s, box-shadow 0.2s",
            }}
          />
          <button
            className="tq-send-btn"
            onClick={onSend}
            style={{
              width: 42, height: 42, borderRadius: "50%", flexShrink: 0,
              background: `linear-gradient(135deg, ${T.teal}, ${T.tealDark})`,
              border: "none", color: "white", cursor: "pointer",
              display: "flex", alignItems: "center", justifyContent: "center",
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
