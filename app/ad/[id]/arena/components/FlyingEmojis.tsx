"use client";

import type { Reaction } from "../types";

const T = {
  glass: "rgba(255,255,255,0.05)",
  glassBorder: "rgba(255,255,255,0.08)",
};

const EMOJIS = ["❤️", "🔥", "😍", "💸", "👏"];

// ── Flying emoji overlay on video ─────────────────────────────────────────
interface FlyingEmojisProps {
  reactions: Reaction[];
}

export function FlyingEmojis({ reactions }: FlyingEmojisProps) {
  return (
    <>
      <style>{`
        @keyframes tq-floatUp {
          0%   { transform: translateY(0) scale(1);   opacity: 1; }
          100% { transform: translateY(-220px) scale(1.6); opacity: 0; }
        }
      `}</style>
      {reactions.map(r => (
        <div
          key={r.id}
          style={{
            position: "absolute", bottom: "18%", left: `${r.left}%`,
            fontSize: "2.2rem", pointerEvents: "none", zIndex: 300,
            animation: "tq-floatUp 2.5s ease-out forwards",
            filter: "drop-shadow(0 0 8px rgba(255,255,255,0.3))",
          }}
        >
          {r.emoji}
        </div>
      ))}
    </>
  );
}

// ── Reaction bar ───────────────────────────────────────────────────────────
interface ReactionBarProps {
  onReact: (emoji: string) => void;
}

export function ReactionBar({ onReact }: ReactionBarProps) {
  return (
    <>
      <style>{`
        .tq-emoji-btn {
          width: 40px; height: 40px; border-radius: 50%;
          background: rgba(255,255,255,0.05);
          border: 1px solid rgba(255,255,255,0.08);
          font-size: 18px; cursor: pointer;
          display: flex; align-items: center; justify-content: center;
          transition: all 0.15s; user-select: none;
        }
        .tq-emoji-btn:hover {
          background: rgba(255,255,255,0.12);
          transform: scale(1.15);
        }
        .tq-emoji-btn:active { transform: scale(0.88); }
      `}</style>
      <div style={{ display: "flex", gap: 6 }}>
        {EMOJIS.map(emoji => (
          <button
            key={emoji}
            className="tq-emoji-btn"
            onClick={() => onReact(emoji)}
          >
            {emoji}
          </button>
        ))}
      </div>
    </>
  );
}
