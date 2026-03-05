"use client";

import { useEffect, useRef } from "react";
import type { ArenaMessage } from "../types";

const T = {
  teal: "#00B4CC",
  glass: "rgba(255,255,255,0.04)",
  glassBorder: "rgba(255,255,255,0.07)",
  text: "#E8EFF7",
  muted: "#4A6070",
  display: "'Syne', system-ui, sans-serif",
};

const AVATAR_COLORS = [
  "#00B4CC","#FF4757","#F5C842","#00E096",
  "#8B5CF6","#F97316","#06B6D4","#EC4899",
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
          from { opacity: 0; transform: translateX(-6px); }
          to   { opacity: 1; transform: translateX(0); }
        }
        .tq-chat-input::placeholder { color: #4A6070; }
        .tq-chat-input:focus { border-color: rgba(0,180,204,0.35) !important; }
        .tq-invite-btn { opacity: 0; transition: opacity 0.2s; }
        .tq-chat-bubble:hover .tq-invite-btn { opacity: 1; }
      `}</style>

      <div style={{ display: "flex", flexDirection: "column", height: "100%", gap: 8 }}>
        {/* Message list */}
        <div
          ref={listRef}
          style={{
            flex: 1, overflowY: "auto", display: "flex",
            flexDirection: "column", gap: 8,
            maskImage: "linear-gradient(to bottom, transparent, black 18%)",
            WebkitMaskImage: "linear-gradient(to bottom, transparent, black 18%)",
            paddingBottom: 4,
          }}
        >
          {messages.map((msg, i) => {
            const avatarColor = AVATAR_COLORS[msg.sender.charCodeAt(0) % AVATAR_COLORS.length];
            const isMe = msg.senderId === currentUserId;
            return (
              <div
                key={msg.id}
                className="tq-chat-bubble"
                style={{
                  display: "flex", alignItems: "flex-start", gap: 8,
                  animation: `tq-slideIn 0.25s ease-out both`,
                  animationDelay: `${Math.min(i * 0.03, 0.15)}s`,
                }}
              >
                {/* Avatar */}
                <div style={{
                  width: 26, height: 26, borderRadius: "50%", flexShrink: 0,
                  background: avatarColor,
                  display: "flex", alignItems: "center", justifyContent: "center",
                  fontSize: 11, fontWeight: 800, color: "white", fontFamily: T.display,
                }}>
                  {msg.sender.charAt(0).toUpperCase()}
                </div>

                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: "flex", alignItems: "baseline", gap: 6, marginBottom: 2 }}>
                    <span style={{
                      fontSize: 11, fontWeight: 700, fontFamily: T.display,
                      color: isMe ? T.teal : avatarColor,
                      whiteSpace: "nowrap",
                    }}>
                      {isMe ? "Sen" : msg.sender}
                    </span>
                  </div>
                  <span style={{
                    fontSize: 13, color: T.text, lineHeight: 1.45,
                    wordBreak: "break-word",
                  }}>
                    {msg.text}
                  </span>
                </div>

                {/* Invite to stage (host only) */}
                {onInviteToStage && msg.senderId && msg.senderId !== currentUserId && (
                  <button
                    className="tq-invite-btn"
                    onClick={() => onInviteToStage(msg.senderId!)}
                    title="Sahneye Davet Et"
                    style={{
                      width: 22, height: 22, borderRadius: "50%", flexShrink: 0,
                      background: "rgba(59,130,246,0.15)",
                      border: "1px solid rgba(59,130,246,0.3)",
                      color: "#60A5FA", fontSize: 10, cursor: "pointer",
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
              flex: 1, height: 40,
              background: T.glass,
              border: `1px solid ${T.glassBorder}`,
              borderRadius: 20, padding: "0 16px",
              color: T.text, fontSize: 13, outline: "none",
              fontFamily: T.display, transition: "border-color 0.2s",
            }}
          />
          <button
            onClick={onSend}
            style={{
              width: 40, height: 40, borderRadius: "50%", flexShrink: 0,
              background: `linear-gradient(135deg, #00B4CC, #008FA3)`,
              border: "none", color: "white", fontSize: 15, cursor: "pointer",
              display: "flex", alignItems: "center", justifyContent: "center",
              transition: "all 0.15s",
            }}
            onMouseOver={e => (e.currentTarget.style.filter = "brightness(1.15)")}
            onMouseOut={e => (e.currentTarget.style.filter = "none")}
          >
            ➤
          </button>
        </div>
      </div>
    </>
  );
}
